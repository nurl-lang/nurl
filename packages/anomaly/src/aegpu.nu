// anomaly/aegpu.nu — GPU-accelerated autoencoder training (bit-exact).
//
// The autoencoder trains through mlp_fit — minibatch Adam over a small dense
// net — and that training is where /train/autoencoder spends its time
// (~20 s for 20 k rows; the bulk-MSE pass after it is milliseconds). This
// module runs THE SAME training on the GPU when one is present, with the
// package's standing guarantee intact: **backend choice can never change a
// result**. The GPU path is bit-for-bit identical to mlp_fit, so a model
// trained on a CUDA machine equals the CPU-trained model exactly — same
// weights, same threshold, same verdicts. GPU is pure speed.
//
// How bit-exactness is achieved (and pinned by tests/aegpu_parity_smoke.sh):
//
//   * Control flow stays on the host and MIRRORS mlp_train exactly: the same
//     seeded PRNG call order (init, the one full shuffle, the per-epoch train
//     -region shuffles), the same validation split, minibatch bounds, early-
//     stopping/patience/best-weights logic, and the same Adam scalar
//     bookkeeping (lr_t via host pow/sqrt, passed to the kernel as data).
//   * The kernels reproduce the CPU's floating-point ROUNDING AND ORDER:
//     every accumulation chain uses explicit __dadd_rn/__dmul_rn/__dsub_rn
//     (round-to-nearest, never fused — NVRTC's default fmad contraction
//     would change results), dot products run serially in the CPU's k-order
//     inside one thread, and per-weight gradient sums walk the batch rows in
//     the CPU's row order. Division and sqrt are IEEE-correctly-rounded on
//     both sides. Scalars that need libm pow are computed on the HOST and
//     shipped to the kernel, so no transcendental runs on the device.
//   * Loss/criterion sums come back as per-element differences and are
//     folded on the host in the same flat order as the CPU loop.
//
// Weights, Adam state and the data live on the device for the whole run;
// per minibatch the device does forward → backprop → gradient → Adam in four
// launches and only the output-layer diffs (batch×d f64s) come back.
//
// Selection: engine `cuda` (score.nu's probe) → GPU; anything else — no
// device, ANOMALY_GPU=0, any mid-setup failure — falls back to the pure
// mlp_fit, which (being bit-identical) is a pace change, never a behaviour
// change. The gpu package's host-C++ backend is deliberately NOT used for
// training: native mlp_fit already is the optimized CPU path.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `score.nu`
$ `deps/mlp/src/mlp.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`

// Rows per eval chunk (validation pass): bounds the acts buffer.
@ _aeg_eval_chunk → i { ^ 4096 }

// ── the kernels ───────────────────────────────────────────────────────
// In gpukit's checked subset (gk_run_checked_dev): every read and write is
// an LD / ST of a bound device buffer, and the barriers are SYNC()s the
// subset proves the whole block reaches. meta (i64): [0]=n_layers [1]=n_a
// [2]=d [3]=dout, then sizes(nl+1) at 4, w_off(nl), b_off(nl), a_off(nl+1).
// One block per row for fwd/bwd/diff (threads stride the neurons, a SYNC()
// between layers); one thread per parameter for grad/adam.

@ _aeg_fwd_body → s {
    ^ `long long s = bid;
if (s < count) {
    long long nl = LD(meta, 0);
    long long n_a = LD(meta, 1);
    long long wb = 4 + nl + 1;
    long long bb0 = wb + nl;
    long long ab = bb0 + nl;
    long long r = LD(idx, at + s);
    long long a = s * n_a;
    for (long long c = tid; c < d; c += bdim) { ST(acts, a + c, LD(X, r * d + c)); }
    SYNC();
    for (long long l = 0; l < nl; l++) {
        long long fin = LD(meta, 4 + l);
        long long fout = LD(meta, 5 + l);
        long long wo = LD(meta, wb + l);
        long long bo = LD(meta, bb0 + l);
        long long ai = LD(meta, ab + l);
        long long ao = LD(meta, ab + l + 1);
        long long last = (l == nl - 1) ? 1 : 0;
        for (long long j = tid; j < fout; j += bdim) {
            double z = LD(bb, bo + j);
            long long wrow = wo + j * fin;
            for (long long i2 = 0; i2 < fin; i2++) {
                z = __dadd_rn(z, __dmul_rn(LD(w, wrow + i2), LD(acts, a + ai + i2)));
            }
            if (!last && z < 0.0) { z = 0.0; }
            ST(acts, a + ao + j, z);
        }
        SYNC();
    }
}`
}

