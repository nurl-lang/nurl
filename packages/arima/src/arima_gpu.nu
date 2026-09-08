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
//   ( arima_fit_many_gpu series spec method )       → ( Vec *ArimaModel )
//   ( arima_eval_gpu kit items ctxs out )           the evaluator itself

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `src/arima.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`

// ── the kernels ───────────────────────────────────────────────────────
//
// meta, per item, 8 long longs:
//   [0] w_off   [1] n   [2] r (ML) / p' (CSS)   [3] f_off (ML) / ncond (CSS)
//   [4] rmax (ML) / scratch_off (CSS)   [5] poly_off   [6] p0_off   [7] q' (CSS)
@ _ag_kernel_src → s {
    ^ `#define ADD(a,b) __dadd_rn((a),(b))
#define SUB(a,b) __dsub_rn((a),(b))
#define MUL(a,b) __dmul_rn((a),(b))
#define DIV(a,b) __ddiv_rn((a),(b))
extern "C" __global__ void arima_ml(const long long* meta, const double* series, const double* polys, const double* p0s, const double* mus, double* scratch, double* ssq_out, double* f_out, long long* ok_out, long long n_items)
{
    // One thread per item: the Chandrasekhar recursions, O(r) a step,
    // in the host's order (_ar_filter_arma) with every operation rounded
    // once. p0s holds P e0 (r values) per item. The four working vectors
    // live in scratch interleaved across the items (element i of item it
    // at [i * n_items + it], rmax rows each, meta[4] = rmax) so that the
    // threads of a warp touch neighbouring addresses.
    long long it = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (it >= n_items) return;
    const long long* m = meta + it * 8;
    long long woff = m[0], n = m[1], r = m[2], foff = m[3], rmax = m[4], poff = m[5], p0off = m[6];
    const double* w = series + woff;
    const double* phi = polys + poff;
    const double* p0 = p0s + p0off;
    double mu = mus[it];
    long long S = n_items;
    double* A = scratch + it;
    double* K = A + rmax * S;
    double* W = K + rmax * S;
    double* O = W + rmax * S;
    long long i, t;
    double F = p0[0];
    if (!(F > 0.0)) { ssq_out[it] = 0.0; ok_out[it] = 0; return; }
    for (i = 0; i < r; i++) {
        double v = MUL(phi[i], p0[0]);
        if (i + 1 < r) v = ADD(v, p0[i + 1]);
        K[i * S] = DIV(v, F);
        W[i * S] = K[i * S];
        A[i * S] = 0.0;
    }
    double M = SUB(0.0, F);
    int frozen = 0, ok = 1;
    double ssq = 0.0;
    for (t = 0; t < n; t++) {
        double a0 = A[0];
        double v = SUB(SUB(w[t], mu), a0);
        ssq = ADD(ssq, DIV(MUL(v, v), F));
        f_out[foff + t] = F;
        for (i = 0; i < r; i++) {
            double x = MUL(phi[i], a0);
            if (i + 1 < r) x = ADD(x, A[(i + 1) * S]);
            O[i * S] = ADD(x, MUL(K[i * S], v));
        }
        for (i = 0; i < r; i++) A[i * S] = O[i * S];
        if (!frozen) {
            double w0 = W[0];
            double fn = ADD(F, MUL(MUL(w0, w0), M));
            double wmax = 0.0;
            for (i = 0; i < r; i++) {
                double x = MUL(phi[i], w0);
                if (i + 1 < r) x = ADD(x, W[(i + 1) * S]);
                O[i * S] = x;
                double aw = fabs(W[i * S]);
                if (aw > wmax) wmax = aw;
            }
            if (MUL(fabs(M), MUL(wmax, wmax)) <= MUL(1e-14, ADD(1.0, F))) frozen = 1;
            else if (fn > 0.0) {
                for (i = 0; i < r; i++) {
                    K[i * S] = DIV(ADD(MUL(K[i * S], F), MUL(MUL(O[i * S], M), w0)), fn);
                    W[i * S] = SUB(O[i * S], MUL(K[i * S], w0));
                }
                M = ADD(M, DIV(MUL(MUL(M, w0), MUL(M, w0)), F));
                F = fn;
            } else { ok = 0; break; }
        }
    }
    ssq_out[it] = ssq;
    ok_out[it] = ok;
}
extern "C" __global__ void arima_css(const long long* meta, const double* series, const double* polys, const double* mus, double* scratch, double* ssq_out, long long n_items)
{
    long long it = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (it >= n_items) return;
    const long long* m = meta + it * 8;
    long long woff = m[0], n = m[1], pf = m[2], nc = m[3], soff = m[4], poff = m[5], qf = m[7];
    if (nc < pf) nc = pf;
    const double* w = series + woff;
    const double* ar = polys + poff;
    const double* ma = polys + poff + pf;
    double mu = mus[it];
    double* ev = scratch + soff;
    double ssq = 0.0;
    long long t, i, j;
    for (t = 0; t < n; t++) ev[t] = 0.0;
    for (t = nc; t < n; t++) {
        double v = SUB(w[t], mu);
        for (i = 0; i < pf; i++) if (ar[i] != 0.0) v = SUB(v, MUL(ar[i], SUB(w[t - i - 1], mu)));
        for (j = 0; j < qf; j++) if (ma[j] != 0.0) { long long at = t - j - 1; if (at >= nc) v = SUB(v, MUL(ma[j], ev[at])); }
        ev[t] = v;
        ssq = ADD(ssq, MUL(v, v));
    }
    ssq_out[it] = ssq;
}
`
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
    : *GpuKit kit ( gk_open_best )
    : b ok ( gk_ok kit )
    ( gk_close kit )
    ^ ok
}

