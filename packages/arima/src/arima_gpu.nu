// arima_gpu.nu — the batch evaluator on a GPU, bit-for-bit the CPU's.
//
// A fit asks for its likelihoods in rounds (src/arima.nu: the optimizer
// as a state machine), and K fits at once ask for K rounds together. This
// module answers such a round with one kernel launch: every item — a
// series, a method, a parameter vector — is one thread that runs the
// same filter the CPU runs, in the same order, with every operation
// rounded once (`__dadd_rn` and friends, never fused), so the value it
// returns is the value the CPU would have returned. The gain is the
// breadth: many series (a detector with a model per feature), or many
// candidate orders, in the time of one.
//
// What stays on the host, and why: the transform from raw parameters to
// polynomials and the start of the model's stationary covariance (small,
// and they use libm — the device's `log` and `exp` are not the host's);
// and the sum of the innovation variances' logarithms, which the kernel
// hands back as the variances themselves. Only the filter's arithmetic —
// the Chandrasekhar recursions, O(n · r) — runs on the device.
//
// Selection: any `gpu` backend — a CUDA device, or the package's host
// C++ backend (`NURL_GPU=cpu`) — gives the same numbers, so the choice is
// pace, never result. `arima_fit_many_gpu` falls back to the threaded CPU
// evaluator when no kit opens.
//
//   ( arima_gpu_available )                         → b
//   ( arima_fit_many_gpu series spec method )       → ( Vec ArimaModel )
//   ( arima_eval_gpu kit items ctxs out )           the evaluator itself

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `arima.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/checked.nu`

// ── the kernels ───────────────────────────────────────────────────────
//
// meta, per item, 8 long longs:
//   [0] w_off   [1] n   [2] r (ML) / p' (CSS)   [3] f_off (ML) / ncond (CSS)
//   [4] rmax (ML) / scratch_off (CSS)   [5] poly_off   [6] p0_off   [7] q' (CSS)
// The two kernels, in gpukit's checked subset (gpukit/src/checked.nu): one
// thread per item (`gid`), every access an LD / ST of a buffer the call
// bound. arima_ml runs the Chandrasekhar recursions, O(r) a step, in the
// host's order (_ar_filter_arma) with every operation rounded once; p0s
// holds P e0 (r values) per item, and the four working vectors live in
// scratch interleaved across the items (element i of item it at
// [i * n_items + it], rmax rows each, meta[4] = rmax) so that the threads
// of a warp touch neighbouring addresses; the state is updated in place
// (ascending, so A[i+1] is still the old value when A[i] is written) and
// each new gain is stored and reused rather than read back. arima_css is the conditional sum
// of squares.
@ _ag_ml_body → s {
    ^ `long long it = gid;
long long woff = LD(meta, it * 8), n = LD(meta, it * 8 + 1), r = LD(meta, it * 8 + 2), foff = LD(meta, it * 8 + 3);
long long rmax = LD(meta, it * 8 + 4), poff = LD(meta, it * 8 + 5), p0off = LD(meta, it * 8 + 6);
double mu = LD(mus, it);
long long S = n_items;
long long A = it;
long long K = A + rmax * S;
long long W = K + rmax * S;
long long O = W + rmax * S;
long long i, t;
double F = LD(p0s, p0off);
if (!(F > 0.0)) { ST(ssq_out, it, 0.0); ST(ok_out, it, 0); return; }
for (i = 0; i < r; i++) {
    double v = __dmul_rn(LD(polys, poff + i), LD(p0s, p0off));
    if (i + 1 < r) v = __dadd_rn(v, LD(p0s, p0off + i + 1));
    ST(scratch, K + i * S, __ddiv_rn(v, F));
    ST(scratch, W + i * S, LD(scratch, K + i * S));
    ST(scratch, A + i * S, 0.0);
}
double M = __dsub_rn(0.0, F);
int frozen = 0, ok = 1;
double ssq = 0.0;
for (t = 0; t < n; t++) {
    double a0 = LD(scratch, A);
    double v = __dsub_rn(__dsub_rn(LD(series, woff + t), mu), a0);
    ssq = __dadd_rn(ssq, __ddiv_rn(__dmul_rn(v, v), F));
    ST(f_out, foff + t, F);
    for (i = 0; i < r; i++) {
        double x = __dmul_rn(LD(polys, poff + i), a0);
        if (i + 1 < r) x = __dadd_rn(x, LD(scratch, A + (i + 1) * S));
        ST(scratch, A + i * S, __dadd_rn(x, __dmul_rn(LD(scratch, K + i * S), v)));
    }
    if (!frozen) {
        double w0 = LD(scratch, W);
        double fn = __dadd_rn(F, __dmul_rn(__dmul_rn(w0, w0), M));
        double wmax = 0.0;
        for (i = 0; i < r; i++) {
            double x = __dmul_rn(LD(polys, poff + i), w0);
            if (i + 1 < r) x = __dadd_rn(x, LD(scratch, W + (i + 1) * S));
            ST(scratch, O + i * S, x);
            double aw = fabs(LD(scratch, W + i * S));
            if (aw > wmax) wmax = aw;
        }
        if (__dmul_rn(fabs(M), __dmul_rn(wmax, wmax)) <= __dmul_rn(1e-14, __dadd_rn(1.0, F))) frozen = 1;
        else if (fn > 0.0) {
            for (i = 0; i < r; i++) {
                double o = LD(scratch, O + i * S);
                double kn = __ddiv_rn(__dadd_rn(__dmul_rn(LD(scratch, K + i * S), F), __dmul_rn(__dmul_rn(o, M), w0)), fn);
                ST(scratch, K + i * S, kn);
                ST(scratch, W + i * S, __dsub_rn(o, __dmul_rn(kn, w0)));
            }
            M = __dadd_rn(M, __ddiv_rn(__dmul_rn(__dmul_rn(M, w0), __dmul_rn(M, w0)), F));
            F = fn;
        } else { ok = 0; break; }
    }
}
ST(ssq_out, it, ssq);
ST(ok_out, it, ok);`
}