@ _aeg_bwd_body → s {
    ^ `long long s = bid;
if (s < count) {
    long long nl = LD(meta, 0);
    long long n_a = LD(meta, 1);
    long long wb = 4 + nl + 1;
    long long ab = wb + nl + nl;
    long long r = LD(idx, at + s);
    long long a = s * n_a;
    long long oa = LD(meta, ab + nl);
    for (long long j = tid; j < dout; j += bdim) {
        double e = __dsub_rn(LD(acts, a + oa + j), LD(Y, r * dout + j));
        ST(deltas, a + oa + j, e);
        ST(outdiff, s * dout + j, e);
    }
    SYNC();
    for (long long l = nl - 1; l >= 1; l--) {
        long long fin = LD(meta, 4 + l);
        long long fout = LD(meta, 5 + l);
        long long wo = LD(meta, wb + l);
        long long ai = LD(meta, ab + l);
        long long ao = LD(meta, ab + l + 1);
        for (long long i3 = tid; i3 < fin; i3 += bdim) {
            double sm = 0.0;
            for (long long j2 = 0; j2 < fout; j2++) {
                sm = __dadd_rn(sm, __dmul_rn(LD(w, wo + j2 * fin + i3), LD(deltas, a + ao + j2)));
            }
            if (LD(acts, a + ai + i3) <= 0.0) { sm = 0.0; }
            ST(deltas, a + ai + i3, sm);
        }
        SYNC();
    }
}`
}

@ _aeg_grad_body → s {
    ^ `long long k = gid;
long long nl = LD(meta, 0);
long long n_a = LD(meta, 1);
long long wb = 4 + nl + 1;
long long bb0 = wb + nl;
long long ab = bb0 + nl;
if (k < n_w) {
    long long l = nl - 1;
    while (l > 0 && LD(meta, wb + l) > k) { l--; }
    long long fin = LD(meta, 4 + l);
    long long off = k - LD(meta, wb + l);
    long long j = off / fin;
    long long i2 = off % fin;
    long long ai = LD(meta, ab + l);
    long long ao = LD(meta, ab + l + 1);
    double acc = 0.0;
    for (long long s = 0; s < count; s++) {
        acc = __dadd_rn(acc, __dmul_rn(LD(deltas, s * n_a + ao + j), LD(acts, s * n_a + ai + i2)));
    }
    ST(gw, k, acc);
} else if (k < n_w + n_b) {
    long long kb = k - n_w;
    long long l = nl - 1;
    while (l > 0 && LD(meta, bb0 + l) > kb) { l--; }
    long long j = kb - LD(meta, bb0 + l);
    long long ao = LD(meta, ab + l + 1);
    double acc = 0.0;
    for (long long s = 0; s < count; s++) { acc = __dadd_rn(acc, LD(deltas, s * n_a + ao + j)); }
    ST(gb, kb, acc);
}`
}

