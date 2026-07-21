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
$ `src/score.nu`
$ `deps/mlp/src/mlp.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`

// Rows per eval chunk (validation pass): bounds the acts buffer.
@ _aeg_eval_chunk → i { ^ 4096 }

// ── the kernels ───────────────────────────────────────────────────────
// meta (i64): [0]=n_layers [1]=n_a [2]=d [3]=dout, then sizes(nl+1),
// w_off(nl), b_off(nl), a_off(nl+1). One block per row for fwd/bwd/diff
// (threads stride the neurons, __syncthreads between layers); one thread
// per parameter for grad/adam.
@ _aeg_kernel_src → s {
    ^ `extern "C" __global__ void ae_fwd(const long long* meta, const double* X, const long long* idx, long long at, long long count, long long d, const double* w, const double* bb, double* acts)
{
    long long s = blockIdx.x; if (s >= count) return;
    long long nl = meta[0]; long long n_a = meta[1];
    const long long* sz = meta + 4;
    const long long* wop = sz + nl + 1;
    const long long* bop = wop + nl;
    const long long* aop = bop + nl;
    long long r = idx[at + s];
    double* a = acts + s * n_a;
    for (long long c = threadIdx.x; c < d; c += blockDim.x) a[c] = X[r * d + c];
    __syncthreads();
    for (long long l = 0; l < nl; l++) {
        long long fin = sz[l]; long long fout = sz[l + 1];
        long long wo = wop[l]; long long bo = bop[l];
        long long ai = aop[l]; long long ao = aop[l + 1];
        int last = (l == nl - 1) ? 1 : 0;
        for (long long j = threadIdx.x; j < fout; j += blockDim.x) {
            double z = bb[bo + j];
            long long wrow = wo + j * fin;
            for (long long i2 = 0; i2 < fin; i2++)
                z = __dadd_rn(z, __dmul_rn(w[wrow + i2], a[ai + i2]));
            if (!last && z < 0.0) z = 0.0;
            a[ao + j] = z;
        }
        __syncthreads();
    }
}
extern "C" __global__ void ae_bwd(const long long* meta, const double* Y, const long long* idx, long long at, long long count, long long dout, const double* w, const double* acts, double* deltas, double* outdiff)
{
    long long s = blockIdx.x; if (s >= count) return;
    long long nl = meta[0]; long long n_a = meta[1];
    const long long* sz = meta + 4;
    const long long* wop = sz + nl + 1;
    const long long* aop = wop + nl + nl;
    long long r = idx[at + s];
    const double* a = acts + s * n_a;
    double* dl = deltas + s * n_a;
    long long oa = aop[nl];
    for (long long j = threadIdx.x; j < dout; j += blockDim.x) {
        double e = __dsub_rn(a[oa + j], Y[r * dout + j]);
        dl[oa + j] = e;
        outdiff[s * dout + j] = e;
    }
    __syncthreads();
    for (long long l = nl - 1; l >= 1; l--) {
        long long fin = sz[l]; long long fout = sz[l + 1];
        long long wo = wop[l]; long long ai = aop[l]; long long ao = aop[l + 1];
        for (long long i3 = threadIdx.x; i3 < fin; i3 += blockDim.x) {
            double sm = 0.0;
            for (long long j2 = 0; j2 < fout; j2++)
                sm = __dadd_rn(sm, __dmul_rn(w[wo + j2 * fin + i3], dl[ao + j2]));
            if (a[ai + i3] <= 0.0) sm = 0.0;
            dl[ai + i3] = sm;
        }
        __syncthreads();
    }
}
extern "C" __global__ void ae_grad(const long long* meta, long long n_w, long long n_b, long long count, const double* acts, const double* deltas, double* gw, double* gb)
{
    long long k = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long nl = meta[0]; long long n_a = meta[1];
    const long long* sz = meta + 4;
    const long long* wop = sz + nl + 1;
    const long long* bop = wop + nl;
    const long long* aop = bop + nl;
    if (k < n_w) {
        long long l = nl - 1;
        while (l > 0 && wop[l] > k) l--;
        long long fin = sz[l];
        long long off = k - wop[l];
        long long j = off / fin; long long i2 = off % fin;
        long long ai = aop[l]; long long ao = aop[l + 1];
        double acc = 0.0;
        for (long long s = 0; s < count; s++)
            acc = __dadd_rn(acc, __dmul_rn(deltas[s * n_a + ao + j], acts[s * n_a + ai + i2]));
        gw[k] = acc;
    } else if (k < n_w + n_b) {
        long long kb = k - n_w;
        long long l = nl - 1;
        while (l > 0 && bop[l] > kb) l--;
        long long j = kb - bop[l];
        long long ao = aop[l + 1];
        double acc = 0.0;
        for (long long s = 0; s < count; s++)
            acc = __dadd_rn(acc, deltas[s * n_a + ao + j]);
        gb[kb] = acc;
    }
}
extern "C" __global__ void ae_adam(long long n_w, long long n_b, double lrt, double alpha, double fb, double* w, double* bb, double* mw, double* vw, double* mb, double* vb, double* gw, double* gb)
{
    long long k = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    double b1 = 0.9; double b2 = 0.999; double eps = 0.00000001;
    if (k < n_w) {
        double g = __dadd_rn(gw[k], __dmul_rn(alpha, w[k])) / fb;
        double nm = __dadd_rn(__dmul_rn(b1, mw[k]), __dmul_rn(__dsub_rn(1.0, b1), g));
        double nv = __dadd_rn(__dmul_rn(b2, vw[k]), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(g, g)));
        mw[k] = nm; vw[k] = nv;
        w[k] = __dsub_rn(w[k], __dmul_rn(lrt, nm) / __dadd_rn(sqrt(nv), eps));
        gw[k] = 0.0;
    } else if (k < n_w + n_b) {
        long long kb = k - n_w;
        double g = gb[kb] / fb;
        double nm = __dadd_rn(__dmul_rn(b1, mb[kb]), __dmul_rn(__dsub_rn(1.0, b1), g));
        double nv = __dadd_rn(__dmul_rn(b2, vb[kb]), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(g, g)));
        mb[kb] = nm; vb[kb] = nv;
        bb[kb] = __dsub_rn(bb[kb], __dmul_rn(lrt, nm) / __dadd_rn(sqrt(nv), eps));
        gb[kb] = 0.0;
    }
}
extern "C" __global__ void ae_diff(const long long* meta, const double* Y, const long long* idx, long long at, long long count, long long dout, const double* acts, double* outdiff)
{
    long long s = blockIdx.x; if (s >= count) return;
    long long nl = meta[0]; long long n_a = meta[1];
    const long long* aop = meta + 4 + (nl + 1) + nl + nl;
    long long oa = aop[nl];
    long long r = idx[at + s];
    for (long long j = threadIdx.x; j < dout; j += blockDim.x)
        outdiff[s * dout + j] = __dsub_rn(acts[s * n_a + oa + j], Y[r * dout + j]);
}
`
}

