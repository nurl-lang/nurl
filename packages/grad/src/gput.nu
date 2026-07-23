// grad/gput.nu — the GPU replay engine: run a captured tape episode on the
// device, bit-exactly.
//
// The CPU tape (grad.nu) stays the semantic reference. `gput_capture` takes
// ONE recorded episode — parameters, constants, every op node up to the loss
// — and mirrors it onto the device: a value buffer and a gradient buffer per
// node, plus the stride/offset metadata each kernel needs. After capture the
// graph is STATIC (the mark/reset training loop re-records the same node
// structure every episode anyway): per minibatch the caller uploads fresh
// input rows into their const slots (`gput_set_input`), replays forward and
// backward on the device, and steps the device optimizer — nothing but the
// loss scalar needs to come back to the host.
//
// Bit-exactness discipline (the aegpu recipe, generalized per op):
//   * Every kernel reproduces the CPU implementation's floating-point
//     ROUNDING AND ORDER: accumulation chains are spelled with explicit
//     __dadd_rn/__dsub_rn/__dmul_rn/__ddiv_rn (never fused — NVRTC's default
//     fmad contraction would change results), inner products and reductions
//     run serially in the CPU's documented index order inside one thread,
//     and broadcast-reduce accumulation walks each slot's contributions in
//     the same row-major subsequence order as grad.nu's _g_acc_reduce.
//   * Optimizer scalars that need libm pow (Adam's lr_t) are computed on the
//     HOST with the same expressions opt.nu uses and shipped to the kernel.
//   * exp/log-based unaries (sigmoid, tanh, exp, log, softmax) mirror the
//     CPU FORMULAS exactly, but the device's exp()/log() are CUDA libm: on
//     the gpu package's CPU backend they are glibc and the results are
//     bit-identical; on real CUDA hardware they can differ by a few ulp.
//     Everything else — relu, +, −, ×, ÷, sqrt, matmul/bmm, sum/mean, data
//     movement, SGD/Adam — is bit-exact on BOTH backends. An MLP/AE
//     workload (relu + linear + mse + Adam) is therefore bit-exact
//     end-to-end everywhere; tests/gput_parity_test.nu pins both tiers.
//
// Coverage: every grad.nu op. Restrictions (capture poisons with a message):
// TE_F64 tapes only, and g_bmm only with both operands carrying the full
// batch (no batch broadcast).
//
// Ownership: GProg owns every device buffer; one gput_free. The tape is
// borrowed during capture and NOT needed afterwards (except as the target of
// gput_param_sync_host, which writes trained parameter values back into the
// tape's own tensors so gvar_value keeps working).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `grad.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/tensor/src/ops.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// ── the kernels ───────────────────────────────────────────────────────
// One source, compiled once per kit (cached by entry name). All f64.
@ _gp_src → s {
    ^ `extern "C" __global__ void gp_fill(double* o, long long n, double v)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) o[i] = v;
}
extern "C" __global__ void gp_ew_bc(const double* a, const double* b, double* o, const long long* meta, long long moff, long long n, long long op)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    const long long* m = meta + moff;
    long long nd = m[0];
    const long long* ost = m + 1;
    const long long* ae = ost + nd;
    const long long* be = ae + nd;
    long long rem = i, ao = 0, bo = 0;
    for (long long d = 0; d < nd; d++) {
        long long st = ost[d];
        long long c = st > 0 ? rem / st : 0;
        if (st > 0) rem = rem % st;
        ao += c * ae[d];
        bo += c * be[d];
    }
    double x = a[ao]; double y = b[bo]; double r;
    if (op == 2) r = __dadd_rn(x, y);
    else if (op == 3) r = __dsub_rn(x, y);
    else if (op == 4) r = __dmul_rn(x, y);
    else r = __ddiv_rn(x, y);
    o[i] = r;
}
extern "C" __global__ void gp_scal(const double* a, double* o, long long n, long long op, double c)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    double x = a[i]; double y;
    if (op == 6) y = __dsub_rn(0.0, x);
    else if (op == 7) y = __dadd_rn(x, c);
    else if (op == 8) y = __dmul_rn(x, c);
    else y = x > 0.0 ? x : 0.0;
    o[i] = y;
}
extern "C" __global__ void gp_trans(const double* a, double* o, long long n, long long op)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    double x = a[i]; double y;
    if (op == 10) { double e = exp(__dsub_rn(0.0, x)); y = __ddiv_rn(1.0, __dadd_rn(1.0, e)); }
    else if (op == 11) { double e2 = exp(__dmul_rn(2.0, x)); y = __ddiv_rn(__dsub_rn(e2, 1.0), __dadd_rn(e2, 1.0)); }
    else if (op == 12) y = exp(x);
    else if (op == 13) y = log(x);
    else y = sqrt(x);
    o[i] = y;
}
extern "C" __global__ void gp_reduce(const double* a, double* o, long long n, long long op)
{
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    double acc = 0.0;
    for (long long k = 0; k < n; k++) acc = __dadd_rn(acc, a[k]);
    if (op == 16) acc = __ddiv_rn(acc, (double)n);
    o[0] = acc;
}
extern "C" __global__ void gp_matmul(const double* a, const double* b, double* c, long long M, long long K, long long N)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= M * N) return;
    long long r = i / N, cx = i % N;
    double s = 0.0;
    for (long long p = 0; p < K; p++)
        s = __dadd_rn(s, __dmul_rn(a[r * K + p], b[p * N + cx]));
    c[i] = s;
}
extern "C" __global__ void gp_bmm(const double* a, const double* b, double* c, long long B, long long M, long long K, long long N)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= B * M * N) return;
    long long bb = i / (M * N), rest = i % (M * N);
    long long r = rest / N, cx = rest % N;
    const double* ab = a + bb * M * K;
    const double* bp = b + bb * K * N;
    double s = 0.0;
    for (long long p = 0; p < K; p++)
        s = __dadd_rn(s, __dmul_rn(ab[r * K + p], bp[p * N + cx]));
    c[i] = s;
}
extern "C" __global__ void gp_transpose(const double* a, double* o, long long M, long long N)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= M * N) return;
    long long r = i / N, cx = i % N;
    o[cx * M + r] = a[i];
}
extern "C" __global__ void gp_copy(const double* a, double* o, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) o[i] = a[i];
}
extern "C" __global__ void gp_softmax(const double* x, double* o, long long outer, long long ax, long long inner)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= outer * inner) return;
    long long ou = i / inner, in2 = i % inner;
    long long base = ou * ax * inner + in2;
    double m = x[base];
    for (long long t = 1; t < ax; t++) {
        double xv = x[base + t * inner];
        if (xv > m) m = xv;
    }
    double s = 0.0;
    for (long long t = 0; t < ax; t++) {
        double e = exp(__dsub_rn(x[base + t * inner], m));
        o[base + t * inner] = e;
    }
    for (long long t = 0; t < ax; t++) s = __dadd_rn(s, o[base + t * inner]);
    for (long long t = 0; t < ax; t++) {
        long long ix = base + t * inner;
        o[ix] = __ddiv_rn(o[ix], s);
    }
}
extern "C" __global__ void gp_slice_fwd(const double* a, double* o, const long long* meta, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    long long nd = meta[0];
    const long long* ost = meta + 1;
    const long long* ist = ost + nd;
    const long long* st = ist + nd;
    long long rem = i, ino = 0;
    for (long long d = 0; d < nd; d++) {
        long long sd = ost[d];
        long long c = sd > 0 ? rem / sd : 0;
        if (sd > 0) rem = rem % sd;
        ino += (c + st[d]) * ist[d];
    }
    o[i] = a[ino];
}
extern "C" __global__ void gp_concat_fwd(const double* a, const double* b, double* o, long long outer, long long ax, long long inner, long long da)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= outer * ax * inner) return;
    long long ou = i / (ax * inner);
    long long t = (i / inner) % ax;
    long long in2 = i % inner;
    if (t < da) o[i] = a[(ou * da + t) * inner + in2];
    else o[i] = b[(ou * (ax - da) + (t - da)) * inner + in2];
}
extern "C" __global__ void gp_bw_accred(double* ga, const double* c, const long long* meta, long long moff, long long in_n, long long tfree, double sgn)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= in_n) return;
    const long long* m = meta + moff;
    long long nd = m[0];
    const long long* ost = m + 1;
    const long long* dec = ost + nd;
    const long long* fdim = dec + nd;
    const long long* fdec = fdim + nd;
    long long rem = i, base = 0;
    for (long long d = 0; d < nd; d++) {
        long long st = dec[d];
        long long ix = st > 0 ? rem / st : 0;
        if (st > 0) rem = rem % st;
        base += ix * ost[d];
    }
    double g0 = ga[i];
    for (long long q = 0; q < tfree; q++) {
        long long r2 = q, off = base;
        for (long long d = 0; d < nd; d++) {
            long long st = fdec[d];
            long long jx = st > 0 ? r2 / st : 0;
            if (st > 0) r2 = r2 % st;
            off += jx * ost[d];
        }
        g0 = __dadd_rn(g0, __dmul_rn(sgn, c[off]));
    }
    ga[i] = g0;
}
extern "C" __global__ void gp_bw_unary(double* ga, const double* g, const double* y, const double* x, long long n, long long op, double c)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    double gi = g[i]; double a0 = ga[i];
    if (op == 6) a0 = __dsub_rn(a0, gi);
    else if (op == 7) a0 = __dadd_rn(a0, gi);
    else if (op == 8) a0 = __dadd_rn(a0, __dmul_rn(gi, c));
    else if (op == 9) { if (y[i] > 0.0) a0 = __dadd_rn(a0, gi); }
    else if (op == 10) { double yj = y[i]; a0 = __dadd_rn(a0, __dmul_rn(gi, __dmul_rn(yj, __dsub_rn(1.0, yj)))); }
    else if (op == 11) { double yj = y[i]; a0 = __dadd_rn(a0, __dmul_rn(gi, __dsub_rn(1.0, __dmul_rn(yj, yj)))); }
    else if (op == 12) a0 = __dadd_rn(a0, __dmul_rn(gi, y[i]));
    else if (op == 13) a0 = __dadd_rn(a0, __ddiv_rn(gi, x[i]));
    else a0 = __dadd_rn(a0, __ddiv_rn(gi, __dmul_rn(2.0, y[i])));
    ga[i] = a0;
}
extern "C" __global__ void gp_bw_reduce(double* ga, const double* g, long long an, long long op)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= an) return;
    double g0 = g[0];
    if (op == 16) g0 = __ddiv_rn(g0, (double)an);
    ga[i] = __dadd_rn(ga[i], g0);
}
extern "C" __global__ void gp_bw_mm_a(double* ga, const double* g, const double* b, long long M, long long K, long long N)
{
    long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= M * K) return;
    long long i = t / K, p = t % K;
    double acc = 0.0;
    for (long long j = 0; j < N; j++)
        acc = __dadd_rn(acc, __dmul_rn(g[i * N + j], b[p * N + j]));
    ga[t] = __dadd_rn(ga[t], acc);
}
extern "C" __global__ void gp_bw_mm_b(double* gb, const double* a, const double* g, long long M, long long K, long long N)
{
    long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= K * N) return;
    long long p = t / N, j = t % N;
    double acc = 0.0;
    for (long long i = 0; i < M; i++)
        acc = __dadd_rn(acc, __dmul_rn(a[i * K + p], g[i * N + j]));
    gb[t] = __dadd_rn(gb[t], acc);
}
extern "C" __global__ void gp_bw_bmm_a(double* ga, const double* g, const double* b, long long B, long long M, long long K, long long N)
{
    long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= B * M * K) return;
    long long bb = t / (M * K), rest = t % (M * K);
    long long i = rest / K, p = rest % K;
    const double* gb2 = g + bb * M * N;
    const double* bp = b + bb * K * N;
    double acc = 0.0;
    for (long long j = 0; j < N; j++)
        acc = __dadd_rn(acc, __dmul_rn(gb2[i * N + j], bp[p * N + j]));
    ga[t] = __dadd_rn(ga[t], acc);
}
extern "C" __global__ void gp_bw_bmm_b(double* gbo, const double* a, const double* g, long long B, long long M, long long K, long long N)
{
    long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= B * K * N) return;
    long long bb = t / (K * N), rest = t % (K * N);
    long long p = rest / N, j = rest % N;
    const double* ab = a + bb * M * K;
    const double* gp2 = g + bb * M * N;
    double acc = 0.0;
    for (long long i = 0; i < M; i++)
        acc = __dadd_rn(acc, __dmul_rn(ab[i * K + p], gp2[i * N + j]));
    gbo[t] = __dadd_rn(gbo[t], acc);
}
extern "C" __global__ void gp_bw_transpose(double* ga, const double* g, long long M, long long N)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= M * N) return;
    long long r = i / N, cx = i % N;
    ga[i] = __dadd_rn(ga[i], g[cx * M + r]);
}
extern "C" __global__ void gp_bw_copy(double* ga, const double* g, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) ga[i] = __dadd_rn(ga[i], g[i]);
}
extern "C" __global__ void gp_bw_softmax(double* ga, const double* g, const double* y, long long outer, long long ax, long long inner)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= outer * inner) return;
    long long ou = i / inner, in2 = i % inner;
    long long base = ou * ax * inner + in2;
    double dot = 0.0;
    for (long long t = 0; t < ax; t++) {
        long long ix = base + t * inner;
        dot = __dadd_rn(dot, __dmul_rn(g[ix], y[ix]));
    }
    for (long long t = 0; t < ax; t++) {
        long long ix = base + t * inner;
        ga[ix] = __dadd_rn(ga[ix], __dmul_rn(y[ix], __dsub_rn(g[ix], dot)));
    }
}
extern "C" __global__ void gp_bw_slice(double* ga, const double* g, const long long* meta, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    long long nd = meta[0];
    const long long* ost = meta + 1;
    const long long* ist = ost + nd;
    const long long* st = ist + nd;
    long long rem = i, ioff = 0;
    for (long long d = 0; d < nd; d++) {
        long long sd = ost[d];
        long long c = sd > 0 ? rem / sd : 0;
        if (sd > 0) rem = rem % sd;
        ioff += (c + st[d]) * ist[d];
    }
    ga[ioff] = __dadd_rn(ga[ioff], g[i]);
}
extern "C" __global__ void gp_bw_concat(double* ga, double* gb, const double* g, long long outer, long long ax, long long inner, long long da)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= outer * ax * inner) return;
    long long ou = i / (ax * inner);
    long long t = (i / inner) % ax;
    long long in2 = i % inner;
    if (t < da) {
        long long ix = (ou * da + t) * inner + in2;
        ga[ix] = __dadd_rn(ga[ix], g[i]);
    } else {
        long long ix = (ou * (ax - da) + (t - da)) * inner + in2;
        gb[ix] = __dadd_rn(gb[ix], g[i]);
    }
}
extern "C" __global__ void gp_gnorm(const long long* ptab, long long np, double* o)
{
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    double ss = 0.0;
    for (long long p = 0; p < np; p++) {
        const double* g = (const double*)(unsigned long long)ptab[2 * p];
        long long n = ptab[2 * p + 1];
        for (long long k = 0; k < n; k++)
            ss = __dadd_rn(ss, __dmul_rn(g[k], g[k]));
    }
    o[0] = sqrt(ss);
}
extern "C" __global__ void gp_clipcs(const long long* ptab, long long np, double clip, double* ctl)
{
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    double ss = 0.0;
    for (long long p = 0; p < np; p++) {
        const double* g = (const double*)(unsigned long long)ptab[2 * p];
        long long n = ptab[2 * p + 1];
        for (long long k = 0; k < n; k++)
            ss = __dadd_rn(ss, __dmul_rn(g[k], g[k]));
    }
    double gn = sqrt(ss);
    ctl[1] = (gn > clip) ? (clip / gn) : 1.0;
}
extern "C" __global__ void gp_opt(double* w, const double* g, double* m, double* v, long long n, long long kind, const double* ctl, double alpha, double lr)
{
    long long k = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= n) return;
    double lrt = ctl[0];
    double cs = ctl[1];
    double gk = __dadd_rn(__dmul_rn(g[k], cs), __dmul_rn(alpha, w[k]));
    if (kind == 0) {
        w[k] = __dsub_rn(w[k], __dmul_rn(lr, gk));
    } else {
        double b1 = 0.9; double b2 = 0.999;
        double nm = __dadd_rn(__dmul_rn(b1, m[k]), __dmul_rn(__dsub_rn(1.0, b1), gk));
        double nv = __dadd_rn(__dmul_rn(b2, v[k]), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(gk, gk)));
        m[k] = nm; v[k] = nv;
        w[k] = __dsub_rn(w[k], __ddiv_rn(__dmul_rn(lrt, nm), __dadd_rn(sqrt(nv), 0.00000001)));
    }
}
`
}