@ _aeg_adam_body → s {
    ^ `long long k = gid;
double b1 = 0.9;
double b2 = 0.999;
double eps = 0.00000001;
if (k < n_w) {
    double g = __dadd_rn(LD(gw, k), __dmul_rn(alpha, LD(w, k))) / fb;
    double nm = __dadd_rn(__dmul_rn(b1, LD(mw, k)), __dmul_rn(__dsub_rn(1.0, b1), g));
    double nv = __dadd_rn(__dmul_rn(b2, LD(vw, k)), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(g, g)));
    ST(mw, k, nm);
    ST(vw, k, nv);
    ST(w, k, __dsub_rn(LD(w, k), __dmul_rn(lrt, nm) / __dadd_rn(sqrt(nv), eps)));
    ST(gw, k, 0.0);
} else if (k < n_w + n_b) {
    long long kb = k - n_w;
    double g = LD(gb, kb) / fb;
    double nm = __dadd_rn(__dmul_rn(b1, LD(mb, kb)), __dmul_rn(__dsub_rn(1.0, b1), g));
    double nv = __dadd_rn(__dmul_rn(b2, LD(vb, kb)), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(g, g)));
    ST(mb, kb, nm);
    ST(vb, kb, nv);
    ST(bb, kb, __dsub_rn(LD(bb, kb), __dmul_rn(lrt, nm) / __dadd_rn(sqrt(nv), eps)));
    ST(gb, kb, 0.0);
}`
}

@ _aeg_diff_body → s {
    ^ `long long s = bid;
if (s < count) {
    long long nl = LD(meta, 0);
    long long n_a = LD(meta, 1);
    long long oa = LD(meta, 4 + (nl + 1) + nl + nl + nl);
    long long r = LD(idx, at + s);
    for (long long j = tid; j < dout; j += bdim) {
        ST(outdiff, s * dout + j, __dsub_rn(LD(acts, s * n_a + oa + j), LD(Y, r * dout + j)));
    }
}`
}

// ── device context ────────────────────────────────────────────────────
// Everything one aegpu_fit run holds on the device. All buffers are f64
// except idx / meta (i64). X doubles as Y (autoencoder: target == input).
: AeGpu {
    b ok
    GpuKit kit
    GkBuf bmeta
    GkBuf bx
    GkBuf bidx
    GkBuf bw
    GkBuf bb
    GkBuf bmw
    GkBuf bvw
    GkBuf bmb
    GkBuf bvb
    GkBuf bgw
    GkBuf bgb
    GkBuf bacts
    GkBuf bdeltas
    GkBuf bodt  // train outdiff: bsz × dout
    GkBuf bode  // eval outdiff: eval_chunk × dout
}

// The meta buffer content for a freshly built net.
@ _aeg_meta Mlp m i d i dout → ( Vec i ) {
    : i nl . m n_layers
    : ( Vec i ) meta ( vec_new [i] )
    ( vec_push [i] meta nl )
    ( vec_push [i] meta . m n_a )
    ( vec_push [i] meta d )
    ( vec_push [i] meta dout )
    : ~ i k 0
    ~ < k + nl 1 { ( vec_push [i] meta ( _mlp_iget . m sizes k ) ) = k + k 1 }
    = k 0
    ~ < k nl { ( vec_push [i] meta ( _mlp_iget . m w_off k ) ) = k + k 1 }
    = k 0
    ~ < k nl { ( vec_push [i] meta ( _mlp_iget . m b_off k ) ) = k + k 1 }
    = k 0
    ~ < k + nl 1 { ( vec_push [i] meta ( _mlp_iget . m a_off k ) ) = k + k 1 }
    ^ meta
}