// ── device context ────────────────────────────────────────────────────
// Everything one aegpu_fit run holds on the device. All buffers are f64
// except idx / meta (i64). X doubles as Y (autoencoder: target == input).
: AeGpu {
    b ok
    Gpu g
    GpuKernel kfwd
    GpuKernel kbwd
    GpuKernel kgrad
    GpuKernel kadam
    GpuKernel kdiff
    GpuBuffer bmeta
    GpuBuffer bx
    GpuBuffer bidx
    GpuBuffer bw
    GpuBuffer bb
    GpuBuffer bmw
    GpuBuffer bvw
    GpuBuffer bmb
    GpuBuffer bvb
    GpuBuffer bgw
    GpuBuffer bgb
    GpuBuffer bacts
    GpuBuffer bdeltas
    GpuBuffer bodt  // train outdiff: bsz × dout
    GpuBuffer bode  // eval outdiff: eval_chunk × dout
}

@ _aeg_free AeGpu cx → v {
    ( gpu_free . cx bmeta ) ( gpu_free . cx bx ) ( gpu_free . cx bidx )
    ( gpu_free . cx bw ) ( gpu_free . cx bb )
    ( gpu_free . cx bmw ) ( gpu_free . cx bvw ) ( gpu_free . cx bmb ) ( gpu_free . cx bvb )
    ( gpu_free . cx bgw ) ( gpu_free . cx bgb )
    ( gpu_free . cx bacts ) ( gpu_free . cx bdeltas )
    ( gpu_free . cx bodt ) ( gpu_free . cx bode )
    ( gpu_kernel_free . cx kfwd ) ( gpu_kernel_free . cx kbwd ) ( gpu_kernel_free . cx kgrad )
    ( gpu_kernel_free . cx kadam ) ( gpu_kernel_free . cx kdiff )
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

// Open the context: buffers + the five kernels, on score.nu's device
// singleton. Any failure → ok=F (caller falls back to mlp_fit).
@ _aeg_open Mlp m i n i d i dout i bsz → AeGpu {
    : Gpu g . ( __an_gpukit_ref ) gpu
    : s src ( _aeg_kernel_src )
    : GpuKernel kfwd ( gpu_compile g src `ae_fwd` )
    : GpuKernel kbwd ( gpu_compile g src `ae_bwd` )
    : GpuKernel kgrad ( gpu_compile g src `ae_grad` )
    : GpuKernel kadam ( gpu_compile g src `ae_adam` )
    : GpuKernel kdiff ( gpu_compile g src `ae_diff` )
    : ( Vec i ) meta ( _aeg_meta m d dout )
    : i ch ( _aeg_eval_chunk )
    : i rows ? > bsz ch bsz ch
    : GpuBuffer bmeta ( gpu_alloc g * ( vec_len [i] meta ) 8 )
    : GpuBuffer bx ( gpu_alloc g * * n d 8 )
    : GpuBuffer bidx ( gpu_alloc g * n 8 )
    : GpuBuffer bw ( gpu_alloc g * . m n_w 8 )
    : GpuBuffer bb2 ( gpu_alloc g * . m n_b 8 )
    : GpuBuffer bmw ( gpu_alloc g * . m n_w 8 )
    : GpuBuffer bvw ( gpu_alloc g * . m n_w 8 )
    : GpuBuffer bmb ( gpu_alloc g * . m n_b 8 )
    : GpuBuffer bvb ( gpu_alloc g * . m n_b 8 )
    : GpuBuffer bgw ( gpu_alloc g * . m n_w 8 )
    : GpuBuffer bgb ( gpu_alloc g * . m n_b 8 )
    : GpuBuffer bacts ( gpu_alloc g * * rows . m n_a 8 )
    : GpuBuffer bdeltas ( gpu_alloc g * * bsz . m n_a 8 )
    : GpuBuffer bodt ( gpu_alloc g * * bsz dout 8 )
    : GpuBuffer bode ( gpu_alloc g * * ch dout 8 )
    : ~ b ok T
    ? ( gpu_kernel_ok kfwd ) {} { = ok F }
    ? ( gpu_kernel_ok kbwd ) {} { = ok F }
    ? ( gpu_kernel_ok kgrad ) {} { = ok F }
    ? ( gpu_kernel_ok kadam ) {} { = ok F }
    ? ( gpu_kernel_ok kdiff ) {} { = ok F }
    ? != . bmeta dptr 0 {} { = ok F }
    ? != . bx dptr 0 {} { = ok F }
    ? != . bidx dptr 0 {} { = ok F }
    ? != . bw dptr 0 {} { = ok F }
    ? != . bb2 dptr 0 {} { = ok F }
    ? != . bacts dptr 0 {} { = ok F }
    ? != . bdeltas dptr 0 {} { = ok F }
    ? ok { ? != ( gpu_upload bmeta # *u ( vec_data [i] meta ) ) 0 { = ok F } {} } {}
    ( vec_free [i] meta )
    ^ @ AeGpu { ok g kfwd kbwd kgrad kadam kdiff bmeta bx bidx bw bb2 bmw bvw bmb bvb bgw bgb bacts bdeltas bodt bode }
}

// score.nu's kit (only valid when the engine probe succeeded).
@ __an_gpukit_ref → *GpuKit { ^ ( anom_gpu_kit ) }

// ── the mirrored trainer ──────────────────────────────────────────────
// Exactly mlp_train, with the four per-minibatch compute steps and the
// validation forward on the device. Returns MlpTrain; the model's w/b,
// Adam state and t are updated in place, exactly as mlp_train leaves them.
// On ANY device error sets *fail and returns immediately (the caller
// discards everything and reruns on the CPU).
@ _aeg_train AeGpu cx Mlp m ( Vec f ) X i n i d i dout MlpCfg cfg * u fail → MlpTrain {
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
    : ~ i up 0
    = up + up ( gpu_upload . cx bw # *u ( vec_data [f] . m w ) )
    = up + up ( gpu_upload . cx bb # *u ( vec_data [f] . m b ) )
    = up + up ( gpu_upload . cx bmw # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bvw # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bmb # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bvb # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bgw # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bgb # *u ( vec_data [f] zeros ) )
    = up + up ( gpu_upload . cx bx # *u ( vec_data [f] X ) )
    ( vec_free [f] zeros )
    ? != up 0 {
        ( nurl_poke fail 0 1 )
        ( vec_free [i] idx ) ( rng_free g2 )
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
    : i pgrid ( gpu_grid nparam 256 )
    : f alpha . cfg alpha
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
        = gerr + gerr ( gpu_upload . cx bidx # *u ( vec_data [i] idx ) )
        // Minibatch pass.
        : ~ f se 0.0
        : ~ i at 0
        ~ & < at n_train == gerr 0 {
            : ~ i bend + at bsz
            ? > bend n_train { = bend n_train } {}
            : i cnt - bend at
            // forward + backprop + gradient + Adam, on the device
            : ( Vec i ) a1 ( vec_new [i] )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bmeta ) )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bx ) )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bidx ) )
            ( vec_push [i] a1 ( gpu_arg_i64 at ) )
            ( vec_push [i] a1 ( gpu_arg_i64 cnt ) )
            ( vec_push [i] a1 ( gpu_arg_i64 d ) )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bw ) )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bb ) )
            ( vec_push [i] a1 ( gpu_arg_buffer . cx bacts ) )
            = gerr + gerr ( gpu_launch . cx kfwd cnt 64 a1 )
            ( vec_free [i] a1 )
            : ( Vec i ) a2 ( vec_new [i] )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bmeta ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bx ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bidx ) )
            ( vec_push [i] a2 ( gpu_arg_i64 at ) )
            ( vec_push [i] a2 ( gpu_arg_i64 cnt ) )
            ( vec_push [i] a2 ( gpu_arg_i64 dout ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bw ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bacts ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bdeltas ) )
            ( vec_push [i] a2 ( gpu_arg_buffer . cx bodt ) )
            = gerr + gerr ( gpu_launch . cx kbwd cnt 64 a2 )
            ( vec_free [i] a2 )
            : ( Vec i ) a3 ( vec_new [i] )
            ( vec_push [i] a3 ( gpu_arg_buffer . cx bmeta ) )
            ( vec_push [i] a3 ( gpu_arg_i64 . m n_w ) )
            ( vec_push [i] a3 ( gpu_arg_i64 . m n_b ) )
            ( vec_push [i] a3 ( gpu_arg_i64 cnt ) )
            ( vec_push [i] a3 ( gpu_arg_buffer . cx bacts ) )
            ( vec_push [i] a3 ( gpu_arg_buffer . cx bdeltas ) )
            ( vec_push [i] a3 ( gpu_arg_buffer . cx bgw ) )
            ( vec_push [i] a3 ( gpu_arg_buffer . cx bgb ) )
            = gerr + gerr ( gpu_launch . cx kgrad pgrid 256 a3 )
            ( vec_free [i] a3 )
            // Adam scalars on the host — exactly mlp's expressions.
            = tstep + tstep 1
            : f tf # f tstep
            : f lrt * . cfg lr / ( sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
            = fb0 # f cnt
            : ( Vec i ) a4 ( vec_new [i] )
            ( vec_push [i] a4 ( gpu_arg_i64 . m n_w ) )
            ( vec_push [i] a4 ( gpu_arg_i64 . m n_b ) )
            ( vec_push [i] a4 ( gpu_arg_i64 ( f64_to_bits lrt ) ) )
            ( vec_push [i] a4 ( gpu_arg_i64 ( f64_to_bits alpha ) ) )
            ( vec_push [i] a4 ( gpu_arg_i64 ( f64_to_bits fb0 ) ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bw ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bb ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bmw ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bvw ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bmb ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bvb ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bgw ) )
            ( vec_push [i] a4 ( gpu_arg_buffer . cx bgb ) )
            = gerr + gerr ( gpu_launch . cx kadam pgrid 256 a4 )
            ( vec_free [i] a4 )
            // the training-loss contribution, folded in the CPU's flat order
            = gerr + gerr ( gpu_download # *u ( vec_data [f] od ) . cx bodt )
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
                : ( Vec i ) a5 ( vec_new [i] )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bmeta ) )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bx ) )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bidx ) )
                ( vec_push [i] a5 ( gpu_arg_i64 vat ) )
                ( vec_push [i] a5 ( gpu_arg_i64 vcnt ) )
                ( vec_push [i] a5 ( gpu_arg_i64 d ) )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bw ) )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bb ) )
                ( vec_push [i] a5 ( gpu_arg_buffer . cx bacts ) )
                = gerr + gerr ( gpu_launch . cx kfwd vcnt 64 a5 )
                ( vec_free [i] a5 )
                : ( Vec i ) a6 ( vec_new [i] )
                ( vec_push [i] a6 ( gpu_arg_buffer . cx bmeta ) )
                ( vec_push [i] a6 ( gpu_arg_buffer . cx bx ) )
                ( vec_push [i] a6 ( gpu_arg_buffer . cx bidx ) )
                ( vec_push [i] a6 ( gpu_arg_i64 vat ) )
                ( vec_push [i] a6 ( gpu_arg_i64 vcnt ) )
                ( vec_push [i] a6 ( gpu_arg_i64 dout ) )
                ( vec_push [i] a6 ( gpu_arg_buffer . cx bacts ) )
                ( vec_push [i] a6 ( gpu_arg_buffer . cx bode ) )
                = gerr + gerr ( gpu_launch . cx kdiff vcnt 64 a6 )
                ( vec_free [i] a6 )
                = gerr + gerr ( gpu_download # *u ( vec_data [f] od ) . cx bode )
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
                    = gerr + gerr ( gpu_download # *u ( vec_data [f] best_w ) . cx bw )
                    = gerr + gerr ( gpu_download # *u ( vec_data [f] best_b ) . cx bb )
                } {}
            } {
                = bad + bad 1
                ? >= bad . cfg n_no_change { = stopped T } {}
            }
            = epoch + epoch 1
        } {}
    }
    ? != gerr 0 {
        ( nurl_poke fail 0 1 )
        ( vec_free [f] best_w ) ( vec_free [f] best_b ) ( vec_free [f] od )
        ( vec_free [i] idx ) ( rng_free g2 )
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
        = derr + derr ( gpu_download # *u ( vec_data [f] . m w ) . cx bw )
        = derr + derr ( gpu_download # *u ( vec_data [f] . m b ) . cx bb )
    }
    = derr + derr ( gpu_download # *u ( vec_data [f] . m mw ) . cx bmw )
    = derr + derr ( gpu_download # *u ( vec_data [f] . m vw ) . cx bvw )
    = derr + derr ( gpu_download # *u ( vec_data [f] . m mb ) . cx bmb )
    = derr + derr ( gpu_download # *u ( vec_data [f] . m vb ) . cx bvb )
    ? != derr 0 { ( nurl_poke fail 0 1 ) } {}
    ( vec_free [f] best_w ) ( vec_free [f] best_b ) ( vec_free [f] od )
    ( vec_free [i] idx ) ( rng_free g2 )
    ^ @ MlpTrain { epoch train_loss best stopped }
}

// ── the public entry: mlp_fit, GPU when a CUDA device is present ─────
// Bit-identical to ( mlp_fit sizes X n d X d cfg restarts ) — the
// autoencoder case (target == input). Falls back to mlp_fit whenever the
// engine is not `cuda` or any device step fails.
@ aegpu_fit ( Vec i ) sizes ( Vec f ) X i n i d MlpCfg cfg i restarts → MlpFit {
    ? == ( nurl_str_eq ( anom_gpu_engine ) `cuda` ) 1 {} {
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
        ( _aeg_free cx )
        ( mlp_free best_m )
        ( nurl_eprintln `anomaly: autoencoder GPU setup failed, training on the CPU` )
        ^ ( mlp_fit sizes X n d X d cfg restarts )
    }
    : *u fail ( nurl_alloc 8 )
    ( nurl_poke fail 0 0 )
    : ~ MlpTrain best_tr ( _aeg_train cx best_m X n d d cfg fail )
    : ~ i r 1
    ~ & < r r2 == ( nurl_peek fail 0 ) 0 {
        : ~ MlpCfg c cfg
        = . c seed + . cfg seed r
        : Mlp m ( mlp_new sizes . c seed )
        : MlpTrain tr ( _aeg_train cx m X n d d c fail )
        ? & == ( nurl_peek fail 0 ) 0 < . tr best_val . best_tr best_val {
            ( mlp_free best_m )
            = best_m m
            = best_tr tr
        } {
            ( mlp_free m )
        }
        = r + r 1
    }
    ( _aeg_free cx )
    : i failed ( nurl_peek fail 0 )
    ( nurl_free fail )
    ? != failed 0 {
        ( mlp_free best_m )
        ( nurl_eprintln `anomaly: autoencoder GPU training failed, retraining on the CPU` )
        ^ ( mlp_fit sizes X n d X d cfg restarts )
    } {}
    ^ @ MlpFit { best_m best_tr }
}