// ── the captured program ─────────────────────────────────────────────

// One mirrored node. dims caches per-op host-side launch geometry:
//   binop broadcast: [offB1 offB2 offB3 offBA offBB tfreeA tfreeB]
//   matmul [M K N] · bmm [B M K N] · transpose [M N]
//   softmax/concat [outer axlen inner (da)]
: GpNode {
    i op
    i a
    i b
    f s
    i n  // value element count
    i reach  // 1 = loss ancestor (backward touches it)
    ( Vec i ) dims
    GkBuf val
    GkBuf grad
    GkBuf scr  // out-shaped scratch (mul/div backward)
    GkBuf meta  // i64 stride/offset blocks
}

: GProg {
    b ok
    * GpuKit kit
    ( Vec GpNode ) nodes
    i loss
    i gexec  // CUDA-graph exec handle for one fwd+bwd episode (0 = none)
}

// Device optimizer over a captured program's parameters — opt.nu mirrored:
// per-param L2, global-norm clip, the same runtime 1−β Adam arithmetic, the
// step counter behind the heap pointer.
: GpOpt {
    b ok
    i kind  // 0 sgd · 1 adam
    f lr
    f clip
    i t
    ( Vec i ) ids
    ( Vec f ) alphas
    ( Vec GkBuf ) m
    ( Vec GkBuf ) v
    GkBuf ptab  // [dptr len]* per param (built lazily for the clip norm)
    GkBuf nrm  // 1-elem norm result
    GkBuf ctl  // [lrt, cs] the update kernels read (graph-capturable)
}