// Open the context: the buffers, on score.nu's device singleton (the
// kernels are checked and compiled at their first launch). Any failure →
// ok=F (caller falls back to mlp_fit).
@ _aeg_open Mlp m i n i d i dout i bsz → AeGpu {
    : GpuKit kit ( __an_gpukit_ref )
    : ( Vec i ) meta ( _aeg_meta m d dout )
    : i ch ( _aeg_eval_chunk )
    : i rows ? > bsz ch bsz ch
    : GkBuf bmeta ( gk_dbuf_new kit ( vec_len [i] meta ) GK_I64 )
    : GkBuf bx ( gk_dbuf_new kit * n d GK_F64 )
    : GkBuf bidx ( gk_dbuf_new kit n GK_I64 )
    : GkBuf bw ( gk_dbuf_new kit . m n_w GK_F64 )
    : GkBuf bb2 ( gk_dbuf_new kit . m n_b GK_F64 )
    : GkBuf bmw ( gk_dbuf_new kit . m n_w GK_F64 )
    : GkBuf bvw ( gk_dbuf_new kit . m n_w GK_F64 )
    : GkBuf bmb ( gk_dbuf_new kit . m n_b GK_F64 )
    : GkBuf bvb ( gk_dbuf_new kit . m n_b GK_F64 )
    : GkBuf bgw ( gk_dbuf_new kit . m n_w GK_F64 )
    : GkBuf bgb ( gk_dbuf_new kit . m n_b GK_F64 )
    : GkBuf bacts ( gk_dbuf_new kit * rows . m n_a GK_F64 )
    : GkBuf bdeltas ( gk_dbuf_new kit * bsz . m n_a GK_F64 )
    : GkBuf bodt ( gk_dbuf_new kit * bsz dout GK_F64 )
    : GkBuf bode ( gk_dbuf_new kit * ch dout GK_F64 )
    : ~ b ok T
    ? & & & ( gk_buf_ok bmeta ) ( gk_buf_ok bx ) ( gk_buf_ok bidx ) & ( gk_buf_ok bw ) ( gk_buf_ok bb2 ) {} { = ok F }
    ? & & & ( gk_buf_ok bmw ) ( gk_buf_ok bvw ) ( gk_buf_ok bmb ) & ( gk_buf_ok bvb ) ( gk_buf_ok bgw ) {} { = ok F }
    ? & & & ( gk_buf_ok bgb ) ( gk_buf_ok bacts ) ( gk_buf_ok bdeltas ) & ( gk_buf_ok bodt ) ( gk_buf_ok bode ) {} { = ok F }
    ? ok { = ok ( gk_dbuf_upload_i kit bmeta meta ) } {}
    ^ @ AeGpu { ok kit bmeta bx bidx bw bb2 bmw bvw bmb bvb bgw bgb bacts bdeltas bodt bode }
}

// The bound launches of one training run: each kernel's buffers, and its
// scalars set per launch (gk_call_set_*).
: AeCalls { GkCall fwd GkCall bwd GkCall grad GkCall adam GkCall vfwd GkCall diff }