// One round on the device: the ML items in one launch, the CSS items in
// another, each item's number folded on the host from what came back.
@ arima_eval_gpu * GpuKit kit ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) out → v {
    : i t_start ( now_ms )
    = g_ag_rounds + g_ag_rounds 1
    // the series, each context's once
    : ( Vec f ) series ( vec_new [f] )
    : ( Vec i ) woff ( vec_new [i] )
    : i nctx ( vec_len [ArimaCtx] ctxs )
    : ~ i c 0
    ~ < c nctx {
        ?? ( vec_get [ArimaCtx] ctxs c ) {
            T cx → {
                ( vec_push [i] woff ( vec_len [f] series ) )
                : i n ( vec_len [f] . cx w )
                : *f pw ( vec_data [f] . cx w )
                : ~ i t 0
                ~ < t n { ( vec_push [f] series . pw t ) = t + t 1 }
            }
            F _ → {}
        }
        = c + c 1
    }
    : i m ( vec_len [ArimaEvalItem] items )
    : *f pout ( vec_data [f] out )
    // Every item's state-space form, prepared on the pool: the transform,
    // the expansion and the start of the stationary covariance are the
    // host's part.
    : ( Vec i ) pjobs ( vec_new [i] )
    : ~ i big 0
    : ~ i k 0
    ~ < k m {
        ?? ( vec_get [ArimaEvalItem] items k ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → {
                        : i kind ? == . cx method ARIMA_ML ? == . it kind 1 3 2 ? == . it kind 1 5 4
                        ( vec_push [i] pjobs ( _ar_job_new . cx sp . cx w . cx method . cx ncond . it raw out k kind ) )
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
    ( _ar_jobs_run pjobs > * big m 2000000 )
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
                        : *ArimaJob pj # *ArimaJob ( _ar_geti pjobs k )
                        : *ArimaPrep pr # *ArimaPrep . pj extra
                        : i n ( vec_len [f] . cx w )
                        : i wo ( _ar_geti woff . it ctx )
                        ? == . cx method ARIMA_ML {
                            ? . pr ok {
                                : i r . pr r
                                ( vec_push [i] ml_idx k )
                                ( vec_push [i] meta wo ) ( vec_push [i] meta n ) ( vec_push [i] meta r )
                                ( vec_push [i] meta f_total ) ( vec_push [i] meta 0 )
                                ( vec_push [i] meta ( vec_len [f] polys ) ) ( vec_push [i] meta ( vec_len [f] p0s ) ) ( vec_push [i] meta 0 )
                                : *f pphi ( vec_data [f] . pr phi )
                                : *f pth ( vec_data [f] . pr theta )
                                : *f ppm ( vec_data [f] . pr p0 )
                                : ~ i q 0
                                ~ < q r { ( vec_push [f] polys . pphi q ) = q + q 1 }
                                = q 0
                                ~ < q r { ( vec_push [f] polys . pth q ) = q + q 1 }
                                = q 0
                                ~ < q r { ( vec_push [f] p0s . ppm q ) = q + q 1 }
                                ( vec_push [f] mus . pr mu )
                                = f_total + f_total n
                                ? > r rmax { = rmax r } {}
                            } { = . pout k 1000000000000.0 }
                        } {
                            : i pf ( vec_len [f] . pr ar )
                            : i qf ( vec_len [f] . pr ma )
                            ? > n pf {
                                ( vec_push [i] css_idx k )
                                ( vec_push [i] cmeta wo ) ( vec_push [i] cmeta n ) ( vec_push [i] cmeta pf )
                                ( vec_push [i] cmeta . cx ncond ) ( vec_push [i] cmeta cs_total )
                                ( vec_push [i] cmeta ( vec_len [f] cpolys ) ) ( vec_push [i] cmeta 0 ) ( vec_push [i] cmeta qf )
                                : *f par ( vec_data [f] . pr ar )
                                : *f pma ( vec_data [f] . pr ma )
                                : ~ i q 0
                                ~ < q pf { ( vec_push [f] cpolys . par q ) = q + q 1 }
                                = q 0
                                ~ < q qf { ( vec_push [f] cpolys . pma q ) = q + q 1 }
                                ( vec_push [f] cmus . pr mu )
                                = cs_total + cs_total n
                            } { = . pout k 1000000000000.0 }
                        }
                        ( _ar_prep_free pr )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( _ar_jobs_free pjobs )
    : i nml ( vec_len [i] ml_idx )
    ? > nml 0 {
        : *i pm4 ( vec_data [i] meta )
        : ~ i q4 0
        ~ < q4 nml { = . pm4 + * q4 8 4 rmax = q4 + q4 1 }
        : ( Vec f ) scratch ( vec_zeroed [f] * * 4 rmax nml )
        : ( Vec f ) ssq ( vec_zeroed [f] nml )
        : ( Vec f ) fout ( vec_zeroed [f] f_total )
        : ( Vec i ) okv ( vec_zeroed [i] nml )
        : ( Vec GkArg ) call ( vec_new [GkArg] )
        ( vec_push [GkArg] call ( gk_in_i meta ) )
        ( vec_push [GkArg] call ( gk_in_f series ) )
        ( vec_push [GkArg] call ( gk_in_f polys ) )
        ( vec_push [GkArg] call ( gk_in_f p0s ) )
        ( vec_push [GkArg] call ( gk_in_f mus ) )
        ( vec_push [GkArg] call ( gk_out_f scratch ) )
        ( vec_push [GkArg] call ( gk_out_f ssq ) )
        ( vec_push [GkArg] call ( gk_out_f fout ) )
        ( vec_push [GkArg] call ( gk_out_i okv ) )
        ( vec_push [GkArg] call ( gk_i64 nml ) )
        : i t_r0 ( now_ms )
        : b ran ( gk_run kit ( _ag_kernel_src ) `arima_ml` ( gk_grid nml 64 ) 64 call )
        = g_ag_t_run + g_ag_t_run - ( now_ms ) t_r0
        ( vec_free [GkArg] call )
        : *f pssq ( vec_data [f] ssq )
        : *f pf ( vec_data [f] fout )
        : *i pmeta ( vec_data [i] meta )
        : *i pok ( vec_data [i] okv )
        : ~ i q 0
        ~ < q nml {
            : i k2 ( _ar_geti ml_idx q )
            : i n . pmeta + * q 8 1
            : i foff . pmeta + * q 8 3
            : ~ f val 1000000000000.0
            ? & ran != . pok q 0 {
                : ~ f sumlog 0.0
                : ~ i t 0
                ~ < t n { = sumlog + sumlog ( float_log . pf + foff t ) = t + t 1 }
                : ArimaLik lk ( _ar_lik_ml_from . pssq q sumlog n )
                ? . lk ok { = val - 0.0 . lk loglik } {}
            } {}
            = . pout k2 val
            = q + q 1
        }
        ( vec_free [f] scratch ) ( vec_free [f] ssq ) ( vec_free [f] fout ) ( vec_free [i] okv )
        = g_ag_t_post + g_ag_t_post - ( now_ms ) + t_r0 - ( now_ms ) t_r0
    } {}
    : i ncss ( vec_len [i] css_idx )
    ? > ncss 0 {
        : ( Vec f ) scratch ( vec_zeroed [f] cs_total )
        : ( Vec f ) ssq ( vec_zeroed [f] ncss )
        : ( Vec GkArg ) call ( vec_new [GkArg] )
        ( vec_push [GkArg] call ( gk_in_i cmeta ) )
        ( vec_push [GkArg] call ( gk_in_f series ) )
        ( vec_push [GkArg] call ( gk_in_f cpolys ) )
        ( vec_push [GkArg] call ( gk_in_f cmus ) )
        ( vec_push [GkArg] call ( gk_out_f scratch ) )
        ( vec_push [GkArg] call ( gk_out_f ssq ) )
        ( vec_push [GkArg] call ( gk_i64 ncss ) )
        : b ran ( gk_run kit ( _ag_kernel_src ) `arima_css` ( gk_grid ncss 64 ) 64 call )
        ( vec_free [GkArg] call )
        : *f pssq ( vec_data [f] ssq )
        : *i pmeta ( vec_data [i] cmeta )
        : ~ i q 0
        ~ < q ncss {
            : i k2 ( _ar_geti css_idx q )
            : i n . pmeta + * q 8 1
            : i pfc . pmeta + * q 8 2
            : i ncq . pmeta + * q 8 3
            : i nc ? > ncq pfc ncq pfc
            : ~ f val 1000000000000.0
            ? ran {
                : ArimaLik lk ( _ar_lik_css_from . pssq q - n nc )
                ? . lk ok { = val - 0.0 . lk loglik } {}
            } {}
            = . pout k2 val
            = q + q 1
        }
        ( vec_free [f] scratch ) ( vec_free [f] ssq )
    } {}
    ( vec_free [f] series ) ( vec_free [i] woff )
    ( vec_free [i] ml_idx ) ( vec_free [i] meta ) ( vec_free [f] polys ) ( vec_free [f] p0s ) ( vec_free [f] mus )
    ( vec_free [i] css_idx ) ( vec_free [i] cmeta ) ( vec_free [f] cpolys ) ( vec_free [f] cmus )
}

// K series fitted together with the device answering every round; the
// threaded CPU evaluator when no device (nor the CPU backend) opens.
@ arima_fit_many_gpu ( Vec ( Vec f ) ) series ArimaSpec sp i method → ( Vec * ArimaModel ) {
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} {
        ( gk_close kit )
        ^ ( arima_fit_many series sp method )
    }
    ( gk_bind_thread kit )
    : ( Vec * ArimaModel ) out ( arima_fit_many_with series sp method \ ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) vals → v { ( arima_eval_gpu kit items ctxs vals ) } )
    ( gk_close kit )
    ^ out
}