@ _gp_nobuf → GkBuf { ^ @ GkBuf { 0 0 0 } }

@ _gp_bfree GkBuf b → v { ? != . b dptr 0 { ( gk_dbuf_free b ) } {} }

// ── capture-time metadata builders ───────────────────────────────────

// Push `nd` entries of `v` (aligned to nd out dims, missing lead = filler).
@ _gp_push_vec ( Vec i ) dst ( Vec i ) src → v {
    : i n ( vec_len [i] src )
    : ~ i k 0
    ~ < k n { ( vec_push [i] dst ( _ti src k ) ) = k + k 1 }
}

// The acc-reduce block for one input: [nd ost dec fdim fdec], plus tfree.
// dec = row-major strides of the input's dims aligned into out dims (1 on
// broadcast dims); fdim/fdec describe the odometer over the broadcast dims.
@ _gp_accred_block ( Vec i ) meta ( Vec i ) oshape ( Vec i ) ost ( Vec i ) eff * u tfree → v {
    : i nd ( vec_len [i] oshape )
    ( vec_push [i] meta nd )
    ( _gp_push_vec meta ost )
    // aligned input dims: out dim where the input participates, else 1
    : ( Vec i ) adim ( vec_new [i] )
    : ( Vec i ) fdim ( vec_new [i] )
    : ~ i d 0
    ~ < d nd {
        ? != ( _ti eff d ) 0 {
            ( vec_push [i] adim ( _ti oshape d ) )
            ( vec_push [i] fdim 1 )
        } {
            ( vec_push [i] adim 1 )
            ( vec_push [i] fdim ( _ti oshape d ) )
        }
        = d + d 1
    }
    : ( Vec i ) dec ( _t_strides adim )
    : ( Vec i ) fdec ( _t_strides fdim )
    ( _gp_push_vec meta dec )
    ( _gp_push_vec meta fdim )
    ( _gp_push_vec meta fdec )
    : ~ i tf 1
    = d 0
    ~ < d nd { = tf * tf ( _ti fdim d ) = d + d 1 }
    ( nurl_poke tfree 0 tf )
    ( vec_free [i] adim ) ( vec_free [i] fdim )
    ( vec_free [i] dec ) ( vec_free [i] fdec )
}

// An ew block [nd ost xe ye].
@ _gp_ew_block ( Vec i ) meta ( Vec i ) ost ( Vec i ) xe ( Vec i ) ye → v {
    : i nd ( vec_len [i] ost )
    ( vec_push [i] meta nd )
    ( _gp_push_vec meta ost )
    ( _gp_push_vec meta xe )
    ( _gp_push_vec meta ye )
}

// ── capture ──────────────────────────────────────────────────────────