@ _aeg_calls AeGpu cx Mlp m i d i dout f alpha → AeCalls {
    : ~ GkCall f1 ( gk_call_new )
    ( gk_call_dev_in f1 `meta` . cx bmeta ) ( gk_call_dev_in f1 `X` . cx bx ) ( gk_call_dev_in f1 `idx` . cx bidx )
    ( gk_call_i64 f1 `at` 0 ) ( gk_call_i64 f1 `count` 0 ) ( gk_call_i64 f1 `d` d )
    ( gk_call_dev_in f1 `w` . cx bw ) ( gk_call_dev_in f1 `bb` . cx bb ) ( gk_call_dev f1 `acts` . cx bacts )
    : ~ GkCall f2 ( gk_call_new )
    ( gk_call_dev_in f2 `meta` . cx bmeta ) ( gk_call_dev_in f2 `Y` . cx bx ) ( gk_call_dev_in f2 `idx` . cx bidx )
    ( gk_call_i64 f2 `at` 0 ) ( gk_call_i64 f2 `count` 0 ) ( gk_call_i64 f2 `dout` dout )
    ( gk_call_dev_in f2 `w` . cx bw ) ( gk_call_dev_in f2 `acts` . cx bacts ) ( gk_call_dev f2 `deltas` . cx bdeltas ) ( gk_call_dev f2 `outdiff` . cx bodt )
    : ~ GkCall f3 ( gk_call_new )
    ( gk_call_dev_in f3 `meta` . cx bmeta ) ( gk_call_i64 f3 `n_w` . m n_w ) ( gk_call_i64 f3 `n_b` . m n_b ) ( gk_call_i64 f3 `count` 0 )
    ( gk_call_dev_in f3 `acts` . cx bacts ) ( gk_call_dev_in f3 `deltas` . cx bdeltas ) ( gk_call_dev f3 `gw` . cx bgw ) ( gk_call_dev f3 `gb` . cx bgb )
    : ~ GkCall f4 ( gk_call_new )
    ( gk_call_i64 f4 `n_w` . m n_w ) ( gk_call_i64 f4 `n_b` . m n_b )
    ( gk_call_f64 f4 `lrt` 0.0 ) ( gk_call_f64 f4 `alpha` alpha ) ( gk_call_f64 f4 `fb` 1.0 )
    ( gk_call_dev f4 `w` . cx bw ) ( gk_call_dev f4 `bb` . cx bb ) ( gk_call_dev f4 `mw` . cx bmw ) ( gk_call_dev f4 `vw` . cx bvw )
    ( gk_call_dev f4 `mb` . cx bmb ) ( gk_call_dev f4 `vb` . cx bvb ) ( gk_call_dev f4 `gw` . cx bgw ) ( gk_call_dev f4 `gb` . cx bgb )
    : ~ GkCall f5 ( gk_call_new )
    ( gk_call_dev_in f5 `meta` . cx bmeta ) ( gk_call_dev_in f5 `X` . cx bx ) ( gk_call_dev_in f5 `idx` . cx bidx )
    ( gk_call_i64 f5 `at` 0 ) ( gk_call_i64 f5 `count` 0 ) ( gk_call_i64 f5 `d` d )
    ( gk_call_dev_in f5 `w` . cx bw ) ( gk_call_dev_in f5 `bb` . cx bb ) ( gk_call_dev f5 `acts` . cx bacts )
    : ~ GkCall f6 ( gk_call_new )
    ( gk_call_dev_in f6 `meta` . cx bmeta ) ( gk_call_dev_in f6 `Y` . cx bx ) ( gk_call_dev_in f6 `idx` . cx bidx )
    ( gk_call_i64 f6 `at` 0 ) ( gk_call_i64 f6 `count` 0 ) ( gk_call_i64 f6 `dout` dout )
    ( gk_call_dev_in f6 `acts` . cx bacts ) ( gk_call_dev f6 `outdiff` . cx bode )
    ^ @ AeCalls { f1 f2 f3 f4 f5 f6 }
}

// score.nu's kit (only valid when the engine probe succeeded).
@ __an_gpukit_ref → GpuKit { ^ ( anom_gpu_kit ) }