@ _ag_css_body → s {
    ^ `long long it = gid;
long long woff = LD(meta, it * 8), n = LD(meta, it * 8 + 1), pf = LD(meta, it * 8 + 2), nc = LD(meta, it * 8 + 3);
long long soff = LD(meta, it * 8 + 4), poff = LD(meta, it * 8 + 5), qf = LD(meta, it * 8 + 7);
if (nc < pf) nc = pf;
double mu = LD(mus, it);
double ssq = 0.0;
long long t, i, j;
for (t = 0; t < n; t++) ST(scratch, soff + t, 0.0);
for (t = nc; t < n; t++) {
    double v = __dsub_rn(LD(series, woff + t), mu);
    for (i = 0; i < pf; i++) if (LD(polys, poff + i) != 0.0) v = __dsub_rn(v, __dmul_rn(LD(polys, poff + i), __dsub_rn(LD(series, woff + t - i - 1), mu)));
    for (j = 0; j < qf; j++) if (LD(polys, poff + pf + j) != 0.0) { long long at = t - j - 1; if (at >= nc) v = __dsub_rn(v, __dmul_rn(LD(polys, poff + pf + j), LD(scratch, soff + at))); }
    ST(scratch, soff + t, v);
    ssq = __dadd_rn(ssq, __dmul_rn(v, v));
}
ST(ssq_out, it, ssq);`
}

// ── the evaluator ─────────────────────────────────────────────────────

// Trace each round's phases (host preparation, the launches, the folds)
// to stderr — for tuning, off by default.
: ~ b g_ag_trace F

@ arima_gpu_set_trace b on → v { = g_ag_trace on }

: ~ i g_ag_t_prep 0
: ~ i g_ag_t_run 0
: ~ i g_ag_t_post 0
: ~ i g_ag_rounds 0

@ arima_gpu_trace_report → v {
    ( nurl_eprint `arima gpu: rounds=` ) ( nurl_eprint_int g_ag_rounds )
    ( nurl_eprint ` prep_ms=` ) ( nurl_eprint_int g_ag_t_prep )
    ( nurl_eprint ` run_ms=` ) ( nurl_eprint_int g_ag_t_run )
    ( nurl_eprint ` post_ms=` ) ( nurl_eprint_int g_ag_t_post ) ( nurl_eprint `\n` )
    = g_ag_rounds 0 = g_ag_t_prep 0 = g_ag_t_run 0 = g_ag_t_post 0
}

@ arima_gpu_available → b {
    : GpuKit kit ( gk_open_best )
    : b ok ( gk_ok kit )
    ^ ok
}