@ _gp_fail * GProg pg s why → v {
    ? . pg ok { ( nurl_eprint `gput: capture failed: ` ) ( nurl_eprintln why ) } {}
    = . pg ok F
}

// Upload a CPU tensor's data into a fresh f64 device buffer.
@ _gp_upload_tensor * GpuKit kit * Tensor t → GkBuf {
    : i n ( vec_len [f] . t data )
    : GkBuf b ( gk_dbuf_new kit n GK_F64 )
    ? ( gk_buf_ok b ) {
        ? ( gk_dbuf_upload kit b . t data ) {} { ( gk_dbuf_free b ) ^ ( _gp_nobuf ) }
    } {}
    ^ b
}

// Mirror one recorded episode ([0, tape_len)) onto the device. `loss` is the
// node backward seeds from. Check gput_ok before use.
@ gput_capture * GpuKit kit * GTape tp GVar loss → *GProg {
    : *GProg pg # *GProg ( nurl_alloc Z GProg )
    = . pg ok T
    = . pg kit kit
    = . pg nodes ( vec_new [GpNode] )
    = . pg loss . loss id
    = . pg gexec 0
    ? & ( tape_ok tp ) >= . loss id 0 {} { ( _gp_fail pg `tape is poisoned or loss invalid` ) ^ pg }
    ? ( gk_ok kit ) {} { ( _gp_fail pg `no device` ) ^ pg }
    : i nn ( tape_len tp )
    // reach = loss-ancestor set; need = requires-grad propagation (a param
    // in the ancestor cone). The backward sweep and the gradient BUFFERS
    // exist only where both hold — grad.nu's rule mirrored, and a frozen
    // 4 GB const costs no device gradient memory and no backward launch.
    : ( Vec i ) reach ( vec_new [i] )
    : ~ i k 0
    ~ < k nn { ( vec_push [i] reach 0 ) = k + k 1 }
    ? < . loss id nn { ( vec_set [i] reach . loss id 1 ) } {}
    = k . loss id
    ~ >= k 0 {
        ? == ( _ti reach k ) 1 {
            : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
            ? >= . nd a 0 { ( vec_set [i] reach . nd a 1 ) } {}
            ? >= . nd b 0 { ( vec_set [i] reach . nd b 1 ) } {}
        } {}
        = k - k 1
    }
    : ( Vec i ) needv ( vec_new [i] )
    = k 0
    ~ < k nn {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : ~ i nv 0
        ? == . nd op ( gop_param ) { = nv 1 } {
            ? & >= . nd a 0 == ( _ti needv . nd a ) 1 { = nv 1 } {}
            ? & >= . nd b 0 == ( _ti needv . nd b ) 1 { = nv 1 } {}
        }
        ( vec_push [i] needv nv )
        // the stored per-node flag = BW-active (reach AND need)
        ? & == ( _ti reach k ) 1 == nv 1 {} { ( vec_set [i] reach k 0 ) }
        = k + k 1
    }
    ( vec_free [i] needv )
    // gbuf = which nodes get a gradient BUFFER: every BW-active node, plus
    // both inputs of a BW-active concat (its fused backward kernel writes
    // both sides; an inactive side's buffer is pure workspace — gput_grad
    // still reports zeros for it, like the CPU tape)
    : ( Vec i ) gbuf ( vec_new [i] )
    = k 0
    ~ < k nn { ( vec_push [i] gbuf ( _ti reach k ) ) = k + k 1 }
    = k 0
    ~ < k nn {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        ? & == . nd op ( gop_concat ) == ( _ti reach k ) 1 {
            ( vec_set [i] gbuf . nd a 1 )
            ( vec_set [i] gbuf . nd b 1 )
        } {}
        = k + k 1
    }
    = k 0
    ~ & < k nn . pg ok {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : *Tensor tv # *Tensor ( _g_val tp k )
        ? == . tv dtype TE_F64 {} { ( _gp_fail pg `only TE_F64 tapes` ) }
        : i n ( vec_len [f] . tv data )
        : GkBuf val ( _gp_upload_tensor kit tv )
        : ~ GkBuf grad ( _gp_nobuf )
        ? == ( _ti gbuf k ) 1 { = grad ( gk_dbuf_new kit n GK_F64 ) } {}
        : ~ GkBuf scr ( _gp_nobuf )
        : ~ GkBuf meta ( _gp_nobuf )
        : ( Vec i ) dims ( vec_new [i] )
        ? ( gk_buf_ok val ) {} { ( _gp_fail pg `device alloc failed` ) }
        ? == ( _ti gbuf k ) 1 {
            ? ( gk_buf_ok grad ) {} { ( _gp_fail pg `device alloc failed` ) }
        } {}
        : i op . nd op
        ? & >= op ( gop_add ) <= op ( gop_div ) {
            // binop: ew blocks B0(fwd) B1(g,b) B2(g,a) B3(g,g) + accred A/B
            : *Tensor ta # *Tensor ( _g_val tp . nd a )
            : *Tensor tb # *Tensor ( _g_val tp . nd b )
            : i nd2 ( vec_len [i] . tv shape )
            : ( Vec i ) ost ( _t_strides . tv shape )
            : ( Vec i ) ae ( _t_eff_strides . ta shape nd2 )
            : ( Vec i ) be ( _t_eff_strides . tb shape nd2 )
            : ( Vec i ) mv ( vec_new [i] )
            ( _gp_ew_block mv ost ae be )
            : i offB1 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost be )
            : i offB2 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost ae )
            : i offB3 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost ost )
            : i offBA ( vec_len [i] mv )
            : *u tfa ( nurl_alloc 8 )
            : *u tfb ( nurl_alloc 8 )
            ( _gp_accred_block mv . tv shape ost ae tfa )
            : i offBB ( vec_len [i] mv )
            ( _gp_accred_block mv . tv shape ost be tfb )
            ( vec_push [i] dims offB1 ) ( vec_push [i] dims offB2 )
            ( vec_push [i] dims offB3 ) ( vec_push [i] dims offBA )
            ( vec_push [i] dims offBB )
            ( vec_push [i] dims ( nurl_peek tfa 0 ) )
            ( vec_push [i] dims ( nurl_peek tfb 0 ) )
            ( nurl_free tfa ) ( nurl_free tfb )
            = meta ( gk_dbuf_new kit ( vec_len [i] mv ) GK_I64 )
            ? & ( gk_buf_ok meta ) ( gk_dbuf_upload_i kit meta mv ) {} { ( _gp_fail pg `meta upload failed` ) }
            // mul/div backward materializes an out-shaped contribution
            ? | == op ( gop_mul ) == op ( gop_div ) {
                = scr ( gk_dbuf_new kit n GK_F64 )
                ? ( gk_buf_ok scr ) {} { ( _gp_fail pg `scratch alloc failed` ) }
            } {}
            ( vec_free [i] mv ) ( vec_free [i] ost )
            ( vec_free [i] ae ) ( vec_free [i] be )
        } {}
        ? == op ( gop_matmul ) {
            : *Tensor ta # *Tensor ( _g_val tp . nd a )
            : *Tensor tb # *Tensor ( _g_val tp . nd b )
            ( vec_push [i] dims ( _ti . ta shape 0 ) )
            ( vec_push [i] dims ( _ti . ta shape 1 ) )
            ( vec_push [i] dims ( _ti . tb shape 1 ) )
        } {}
        ? == op ( gop_bmm ) {
            : *Tensor ta # *Tensor ( _g_val tp . nd a )
            : *Tensor tb # *Tensor ( _g_val tp . nd b )
            ? & == ( vec_len [i] . ta shape ) 3 == ( vec_len [i] . tb shape ) 3 {} {
                ( _gp_fail pg `bmm: only full-batch [B,m,k]x[B,k,n] on the device` )
            }
            ? . pg ok {
                ? == ( _ti . ta shape 0 ) ( _ti . tb shape 0 ) {} {
                    ( _gp_fail pg `bmm: only full-batch [B,m,k]x[B,k,n] on the device` )
                }
            } {}
            ? . pg ok {
                ( vec_push [i] dims ( _ti . ta shape 0 ) )
                ( vec_push [i] dims ( _ti . ta shape 1 ) )
                ( vec_push [i] dims ( _ti . ta shape 2 ) )
                ( vec_push [i] dims ( _ti . tb shape 2 ) )
            } {}
        } {}
        ? == op ( gop_transpose ) {
            : *Tensor ta # *Tensor ( _g_val tp . nd a )
            ( vec_push [i] dims ( _ti . ta shape 0 ) )
            ( vec_push [i] dims ( _ti . ta shape 1 ) )
        } {}
        ? | == op ( gop_softmax ) == op ( gop_concat ) {
            : i axis # i . nd s
            : i ndim ( vec_len [i] . tv shape )
            : ~ i outer 1
            : ~ i inner 1
            : ~ i d 0
            ~ < d axis { = outer * outer ( _ti . tv shape d ) = d + d 1 }
            = d + axis 1
            ~ < d ndim { = inner * inner ( _ti . tv shape d ) = d + d 1 }
            ( vec_push [i] dims outer )
            ( vec_push [i] dims ( _ti . tv shape axis ) )
            ( vec_push [i] dims inner )
            ? == op ( gop_concat ) {
                : *Tensor ta # *Tensor ( _g_val tp . nd a )
                ( vec_push [i] dims ( _ti . ta shape axis ) )
            } {}
        } {}
        ? == op ( gop_slice ) {
            : *Tensor ta # *Tensor ( _g_val tp . nd a )
            : s axp ?? ( vec_get [s] . tp aux k ) { T x → x F → # s 0 }
            : *GAux ax # *GAux axp
            : ( Vec i ) ost ( _t_strides . tv shape )
            : ( Vec i ) ist ( _t_strides . ta shape )
            : ( Vec i ) mv ( vec_new [i] )
            ( vec_push [i] mv ( vec_len [i] . tv shape ) )
            ( _gp_push_vec mv ost )
            ( _gp_push_vec mv ist )
            ( _gp_push_vec mv . ax starts )
            = meta ( gk_dbuf_new kit ( vec_len [i] mv ) GK_I64 )
            ? & ( gk_buf_ok meta ) ( gk_dbuf_upload_i kit meta mv ) {} { ( _gp_fail pg `meta upload failed` ) }
            ( vec_free [i] mv ) ( vec_free [i] ost ) ( vec_free [i] ist )
        } {}
        ( vec_push [GpNode] . pg nodes @ GpNode {
            op . nd a . nd b . nd s n ( _ti reach k ) dims val grad scr meta
        } )
        = k + k 1
    }
    ( vec_free [i] reach )
    ( vec_free [i] gbuf )
    ^ pg
}