// ── the mirrored trainer ──────────────────────────────────────────────
// Exactly mlp_train, with the four per-minibatch compute steps and the
// validation forward on the device. Returns MlpTrain; the model's w/b,
// Adam state and t are updated in place, exactly as mlp_train leaves them.
// On ANY device error sets `fail` and returns immediately (the caller
// discards everything and reruns on the CPU).
@ _aeg_train AeGpu cx Mlp m ( Vec f ) X i n i d i dout MlpCfg cfg inout i fail → MlpTrain {
    : Rng g2 ( rng_seed . cfg seed )
    : i oa2 ( _mlp_iget . m a_off . m n_layers )
    // One shuffled split: [0, n_train) train, [n_train, n) validation.
    : ( Vec i ) idx ( vec_iota 0 n )
    : ~ i k0 0
    ~ < k0 - n 1 {
        : i j0 + k0 ( rng_below g2 - n k0 )
        ( vec_swap [i] idx k0 j0 )
        = k0 + k0 1
    }
    : ~ i n_val 0
    ? . cfg early_stop {
        = n_val # i ( round * . cfg val_frac # f n )
        ? < n_val 1 { = n_val 1 } {}
        ? >= n_val n { = n_val / n 5 } {}
    } {}
    : i n_train - n n_val
    : ~ i bsz . cfg batch
    ? <= bsz 0 { = bsz 200 } {}
    ? > bsz n_train { = bsz n_train } {}
    // Device state for THIS candidate: weights + zeroed Adam/grad state.
    : ( Vec f ) zeros ( vec_with_cap [f] . m n_w )
    : ~ i z 0
    ~ < z . m n_w { ( vec_push [f] zeros 0.0 ) = z + z 1 }
    : GpuKit kit . cx kit
    : ~ b up T
    = up & up ( gk_dbuf_upload kit . cx bw . m w )
    = up & up ( gk_dbuf_upload kit . cx bb . m b )
    = up & up ( gk_dbuf_upload kit . cx bmw zeros )
    = up & up ( gk_dbuf_upload kit . cx bvw zeros )
    = up & up ( gk_dbuf_upload kit . cx bmb zeros )
    = up & up ( gk_dbuf_upload kit . cx bvb zeros )
    = up & up ( gk_dbuf_upload kit . cx bgw zeros )
    = up & up ( gk_dbuf_upload kit . cx bgb zeros )
    = up & up ( gk_dbuf_upload kit . cx bx X )
    ? ! up {
        = fail 1
        ^ @ MlpTrain { 0 0.0 0.0 F }
    } {}
    : ( Vec f ) best_w ( vec_with_cap [f] . m n_w )
    : ( Vec f ) best_b ( vec_with_cap [f] . m n_b )
    = z 0
    ~ < z . m n_w { ( vec_push [f] best_w 0.0 ) = z + z 1 }
    = z 0
    ~ < z . m n_b { ( vec_push [f] best_b 0.0 ) = z + z 1 }
    : i ch ( _aeg_eval_chunk )
    : ( Vec f ) od ( vec_with_cap [f] * ? > bsz ch bsz ch dout )
    = z 0
    ~ < z * ? > bsz ch bsz ch dout { ( vec_push [f] od 0.0 ) = z + z 1 }
    : i nparam + . m n_w . m n_b
    : i pgrid ( gk_grid nparam 256 )
    : f alpha . cfg alpha
    : ~ AeCalls ac ( _aeg_calls cx m d dout alpha )
    : ~ f fb0 0.0  // per-batch, set below
    : ~ i tstep 0
    : ~ f best 0.0
    : ~ b have_best F
    : ~ i bad 0
    : ~ i epoch 0
    : ~ f train_loss 0.0
    : ~ b stopped F
    : ~ i gerr 0
    ~ & & < epoch . cfg max_iter ! stopped == gerr 0 {
        // Shuffle the TRAIN region only; the val tail stays fixed.
        : ~ i k 0
        ~ < k - n_train 1 {
            : i j + k ( rng_below g2 - n_train k )
            ( vec_swap [i] idx k j )
            = k + k 1
        }
        ? ( gk_dbuf_upload_i kit . cx bidx idx ) {} { = gerr + gerr 1 }
        // Minibatch pass.
        : ~ f se 0.0
        : ~ i at 0
        ~ & < at n_train == gerr 0 {
            : ~ i bend + at bsz
            ? > bend n_train { = bend n_train } {}
            : i cnt - bend at
            // forward + backprop + gradient + Adam, on the device
            : b _s1 & ( gk_call_set_i64 . ac fwd `at` at ) ( gk_call_set_i64 . ac fwd `count` cnt )
            ? ( gk_run_checked_dev kit . ac fwd `ae_fwd` ( _aeg_fwd_body ) cnt 64 ) {} { = gerr + gerr 1 }
            : b _s2 & ( gk_call_set_i64 . ac bwd `at` at ) ( gk_call_set_i64 . ac bwd `count` cnt )
            ? ( gk_run_checked_dev kit . ac bwd `ae_bwd` ( _aeg_bwd_body ) cnt 64 ) {} { = gerr + gerr 1 }
            : b _s3 ( gk_call_set_i64 . ac grad `count` cnt )
            ? ( gk_run_checked_dev kit . ac grad `ae_grad` ( _aeg_grad_body ) pgrid 256 ) {} { = gerr + gerr 1 }
            // Adam scalars on the host — exactly mlp's expressions.
            = tstep + tstep 1
            : f tf # f tstep
            : f lrt * . cfg lr / ( sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
            = fb0 # f cnt
            : b _s4 & ( gk_call_set_f64 . ac adam `lrt` lrt ) ( gk_call_set_f64 . ac adam `fb` fb0 )
            ? ( gk_run_checked_dev kit . ac adam `ae_adam` ( _aeg_adam_body ) pgrid 256 ) {} { = gerr + gerr 1 }
            // the training-loss contribution, folded in the CPU's flat order
            ? ( gk_dbuf_download kit . cx bodt od ) {} { = gerr + gerr 1 }
            : ~ i s2 0
            ~ < s2 cnt {
                : ~ i j2 0
                ~ < j2 dout {
                    : f e ( _mlp_fget od + * s2 dout j2 )
                    = se + se * e e
                    = j2 + j2 1
                }
                = s2 + s2 1
            }
            = at bend
        }
        = train_loss / se # f * n_train dout
        // The plateau criterion: validation MSE with early_stop, else the
        // training loss.
        : ~ f crit train_loss
        ? & . cfg early_stop == gerr 0 {
            : ~ f sev 0.0
            : ~ i vat n_train
            ~ & < vat n == gerr 0 {
                : ~ i vend + vat ch
                ? > vend n { = vend n } {}
                : i vcnt - vend vat
                : b _s5 & ( gk_call_set_i64 . ac vfwd `at` vat ) ( gk_call_set_i64 . ac vfwd `count` vcnt )
                ? ( gk_run_checked_dev kit . ac vfwd `ae_fwd` ( _aeg_fwd_body ) vcnt 64 ) {} { = gerr + gerr 1 }
                : b _s6 & ( gk_call_set_i64 . ac diff `at` vat ) ( gk_call_set_i64 . ac diff `count` vcnt )
                ? ( gk_run_checked_dev kit . ac diff `ae_diff` ( _aeg_diff_body ) vcnt 64 ) {} { = gerr + gerr 1 }
                ? ( gk_dbuf_download kit . cx bode od ) {} { = gerr + gerr 1 }
                : ~ i s3 0
                ~ < s3 vcnt {
                    : ~ i j3 0
                    ~ < j3 dout {
                        : f e2 ( _mlp_fget od + * s3 dout j3 )
                        = sev + sev * e2 e2
                        = j3 + j3 1
                    }
                    = s3 + s3 1
                }
                = vat vend
            }
            = crit / sev # f * n_val dout
        } {}
        ? . cfg verbose {
            ( nurl_print `epoch ` ) ( nurl_print_int + epoch 1 )
            ( nurl_print ` train_mse ` ) ( nurl_print ( nurl_str_float train_loss ) )
            ( nurl_print ` crit ` ) ( nurl_print ( nurl_str_float crit ) )
            ( nurl_print `\n` )
        } {}
        ? == gerr 0 {
            ? | ! have_best < crit - best . cfg tol {
                = bad 0
                ? | ! have_best < crit best { = best crit } {}
                = have_best T
                ? . cfg early_stop {
                    ? & ( gk_dbuf_download kit . cx bw best_w ) ( gk_dbuf_download kit . cx bb best_b ) {} { = gerr + gerr 1 }
                } {}
            } {
                = bad + bad 1
                ? >= bad . cfg n_no_change { = stopped T } {}
            }
            = epoch + epoch 1
        } {}
    }
    ? != gerr 0 {
        = fail 1
        ^ @ MlpTrain { 0 0.0 0.0 F }
    } {}
    // Restore the best weights (early stopping keeps the best epoch, not
    // the last); Adam state and t stay FINAL, exactly like mlp_train.
    : ~ i derr 0
    ? & . cfg early_stop have_best {
        : ~ i c3 0
        ~ < c3 . m n_w { ( vec_set [f] . m w c3 ( _mlp_fget best_w c3 ) ) = c3 + c3 1 }
        = c3 0
        ~ < c3 . m n_b { ( vec_set [f] . m b c3 ( _mlp_fget best_b c3 ) ) = c3 + c3 1 }
    } {
        ? & ( gk_dbuf_download kit . cx bw . m w ) ( gk_dbuf_download kit . cx bb . m b ) {} { = derr + derr 1 }
    }
    ? & & ( gk_dbuf_download kit . cx bmw . m mw ) ( gk_dbuf_download kit . cx bvw . m vw ) & ( gk_dbuf_download kit . cx bmb . m mb ) ( gk_dbuf_download kit . cx bvb . m vb ) {} { = derr + derr 1 }
    ? != derr 0 { = fail 1 } {}
    ^ @ MlpTrain { epoch train_loss best stopped }
}

// ANOMALY_AEGPU_CPU=1: train through the device kernels on the gpu
// package's CPU backend too — how the parity test and the kernels' timing
// run on a machine without a GPU (native mlp_fit is the faster CPU path).
@ __aeg_cpu_on → b {
    : s v ( getenv `ANOMALY_AEGPU_CPU` )
    ? == # i v 0 { ^ F } {}
    ^ != 0 ( nurl_str_eq v `1` )
}

// ── the public entry: mlp_fit, GPU when a CUDA device is present ─────
// Bit-identical to ( mlp_fit sizes X n d X d cfg restarts ) — the
// autoencoder case (target == input). Falls back to mlp_fit whenever the
// engine is not `cuda` or any device step fails.
@ aegpu_fit ( Vec i ) sizes ( Vec f ) X i n i d MlpCfg cfg i restarts → MlpFit {
    ? | != 0 ( nurl_str_eq ( anom_gpu_engine ) `cuda` ) & != 0 ( nurl_str_eq ( anom_gpu_engine ) `cpu` ) ( __aeg_cpu_on ) {} {
        ^ ( mlp_fit sizes X n d X d cfg restarts )
    }
    // The batch size is data-dependent but restart-independent: compute it
    // once for the buffer sizing (mirrors mlp_train's own derivation).
    : ~ i n_val 0
    ? . cfg early_stop {
        = n_val # i ( round * . cfg val_frac # f n )
        ? < n_val 1 { = n_val 1 } {}
        ? >= n_val n { = n_val / n 5 } {}
    } {}
    : i n_train - n n_val
    : ~ i bsz . cfg batch
    ? <= bsz 0 { = bsz 200 } {}
    ? > bsz n_train { = bsz n_train } {}
    : ~ i r2 restarts
    ? < r2 1 { = r2 1 } {}
    // First candidate sizes the context (every restart shares the topology).
    : ~ Mlp best_m ( mlp_new sizes . cfg seed )
    : AeGpu cx ( _aeg_open best_m n d d bsz )
    ? . cx ok {} {
        ( nurl_eprintln `anomaly: autoencoder GPU setup failed, training on the CPU` )
        ^ ( mlp_fit sizes X n d X d cfg restarts )
    }
    // Launches stream without a sync each: the downloads wait for them.
    : b prev_sync g_gk_autosync
    ( gk_autosync F )
    : ~ i fail 0
    : ~ MlpTrain best_tr ( _aeg_train cx best_m X n d d cfg fail )
    : ~ i r 1
    ~ & < r r2 == fail 0 {
        : ~ MlpCfg c cfg
        = . c seed + . cfg seed r
        : Mlp m ( mlp_new sizes . c seed )
        : MlpTrain tr ( _aeg_train cx m X n d d c fail )
        ? & == fail 0 < . tr best_val . best_tr best_val {
            = best_m m
            = best_tr tr
        } {
        }
        = r + r 1
    }
    ( gk_autosync prev_sync )
    : i failed fail
    ? != failed 0 {
        ( nurl_eprintln `anomaly: autoencoder GPU training failed, retraining on the CPU` )
        ^ ( mlp_fit sizes X n d X d cfg restarts )
    } {}
    ^ @ MlpFit { best_m best_tr }
}