// One round on the device: the ML items in one launch, the CSS items in
// another, each item's number folded on the host from what came back.
@ arima_eval_gpu GpuKit kit ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) out → v {
    : i t_start ( now_ms )
    = g_ag_rounds + g_ag_rounds 1
    // the series, each context's once
    : ~ ( Vec f ) series ( vec_new [f] )
    : ( Vec i ) woff ( vec_new [i] )
    : i nctx ( vec_len [ArimaCtx] ctxs )
    : ~ i c 0
    ~ < c nctx {
        ?? ( vec_get [ArimaCtx] ctxs c ) {
            T cx → {
                ( vec_push [i] woff ( vec_len [f] series ) )
                ( vec_extend [f] series ( arc_get [( Vec f )] . cx w ) )
            }
            F _ → {}
        }
        = c + c 1
    }
    : i m ( vec_len [ArimaEvalItem] items )
    : ( Slice f ) pout ( slice_from_vec [f] out )
    // Every item's state-space form, prepared on the pool: the transform,
    // the expansion and the start of the stationary covariance are the
    // host's part.
    : ( Vec ArimaJob ) pjobs ( vec_new [ArimaJob] )
    : ~ i big 0
    : ~ i k 0
    ~ < k m {
        ?? ( vec_get [ArimaEvalItem] items k ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → {
                        : i kind ? == . cx method ARIMA_ML ? == . it kind 1 3 2 ? == . it kind 1 5 4
                        ( vec_push [ArimaJob] pjobs ( _ar_job . cx sp . cx w . cx method . cx ncond . it raw kind ) )
                        : ArimaSpec csp . cx sp
                        : i pf + . csp p * . csp s . csp P
                        : i qf + . csp q * . csp s . csp Q
                        : ~ i r pf
                        ? > + qf 1 r { = r + qf 1 } {}
                        : i wk * r r
                        ? > wk big { = big wk } {}
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : ( Vec ArimaPrep ) preps ( _ar_jobs_prep pjobs > * big m 2000000 )
    // ML items
    : ( Vec i ) ml_idx ( vec_new [i] )
    : ( Vec i ) meta ( vec_new [i] )
    : ( Vec f ) polys ( vec_new [f] )
    : ( Vec f ) p0s ( vec_new [f] )
    : ( Vec f ) mus ( vec_new [f] )
    : ~ i f_total 0
    : ~ i rmax 0
    // CSS items
    : ( Vec i ) css_idx ( vec_new [i] )
    : ( Vec i ) cmeta ( vec_new [i] )
    : ( Vec f ) cpolys ( vec_new [f] )
    : ( Vec f ) cmus ( vec_new [f] )
    : ~ i cs_total 0
    = k 0
    ~ < k m {
        ?? ( vec_get [ArimaEvalItem] items k ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → {
                        : ArimaPrep pr ( vec_at [ArimaPrep] preps k )
                        : i n ( vec_len [f] ( arc_get [( Vec f )] . cx w ) )
                        : i wo ( _ar_geti woff . it ctx )
                        ? == . cx method ARIMA_ML {
                            ? . pr ok {
                                : i r . pr r
                                ( vec_push [i] ml_idx k )
                                ( vec_push [i] meta wo ) ( vec_push [i] meta n ) ( vec_push [i] meta r )
                                ( vec_push [i] meta f_total ) ( vec_push [i] meta 0 )
                                ( vec_push [i] meta ( vec_len [f] polys ) ) ( vec_push [i] meta ( vec_len [f] p0s ) ) ( vec_push [i] meta 0 )
                                ( vec_extend_range [f] polys . pr phi 0 r )
                                ( vec_extend_range [f] polys . pr theta 0 r )
                                ( vec_extend_range [f] p0s . pr p0 0 r )
                                ( vec_push [f] mus . pr mu )
                                = f_total + f_total n
                                ? > r rmax { = rmax r } {}
                            } { ( slice_put [f] pout k 1000000000000.0 ) }
                        } {
                            : i pf ( vec_len [f] . pr ar )
                            : i qf ( vec_len [f] . pr ma )
                            ? > n pf {
                                ( vec_push [i] css_idx k )
                                ( vec_push [i] cmeta wo ) ( vec_push [i] cmeta n ) ( vec_push [i] cmeta pf )
                                ( vec_push [i] cmeta . cx ncond ) ( vec_push [i] cmeta cs_total )
                                ( vec_push [i] cmeta ( vec_len [f] cpolys ) ) ( vec_push [i] cmeta 0 ) ( vec_push [i] cmeta qf )
                                ( vec_extend_range [f] cpolys . pr ar 0 pf )
                                ( vec_extend_range [f] cpolys . pr ma 0 qf )
                                ( vec_push [f] cmus . pr mu )
                                = cs_total + cs_total n
                            } { ( slice_put [f] pout k 1000000000000.0 ) }
                        }
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nml ( vec_len [i] ml_idx )
    ? > nml 0 {
        : ( Slice i ) pm4 ( slice_from_vec [i] meta )
        : ~ i q4 0
        ~ < q4 nml { ( slice_put [i] pm4 + * q4 8 4 rmax ) = q4 + q4 1 }
        : ~ GkCall call ( gk_call_new )
        ( gk_call_in_i call `meta` meta )
        ( gk_call_in_f call `series` series )
        ( gk_call_in_f call `polys` polys )
        ( gk_call_in_f call `p0s` p0s )
        ( gk_call_in_f call `mus` mus )
        ( gk_call_out_f call `scratch` ( vec_zeroed [f] * * 4 rmax nml ) )
        ( gk_call_out_f call `ssq_out` ( vec_zeroed [f] nml ) )
        ( gk_call_out_f call `f_out` ( vec_zeroed [f] f_total ) )
        ( gk_call_out_i call `ok_out` ( vec_zeroed [i] nml ) )
        ( gk_call_i64 call `n_items` nml )
        : i t_r0 ( now_ms )
        : b ran ( gk_run_checked kit call `arima_ml` ( _ag_ml_body ) nml 64 )
        = series ( gk_call_take_f call `series` )
        : ( Vec f ) ssq ( gk_call_take_f call `ssq_out` )
        : ( Vec f ) fout ( gk_call_take_f call `f_out` )
        : ( Vec i ) okv ( gk_call_take_i call `ok_out` )
        : ( Vec i ) meta2 ( gk_call_take_i call `meta` )
        = g_ag_t_run + g_ag_t_run - ( now_ms ) t_r0
        : ( Slice f ) pssq ( slice_from_vec [f] ssq )
        : ( Slice f ) pf ( slice_from_vec [f] fout )
        : ( Slice i ) pmeta ( slice_from_vec [i] meta2 )
        : ( Slice i ) pok ( slice_from_vec [i] okv )
        : ~ i q 0
        ~ < q nml {
            : i k2 ( _ar_geti ml_idx q )
            : i n ( slice_at [i] pmeta + * q 8 1 )
            : i foff ( slice_at [i] pmeta + * q 8 3 )
            : ~ f val 1000000000000.0
            ? & ran != ( slice_at [i] pok q ) 0 {
                : ~ f sumlog 0.0
                : ~ i t 0
                ~ < t n { = sumlog + sumlog ( float_log ( slice_at [f] pf + foff t ) ) = t + t 1 }
                : ArimaLik lk ( _ar_lik_ml_from ( slice_at [f] pssq q ) sumlog n )
                ? . lk ok { = val - 0.0 . lk loglik } {}
            } {}
            ( slice_put [f] pout k2 val )
            = q + q 1
        }
        = g_ag_t_post + g_ag_t_post - ( now_ms ) + t_r0 - ( now_ms ) t_r0
    } {}
    : i ncss ( vec_len [i] css_idx )
    ? > ncss 0 {
        : ~ GkCall call ( gk_call_new )
        ( gk_call_in_i call `meta` cmeta )
        ( gk_call_in_f call `series` series )
        ( gk_call_in_f call `polys` cpolys )
        ( gk_call_in_f call `mus` cmus )
        ( gk_call_out_f call `scratch` ( vec_zeroed [f] cs_total ) )
        ( gk_call_out_f call `ssq_out` ( vec_zeroed [f] ncss ) )
        ( gk_call_i64 call `n_items` ncss )
        : b ran ( gk_run_checked kit call `arima_css` ( _ag_css_body ) ncss 64 )
        : ( Vec f ) ssq ( gk_call_take_f call `ssq_out` )
        : ( Vec i ) cmeta2 ( gk_call_take_i call `meta` )
        : ( Slice f ) pssq ( slice_from_vec [f] ssq )
        : ( Slice i ) pmeta ( slice_from_vec [i] cmeta2 )
        : ~ i q 0
        ~ < q ncss {
            : i k2 ( _ar_geti css_idx q )
            : i n ( slice_at [i] pmeta + * q 8 1 )
            : i pfc ( slice_at [i] pmeta + * q 8 2 )
            : i ncq ( slice_at [i] pmeta + * q 8 3 )
            : i nc ? > ncq pfc ncq pfc
            : ~ f val 1000000000000.0
            ? ran {
                : ArimaLik lk ( _ar_lik_css_from ( slice_at [f] pssq q ) - n nc )
                ? . lk ok { = val - 0.0 . lk loglik } {}
            } {}
            ( slice_put [f] pout k2 val )
            = q + q 1
        }
    } {}
}

// K series fitted together with the device answering every round; the
// threaded CPU evaluator when no device (nor the CPU backend) opens.
@ arima_fit_many_gpu ( Vec ( Vec f ) ) series ArimaSpec sp i method → ( Vec ArimaModel ) {
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} {
        ^ ( arima_fit_many series sp method )
    }
    ( gk_bind_thread kit )
    : ( Vec ArimaModel ) out ( arima_fit_many_with series sp method \ ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) vals → v { ( arima_eval_gpu kit items ctxs vals ) } )
    ^ out
}