@ gput_ok * GProg pg → b { ^ . pg ok }

@ gput_free * GProg pg → v {
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [GpNode] . pg nodes k ) {
            T nd → {
                ( _gp_bfree . nd val )
                ( _gp_bfree . nd grad )
                ( _gp_bfree . nd scr )
                ( _gp_bfree . nd meta )
                ( vec_free [i] . nd dims )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [GpNode] . pg nodes )
    ? != . pg gexec 0 { ( gpu_graph_free . pg gexec ) } {}
    ( nurl_free # s pg )
}

@ _gp_node * GProg pg i id → GpNode {
    ^ ?? ( vec_get [GpNode] . pg nodes id ) {
        T x → x
        F → @ GpNode { -1 -1 -1 0.0 0 0 ( vec_new [i] ) ( _gp_nobuf ) ( _gp_nobuf ) ( _gp_nobuf ) ( _gp_nobuf ) }
    }
}

// Fresh values for an input slot (a const's minibatch rows, or a param).
@ gput_set_input * GProg pg GVar v ( Vec f ) data → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] data ) . nd n {} { ^ F }
    ^ ( gk_dbuf_upload . pg kit . nd val data )
}

// ── replay: forward ──────────────────────────────────────────────────

@ _gp_run * GProg pg s name i grid i block ( Vec i ) args → b {
    ^ ( gk_run_dev . pg kit ( _gp_src ) name grid block args )
}

@ _gp_fill_buf * GProg pg GkBuf b f v → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gk_arg_dev b ) )
    ( vec_push [i] a ( gpu_arg_i64 . b n ) )
    ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits v ) ) )
    : b r ( _gp_run pg `gp_fill` ( gk_grid . b n 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

// One forward launch for node `k`. Leaves are data — nothing to do.
@ _gp_fwd_node * GProg pg i k → b {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? <= op ( gop_const ) { ^ T } {}
    : ~ b r T
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gk_arg_dev . nd meta ) )
        ( vec_push [i] a ( gpu_arg_i64 0 ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        = r ( _gp_run pg `gp_ew_bc` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_relu ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits . nd s ) ) )
        = r ( _gp_run pg `gp_scal` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? & >= op ( gop_sigmoid ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        = r ( _gp_run pg `gp_trans` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? | == op ( gop_sum ) == op ( gop_mean ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 . na n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        = r ( _gp_run pg `gp_reduce` 1 1 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        = r ( _gp_run pg `gp_matmul` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_bmm ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 3 ) ) )
        = r ( _gp_run pg `gp_bmm` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_transpose ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        = r ( _gp_run pg `gp_transpose` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_reshape ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        = r ( _gp_run pg `gp_copy` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_softmax ) {
        : GpNode na ( _gp_node pg . nd a )
        : i sl * ( _ti . nd dims 0 ) ( _ti . nd dims 2 )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        = r ( _gp_run pg `gp_softmax` ( gk_grid sl 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_slice ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gk_arg_dev . nd meta ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        = r ( _gp_run pg `gp_slice_fwd` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_concat ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 3 ) ) )
        = r ( _gp_run pg `gp_concat_fwd` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ^ r
}

@ __gput_fwd_launches * GProg pg → b {
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ b r T
    : ~ i k 0
    ~ & < k n r {
        = r ( _gp_fwd_node pg k )
        = k + k 1
    }
    ^ r
}

// Recompute every non-leaf value on the device, in tape order.
@ gput_forward * GProg pg → b {
    ? . pg ok {} { ^ F }
    ( gk_autosync F )
    : b r ( __gput_fwd_launches pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── replay: backward ─────────────────────────────────────────────────

// The out-shaped contribution `src` accumulated into input `dst`'s gradient
// over the broadcast axes (block at `moff`, odometer size `tfree`).
@ _gp_accred * GProg pg GpNode dst GpNode nd GkBuf src i moff i tfree f sgn → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gk_arg_dev . dst grad ) )
    ( vec_push [i] a ( gk_arg_dev src ) )
    ( vec_push [i] a ( gk_arg_dev . nd meta ) )
    ( vec_push [i] a ( gpu_arg_i64 moff ) )
    ( vec_push [i] a ( gpu_arg_i64 . dst n ) )
    ( vec_push [i] a ( gpu_arg_i64 tfree ) )
    ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits sgn ) ) )
    : b r ( _gp_run pg `gp_bw_accred` ( gk_grid . dst n 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

// g (out-shaped) ⊙ other-input → scr, via the ew block at `moff`.
@ _gp_scr_ew * GProg pg GpNode nd GkBuf x GkBuf y i moff i op → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gk_arg_dev x ) )
    ( vec_push [i] a ( gk_arg_dev y ) )
    ( vec_push [i] a ( gk_arg_dev . nd scr ) )
    ( vec_push [i] a ( gk_arg_dev . nd meta ) )
    ( vec_push [i] a ( gpu_arg_i64 moff ) )
    ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
    ( vec_push [i] a ( gpu_arg_i64 op ) )
    : b r ( _gp_run pg `gp_ew_bc` ( gk_grid . nd n 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ _gp_bwd_node * GProg pg i k → b {
    : GpNode nd ( _gp_node pg k )
    ? == . nd reach 1 {} { ^ T }
    : i op . nd op
    ? <= op ( gop_const ) { ^ T } {}
    : ~ b r T
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i offB1 ( _ti . nd dims 0 )
        : i offB2 ( _ti . nd dims 1 )
        : i offB3 ( _ti . nd dims 2 )
        : i offBA ( _ti . nd dims 3 )
        : i offBB ( _ti . nd dims 4 )
        : i tfa ( _ti . nd dims 5 )
        : i tfb ( _ti . nd dims 6 )
        : b needa == . na reach 1
        : b needb == . nb reach 1
        ? == op ( gop_add ) {
            ? needa { = r & r ( _gp_accred pg na nd . nd grad offBA tfa 1.0 ) } {}
            ? needb { = r & r ( _gp_accred pg nb nd . nd grad offBB tfb 1.0 ) } {}
        } {}
        ? == op ( gop_sub ) {
            ? needa { = r & r ( _gp_accred pg na nd . nd grad offBA tfa 1.0 ) } {}
            ? needb { = r & r ( _gp_accred pg nb nd . nd grad offBB tfb -1.0 ) } {}
        } {}
        ? == op ( gop_mul ) {
            ? needa {
                = r & r ( _gp_scr_ew pg nd . nd grad . nb val offB1 ( gop_mul ) )
                = r & r ( _gp_accred pg na nd . nd scr offBA tfa 1.0 )
            } {}
            ? needb {
                = r & r ( _gp_scr_ew pg nd . nd grad . na val offB2 ( gop_mul ) )
                = r & r ( _gp_accred pg nb nd . nd scr offBB tfb 1.0 )
            } {}
        } {}
        ? == op ( gop_div ) {
            ? needa {
                = r & r ( _gp_scr_ew pg nd . nd grad . nb val offB1 ( gop_div ) )
                = r & r ( _gp_accred pg na nd . nd scr offBA tfa 1.0 )
            } {}
            ? needb {
                = r & r ( _gp_scr_ew pg nd . nd grad . nd val offB3 ( gop_mul ) )
                = r & r ( _gp_scr_ew pg nd . nd scr . nb val offB1 ( gop_div ) )
                = r & r ( _gp_accred pg nb nd . nd scr offBB tfb -1.0 )
            } {}
        } {}
        ^ r
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gk_arg_dev . na val ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits . nd s ) ) )
        = r ( _gp_run pg `gp_bw_unary` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? | == op ( gop_sum ) == op ( gop_mean ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gpu_arg_i64 . na n ) )
        ( vec_push [i] a ( gpu_arg_i64 op ) )
        = r ( _gp_run pg `gp_bw_reduce` ( gk_grid . na n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i M ( _ti . nd dims 0 )
        : i K ( _ti . nd dims 1 )
        : i N2 ( _ti . nd dims 2 )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gpu_arg_i64 M ) )
        ( vec_push [i] a ( gpu_arg_i64 K ) )
        ( vec_push [i] a ( gpu_arg_i64 N2 ) )
        ? == . na reach 1 { = r ( _gp_run pg `gp_bw_mm_a` ( gk_grid * M K 256 ) 256 a ) } {}
        ( vec_free [i] a )
        : ( Vec i ) a2 ( vec_new [i] )
        ( vec_push [i] a2 ( gk_arg_dev . nb grad ) )
        ( vec_push [i] a2 ( gk_arg_dev . na val ) )
        ( vec_push [i] a2 ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a2 ( gpu_arg_i64 M ) )
        ( vec_push [i] a2 ( gpu_arg_i64 K ) )
        ( vec_push [i] a2 ( gpu_arg_i64 N2 ) )
        ? == . nb reach 1 { = r & r ( _gp_run pg `gp_bw_mm_b` ( gk_grid * K N2 256 ) 256 a2 ) } {}
        ( vec_free [i] a2 )
        ^ r
    } {}
    ? == op ( gop_bmm ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i B2 ( _ti . nd dims 0 )
        : i M ( _ti . nd dims 1 )
        : i K ( _ti . nd dims 2 )
        : i N2 ( _ti . nd dims 3 )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gk_arg_dev . nb val ) )
        ( vec_push [i] a ( gpu_arg_i64 B2 ) )
        ( vec_push [i] a ( gpu_arg_i64 M ) )
        ( vec_push [i] a ( gpu_arg_i64 K ) )
        ( vec_push [i] a ( gpu_arg_i64 N2 ) )
        ? == . na reach 1 { = r ( _gp_run pg `gp_bw_bmm_a` ( gk_grid * B2 * M K 256 ) 256 a ) } {}
        ( vec_free [i] a )
        : ( Vec i ) a2 ( vec_new [i] )
        ( vec_push [i] a2 ( gk_arg_dev . nb grad ) )
        ( vec_push [i] a2 ( gk_arg_dev . na val ) )
        ( vec_push [i] a2 ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a2 ( gpu_arg_i64 B2 ) )
        ( vec_push [i] a2 ( gpu_arg_i64 M ) )
        ( vec_push [i] a2 ( gpu_arg_i64 K ) )
        ( vec_push [i] a2 ( gpu_arg_i64 N2 ) )
        ? == . nb reach 1 { = r & r ( _gp_run pg `gp_bw_bmm_b` ( gk_grid * B2 * K N2 256 ) 256 a2 ) } {}
        ( vec_free [i] a2 )
        ^ r
    } {}
    ? == op ( gop_transpose ) {
        : GpNode na ( _gp_node pg . nd a )
        : i M ( _ti . nd dims 0 )
        : i N2 ( _ti . nd dims 1 )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gpu_arg_i64 M ) )
        ( vec_push [i] a ( gpu_arg_i64 N2 ) )
        = r ( _gp_run pg `gp_bw_transpose` ( gk_grid * M N2 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_reshape ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        = r ( _gp_run pg `gp_bw_copy` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_softmax ) {
        : GpNode na ( _gp_node pg . nd a )
        : i sl * ( _ti . nd dims 0 ) ( _ti . nd dims 2 )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd val ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        = r ( _gp_run pg `gp_bw_softmax` ( gk_grid sl 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_slice ) {
        : GpNode na ( _gp_node pg . nd a )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd meta ) )
        ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
        = r ( _gp_run pg `gp_bw_slice` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ? == op ( gop_concat ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . na grad ) )
        ( vec_push [i] a ( gk_arg_dev . nb grad ) )
        ( vec_push [i] a ( gk_arg_dev . nd grad ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 0 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 1 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 2 ) ) )
        ( vec_push [i] a ( gpu_arg_i64 ( _ti . nd dims 3 ) ) )
        = r ( _gp_run pg `gp_bw_concat` ( gk_grid . nd n 256 ) 256 a )
        ( vec_free [i] a )
        ^ r
    } {}
    ^ r
}

// Zero every gradient, seed dL/d(loss) = 1, sweep the tape in reverse over
// the loss-ancestor set, then zero const-leaf gradients (grad.nu's epilogue).
@ __gput_bwd_launches * GProg pg → b {
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ b r T
    : ~ i k 0
    ~ & < k n r {
        : GpNode nd ( _gp_node pg k )
        : GkBuf gb2 . nd grad
        ? ( gk_buf_ok gb2 ) { = r ( _gp_fill_buf pg gb2 0.0 ) } {}
        = k + k 1
    }
    ? r {
        : GpNode lo ( _gp_node pg . pg loss )
        : GkBuf lg . lo grad
        ? ( gk_buf_ok lg ) { = r ( _gp_fill_buf pg lg 1.0 ) } {}
    } {}
    = k . pg loss
    ~ & >= k 0 r {
        = r ( _gp_bwd_node pg k )
        = k - k 1
    }
    ^ r
}

@ gput_backward * GProg pg → b {
    ? . pg ok {} { ^ F }
    ( gk_autosync F )
    : b r ( __gput_bwd_launches pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── graph fusion: one episode (forward + backward) as ONE launch ────
// CUDA only; every kernel, argument value and launch order is IDENTICAL
// to the per-node path (bit-identical results) — the graph merely removes
// ~2N launch round-trips per episode. Inputs still refresh normally with
// gput_set_input (plain HtoD; the recorded kernels read the buffers).
// Returns F where graphs are unavailable (CPU backend) — callers keep
// using gput_forward/gput_backward.
@ gput_graph_capture * GProg pg → b {
    ? . pg ok {} { ^ F }
    ? == . pg gexec 0 {} { ^ T }
    : *GpuKit kit . pg kit
    ? ( gpu_graph_begin . kit gpu ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( __gput_fwd_launches pg )
    = r & r ( __gput_bwd_launches pg )
    ( gk_autosync T )
    : i exec ( gpu_graph_end . kit gpu )
    ? & r != exec 0 {
        = . pg gexec exec
        ^ T
    } {}
    ? != exec 0 { ( gpu_graph_free exec ) } {}
    ^ F
}

// Capture a whole TRAINING episode — forward + backward + the optimizer
// update — as one graph. Per episode the host then does: refresh inputs
// (gput_set_input), gpopt_prepare (one 16-byte ctl upload), and ONE
// gput_episode launch. The optimizer's per-step scalars ride the ctl
// buffer, so the captured launches never change.
@ gput_graph_capture_train * GProg pg * GpOpt go → b {
    ? & . pg ok . go ok {} { ^ F }
    ? == . pg gexec 0 {} { ^ T }
    ? ( __gpopt_ensure go pg ) {} { ^ F }
    : *GpuKit kit . pg kit
    ? ( gpu_graph_begin . kit gpu ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( __gput_fwd_launches pg )
    = r & r ( __gput_bwd_launches pg )
    = r & r ( __gpopt_launches go pg )
    ( gk_autosync T )
    : i exec ( gpu_graph_end . kit gpu )
    ? & r != exec 0 {
        = . pg gexec exec
        ^ T
    } {}
    ? != exec 0 { ( gpu_graph_free exec ) } {}
    ^ F
}

// Run one fused episode (falls back to the per-node path without a graph).
@ gput_episode * GProg pg → b {
    ? . pg ok {} { ^ F }
    ? != . pg gexec 0 {
        : *GpuKit kit . pg kit
        ^ == ( gpu_graph_launch . kit gpu . pg gexec ) 0
    } {}
    ? ( gput_forward pg ) {} { ^ F }
    ^ ( gput_backward pg )
}

// ── readback ─────────────────────────────────────────────────────────

// Download a node's value into `out` (resized by the caller to node size).
@ gput_value * GProg pg GVar v ( Vec f ) out → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] out ) . nd n {} { ^ F }
    ^ ( gk_dbuf_download . pg kit . nd val out )
}

@ gput_grad * GProg pg GVar v ( Vec f ) out → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] out ) . nd n {} { ^ F }
    // no gradient flows here (const branch / not a loss ancestor): report
    // zeros, exactly like the CPU tape's grad_of
    ? == . nd reach 1 {} {
        : ~ i k 0
        ~ < k . nd n { ( vec_set [f] out k 0.0 ) = k + k 1 }
        ^ T
    }
    ^ ( gk_dbuf_download . pg kit . nd grad out )
}

// The loss scalar (node value element 0).
@ gput_loss * GProg pg → f {
    : GpNode nd ( _gp_node pg . pg loss )
    : ( Vec f ) o ( vec_new [f] )
    ( vec_push [f] o 0.0 )
    : b r ( gk_dbuf_download . pg kit . nd val o )
    : f v ( _tf o 0 )
    ( vec_free [f] o )
    ? r { ^ v } {}
    ^ 0.0
}

// Write every parameter node's device value back into the CPU tape's own
// tensor (in place), so gvar_value reflects the trained weights.
@ gput_param_sync_host * GProg pg * GTape tp → b {
    ? . pg ok {} { ^ F }
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ b r T
    : ~ i k 0
    ~ & < k n r {
        : GpNode nd ( _gp_node pg k )
        ? == . nd op ( gop_param ) {
            : *Tensor tv # *Tensor ( _g_val tp k )
            = r ( gk_dbuf_download . pg kit . nd val . tv data )
        } {}
        = k + k 1
    }
    ^ r
}

// ── the device optimizer ─────────────────────────────────────────────

@ gpopt_new i kind f lr → *GpOpt {
    : *GpOpt o # *GpOpt ( nurl_alloc Z GpOpt )
    = . o ok T
    = . o kind kind
    = . o lr lr
    = . o clip 0.0
    = . o t 0
    = . o ids ( vec_new [i] )
    = . o alphas ( vec_new [f] )
    = . o m ( vec_new [GkBuf] )
    = . o v ( vec_new [GkBuf] )
    = . o ptab ( _gp_nobuf )
    = . o nrm ( _gp_nobuf )
    = . o ctl ( _gp_nobuf )
    ^ o
}

@ gpopt_sgd_new f lr → *GpOpt { ^ ( gpopt_new 0 lr ) }

@ gpopt_adam_new f lr → *GpOpt { ^ ( gpopt_new 1 lr ) }

@ gpopt_free * GpOpt o → v {
    : i n ( vec_len [GkBuf] . o m )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [GkBuf] . o m k ) { T b → { ( _gp_bfree b ) } F _ → {} }
        ?? ( vec_get [GkBuf] . o v k ) { T b → { ( _gp_bfree b ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [GkBuf] . o m )
    ( vec_free [GkBuf] . o v )
    ( vec_free [i] . o ids )
    ( vec_free [f] . o alphas )
    ( _gp_bfree . o ptab )
    ( _gp_bfree . o nrm )
    ( _gp_bfree . o ctl )
    ( nurl_free # s o )
}

@ gpopt_set_clip * GpOpt o f maxn → v { = . o clip maxn }

// Register one parameter (its Adam moments start at zero, on the device).
@ gpopt_add * GpOpt o * GProg pg GVar p f alpha → v {
    ? & . o ok >= . p id 0 {} { ^ v }
    : GpNode nd ( _gp_node pg . p id )
    : GkBuf mb ( gk_dbuf_new . pg kit . nd n GK_F64 )
    : GkBuf vb ( gk_dbuf_new . pg kit . nd n GK_F64 )
    ? & ( gk_buf_ok mb ) ( gk_buf_ok vb ) {} {
        ( _gp_bfree mb )
        ( _gp_bfree vb )
        = . o ok F
        ^ v
    }
    ? & ( _gp_fill_buf pg mb 0.0 ) ( _gp_fill_buf pg vb 0.0 ) {} { = . o ok F }
    ( vec_push [i] . o ids . p id )
    ( vec_push [f] . o alphas alpha )
    ( vec_push [GkBuf] . o m mb )
    ( vec_push [GkBuf] . o v vb )
}

// Ensure the ctl buffer and (with clipping) the [dptr len] table exist.
@ __gpopt_ensure * GpOpt o * GProg pg → b {
    ? ( gk_buf_ok . o ctl ) {} {
        = . o ctl ( gk_dbuf_new . pg kit 2 GK_F64 )
        ? ( gk_buf_ok . o ctl ) {} { = . o ok F ^ F }
    }
    ? & > . o clip 0.0 ! ( gk_buf_ok . o ptab ) {
        : ( Vec i ) tv ( vec_new [i] )
        : i np ( vec_len [i] . o ids )
        : ~ i k 0
        ~ < k np {
            : GpNode nd ( _gp_node pg ( _ti . o ids k ) )
            ? == . nd reach 1 {
                : GkBuf gb . nd grad
                ( vec_push [i] tv . gb dptr )
                ( vec_push [i] tv . nd n )
            } {}
            = k + k 1
        }
        = . o ptab ( gk_dbuf_new . pg kit ( vec_len [i] tv ) GK_I64 )
        : ~ b up ( gk_buf_ok . o ptab )
        = up & up ( gk_dbuf_upload_i . pg kit . o ptab tv )
        ( vec_free [i] tv )
        ? up {} { = . o ok F ^ F }
    } {}
    ^ T
}

// The HOST half of a step: advance t, compute Adam's lr_t (host pow, like
// opt.nu), and upload [lrt, 1.0] into ctl. The device half then overwrites
// ctl[1] with the clip scale when clipping is on. Graph-safe: per episode
// this is ONE 16-byte upload.
@ gpopt_prepare * GpOpt o * GProg pg → b {
    ? & . o ok . pg ok {} { ^ F }
    ? ( __gpopt_ensure o pg ) {} { ^ F }
    : ~ f lrt . o lr
    ? == . o kind 1 {
        = . o t + . o t 1
        : f tf # f . o t
        = lrt * . o lr / ( float_sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
    } {}
    : ( Vec f ) cv ( vec_new [f] )
    ( vec_push [f] cv lrt )
    ( vec_push [f] cv 1.0 )
    : b up ( gk_dbuf_upload . pg kit . o ctl cv )
    ( vec_free [f] cv )
    ^ up
}

// The DEVICE half: (clip-scale kernel when clipping) + one gp_opt launch
// per backward-active parameter. Pure launches — capturable into a graph.
@ __gpopt_launches * GpOpt o * GProg pg → b {
    : ~ b r T
    ? > . o clip 0.0 {
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a ( gk_arg_dev . o ptab ) )
        ( vec_push [i] a ( gpu_arg_i64 / ( gk_buf_len . o ptab ) 2 ) )
        ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits . o clip ) ) )
        ( vec_push [i] a ( gk_arg_dev . o ctl ) )
        = r ( _gp_run pg `gp_clipcs` 1 1 a )
        ( vec_free [i] a )
    } {}
    : i np ( vec_len [i] . o ids )
    : ~ i pi 0
    ~ & < pi np r {
        : i id ( _ti . o ids pi )
        : GpNode nd ( _gp_node pg id )
        ? == . nd reach 1 {
            : GkBuf mb ?? ( vec_get [GkBuf] . o m pi ) { T x → x F → ( _gp_nobuf ) }
            : GkBuf vb ?? ( vec_get [GkBuf] . o v pi ) { T x → x F → ( _gp_nobuf ) }
            : ( Vec i ) a ( vec_new [i] )
            ( vec_push [i] a ( gk_arg_dev . nd val ) )
            ( vec_push [i] a ( gk_arg_dev . nd grad ) )
            ( vec_push [i] a ( gk_arg_dev mb ) )
            ( vec_push [i] a ( gk_arg_dev vb ) )
            ( vec_push [i] a ( gpu_arg_i64 . nd n ) )
            ( vec_push [i] a ( gpu_arg_i64 . o kind ) )
            ( vec_push [i] a ( gk_arg_dev . o ctl ) )
            ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits ( _tf . o alphas pi ) ) ) )
            ( vec_push [i] a ( gpu_arg_i64 ( f64_to_bits . o lr ) ) )
            = r ( _gp_run pg `gp_opt` ( gk_grid . nd n 256 ) 256 a )
            ( vec_free [i] a )
        } {}
        = pi + pi 1
    }
    ^ r
}

// One update step from the gradients on the device — opt.nu's semantics:
// untouched params (not loss ancestors) are SKIPPED, the clip norm covers
// every registered ancestor's gradient in registration order, Adam's lr_t
// comes from host pow exactly like the CPU path.
@ gpopt_step * GpOpt o * GProg pg → b {
    ? ( gpopt_prepare o pg ) {} { ^ F }
    ( gk_autosync F )
    : b r ( __gpopt_launches o pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}
