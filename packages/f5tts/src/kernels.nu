// packages/f5tts/src/kernels.nu — the kernels a flow-matching DiT needs and
// a language model does not.
//
// The heavy arithmetic — every projection, the feed-forward, the fused
// attention — is gpukit's: its GEMM is tiled and tuned, and its attention is
// the online-softmax one that never writes a score matrix. What is here is
// what F5-TTS has and the rest of this ecosystem does not:
//
//   * ADALN-ZERO MODULATION. A DiT does not condition on time by adding a
//     vector; it derives a scale and a shift per feature from the timestep
//     and applies them to a normalised activation, and it gates the residual
//     by a third one. Fused into the LayerNorm, that is one pass over the
//     activation instead of four.
//   * INTERLEAVED ROPE while splitting heads. The projection writes
//     [n, heads*hd]; attention wants [heads, n, hd]; the rotation is a
//     per-pair 2-D rotation. All three are one kernel, so the activation is
//     read once and written once.
//   * CONV1D along the sequence — depthwise with kernel 7 inside the text
//     encoder's ConvNeXt blocks, and GROUPED with kernel 31 for the
//     convolutional position embedding. Neither exists anywhere else here.
//   * GRN, ConvNeXt-V2's global response normalisation, which normalises
//     down the SEQUENCE rather than across the features — two reductions
//     over the whole block before a single elementwise pass.
//   * MISH (x·tanh(softplus x)) and the two GELUs. Both GELUs are here on
//     purpose: the text encoder uses the exact error-function form and the
//     transformer's feed-forward uses the tanh approximation, and they are
//     different functions.
//
// Every kernel is written once and runs on both of gpukit's backends: the
// CPU one implements __shared__ as thread-local storage and __syncthreads as
// a fiber yield, so a block-wide reduction is portable.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// ── modulated layer norm ────────────────────────────────────────────
//
// y = normalise(x) * (1 + scale) + shift, with the mean and variance taken
// over the feature axis and `scale`/`shift` broadcast down the sequence. The
// variance is the two-pass one — E[x²] − mean² cancels catastrophically when
// the mean is large next to the spread, which is exactly what a residual
// stream looks like by layer twenty.

@ __f5k_modln → s {
    ^ `
extern "C" __global__ void f5_modln(const float* x, float* y, const float* scale,
                                    const float* shift, long long rows, long long d, float eps)
{
    long long r = (long long)blockIdx.x;
    if (r >= rows) return;
    const float* xr = x + r * d;
    float* yr = y + r * d;
    __shared__ float red[256];
    unsigned int tid = threadIdx.x;
    float s = 0.0f;
    for (long long i = tid; i < d; i += blockDim.x) s += xr[i];
    red[tid] = s;
    __syncthreads();
    for (unsigned int st = blockDim.x / 2; st > 0; st >>= 1) {
        if (tid < st) red[tid] += red[tid + st];
        __syncthreads();
    }
    float mean = red[0] / (float)d;
    __syncthreads();
    float q = 0.0f;
    for (long long i = tid; i < d; i += blockDim.x) { float v = xr[i] - mean; q += v * v; }
    red[tid] = q;
    __syncthreads();
    for (unsigned int st = blockDim.x / 2; st > 0; st >>= 1) {
        if (tid < st) red[tid] += red[tid + st];
        __syncthreads();
    }
    float inv = 1.0f / sqrtf(red[0] / (float)d + eps);
    __syncthreads();
    for (long long i = tid; i < d; i += blockDim.x)
        yr[i] = (xr[i] - mean) * inv * (1.0f + scale[i]) + shift[i];
}
`
}

// The same norm with an ordinary learned weight and bias — ConvNeXt's.
@ __f5k_lnaff → s {
    ^ `
extern "C" __global__ void f5_lnaff(const float* x, float* y, const float* w,
                                    const float* b, long long rows, long long d, float eps)
{
    long long r = (long long)blockIdx.x;
    if (r >= rows) return;
    const float* xr = x + r * d;
    float* yr = y + r * d;
    __shared__ float red[256];
    unsigned int tid = threadIdx.x;
    float s = 0.0f;
    for (long long i = tid; i < d; i += blockDim.x) s += xr[i];
    red[tid] = s;
    __syncthreads();
    for (unsigned int st = blockDim.x / 2; st > 0; st >>= 1) {
        if (tid < st) red[tid] += red[tid + st];
        __syncthreads();
    }
    float mean = red[0] / (float)d;
    __syncthreads();
    float q = 0.0f;
    for (long long i = tid; i < d; i += blockDim.x) { float v = xr[i] - mean; q += v * v; }
    red[tid] = q;
    __syncthreads();
    for (unsigned int st = blockDim.x / 2; st > 0; st >>= 1) {
        if (tid < st) red[tid] += red[tid + st];
        __syncthreads();
    }
    float inv = 1.0f / sqrtf(red[0] / (float)d + eps);
    __syncthreads();
    for (long long i = tid; i < d; i += blockDim.x)
        yr[i] = (xr[i] - mean) * inv * w[i] + b[i];
}
`
}

// x += gate * y, the gate broadcast down the sequence. This is the adaLN-zero
// residual: at initialisation the gate is zero and the block is the identity.
@ __f5k_gated_add → s {
    ^ `
extern "C" __global__ void f5_gated_add(float* x, const float* y, const float* gate,
                                        long long rows, long long d)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long n = rows * d;
    if (i < n) x[i] += gate[i % d] * y[i];
}
`
}

// ── heads, and the rotation that goes with them ─────────────────────
//
// [batch*n, heads*hd] → [batch*heads, n, hd], with the interleaved rotary
// embedding applied when `dorope` is set. The tables hold one angle per PAIR
// of features, so cos and sin are [n, hd/2].

@ __f5k_split_rope → s {
    ^ `
// The same split, reading a WIDER source row at a given column offset — so a
// fused q/k/v projection's three thirds can each be taken out in place,
// without a copy.
extern "C" __global__ void f5_split_rope_s(const float* src, float* dst,
                                           const float* cosd, const float* sind,
                                           long long batch, long long n, long long heads,
                                           long long hd, long long dorope,
                                           long long stride, long long coff)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long total = batch * heads * n * hd;
    if (i >= total) return;
    long long e = i % hd;
    long long t = (i / hd) % n;
    long long bh = i / (hd * n);
    long long h = bh % heads;
    long long b = bh / heads;
    const float* row = src + (b * n + t) * stride + coff + h * hd;
    if (dorope == 0) { dst[i] = row[e]; return; }
    long long p = e >> 1;
    float c = cosd[t * (hd / 2) + p];
    float s = sind[t * (hd / 2) + p];
    float x0 = row[p * 2];
    float x1 = row[p * 2 + 1];
    dst[i] = ((e & 1) == 0) ? (x0 * c - x1 * s) : (x1 * c + x0 * s);
}

extern "C" __global__ void f5_split_rope(const float* src, float* dst,
                                         const float* cosd, const float* sind,
                                         long long batch, long long n, long long heads,
                                         long long hd, long long dorope)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long total = batch * heads * n * hd;
    if (i >= total) return;
    long long e = i % hd;
    long long t = (i / hd) % n;
    long long bh = i / (hd * n);
    long long h = bh % heads;
    long long b = bh / heads;
    const float* row = src + ((b * n + t) * heads + h) * hd;
    if (dorope == 0) { dst[i] = row[e]; return; }
    long long p = e >> 1;
    float c = cosd[t * (hd / 2) + p];
    float s = sind[t * (hd / 2) + p];
    float x0 = row[p * 2];
    float x1 = row[p * 2 + 1];
    dst[i] = ((e & 1) == 0) ? (x0 * c - x1 * s) : (x1 * c + x0 * s);
}
`
}

// [batch*heads, n, hd] → [batch*n, heads*hd]
@ __f5k_merge → s {
    ^ `
extern "C" __global__ void f5_merge(const float* src, float* dst,
                                    long long batch, long long n, long long heads, long long hd)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long total = batch * heads * n * hd;
    if (i >= total) return;
    long long e = i % hd;
    long long t = (i / hd) % n;
    long long bh = i / (hd * n);
    long long h = bh % heads;
    long long b = bh / heads;
    dst[((b * n + t) * heads + h) * hd + e] = src[i];
}
`
}

// ── activations ─────────────────────────────────────────────────────
//
// Two GELUs, and they are not interchangeable. nn.GELU() is the exact
// integral of the Gaussian; nn.GELU(approximate="tanh") is a different
// function that happens to be close. F5-TTS uses the exact one inside the
// text encoder's ConvNeXt blocks and the tanh one in every transformer
// feed-forward, so using either everywhere is a small, quiet, systematic
// error in half the network.

@ __f5k_acts → s {
    ^ `
extern "C" __global__ void f5_gelu_erf(float* x, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) { float v = x[i]; x[i] = v * 0.5f * (1.0f + erff(v * 0.70710678118654752f)); }
}

extern "C" __global__ void f5_gelu_tanh(float* x, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        float v = x[i];
        float inner = 0.79788456080286535588f * (v + 0.044715f * v * v * v);
        x[i] = 0.5f * v * (1.0f + tanhf(inner));
    }
}

extern "C" __global__ void f5_silu(float* x, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) { float v = x[i]; x[i] = v / (1.0f + expf(-v)); }
}

extern "C" __global__ void f5_mish(float* x, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        float v = x[i];
        float sp = (v > 20.0f) ? v : log1pf(expf(v));
        x[i] = v * tanhf(sp);
    }
}
`
}

// ── convolution along the sequence ──────────────────────────────────
//
// Both convolutions here are "same"-padded and stride 1, and both are
// written against the [batch, n, channels] layout the rest of the forward
// already uses — so neither needs the pair of transposes PyTorch's
// channels-first Conv1d forces on its callers.

@ __f5k_convs → s {
    ^ `
extern "C" __global__ void f5_conv1d(const float* x, float* y, const float* w,
                                     const float* bias, long long batch, long long n,
                                     long long cin, long long cout, long long K,
                                     long long pad, long long groups)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long total = batch * n * cout;
    if (i >= total) return;
    long long c = i % cout;
    long long t = (i / cout) % n;
    long long b = i / (cout * n);
    long long ipg = cin / groups;
    long long opg = cout / groups;
    long long gbase = (c / opg) * ipg;
    const float* wc = w + c * ipg * K;
    const float* xb = x + b * n * cin;
    float acc = bias ? bias[c] : 0.0f;
    for (long long k = 0; k < K; k++) {
        long long sp = t + k - pad;
        if (sp < 0 || sp >= n) continue;
        const float* xs = xb + sp * cin + gbase;
        const float* wk = wc + k;
        for (long long j = 0; j < ipg; j++) acc += wk[j * K] * xs[j];
    }
    y[i] = acc;
}

// The same convolution with the weights already permuted to [K][cin/groups]
// [cout] — the output channel LAST, so that the 32 threads of a warp (which
// hold 32 consecutive output channels of the same position) read 32
// consecutive floats instead of 32 floats 1984 apart. The arithmetic is
// identical; the memory is a different machine. The permutation happens once,
// while the weights are being uploaded.
// Four POSITIONS per thread. The convolution's weights do not depend on the
// position, so computing four of them together reads each weight once for
// four multiply-adds instead of once for one — and this kernel is bound by
// reading weights, not by the arithmetic: at one position per thread a warp
// fetched 128 bytes of weights and one broadcast float to do 32 MACs.
extern "C" __global__ void f5_conv1d_t4(const float* x, float* y, const float* w,
                                        const float* bias, long long batch, long long n,
                                        long long cin, long long cout, long long K,
                                        long long pad, long long groups)
{
    enum { TT = 4 };
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long nt = (n + TT - 1) / TT;
    long long total = batch * nt * cout;
    if (i >= total) return;
    long long c = i % cout;
    long long t0 = ((i / cout) % nt) * TT;
    long long b = i / (cout * nt);
    long long ipg = cin / groups;
    long long opg = cout / groups;
    long long gbase = (c / opg) * ipg;
    const float* xb = x + b * n * cin;
    float bv = bias ? bias[c] : 0.0f;
    float acc[TT];
    for (int p = 0; p < TT; p++) acc[p] = bv;
    for (long long k = 0; k < K; k++) {
        long long s0 = t0 + k - pad;
        const float* wk = w + k * ipg * cout + c;
        for (long long j = 0; j < ipg; j++) {
            float wv = wk[j * cout];
            const float* xs = xb + s0 * cin + gbase + j;
            for (int p = 0; p < TT; p++) {
                long long sp = s0 + p;
                if (sp >= 0 && sp < n) acc[p] += wv * xs[(long long)p * cin];
            }
        }
    }
    long long base = (b * n + t0) * cout + c;
    for (int p = 0; p < TT; p++) if (t0 + p < n) y[base + (long long)p * cout] = acc[p];
}

extern "C" __global__ void f5_conv1d_t(const float* x, float* y, const float* w,
                                       const float* bias, long long batch, long long n,
                                       long long cin, long long cout, long long K,
                                       long long pad, long long groups)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long total = batch * n * cout;
    if (i >= total) return;
    long long c = i % cout;
    long long t = (i / cout) % n;
    long long b = i / (cout * n);
    long long ipg = cin / groups;
    long long opg = cout / groups;
    long long gbase = (c / opg) * ipg;
    const float* xb = x + b * n * cin;
    float acc = bias ? bias[c] : 0.0f;
    for (long long k = 0; k < K; k++) {
        long long sp = t + k - pad;
        if (sp < 0 || sp >= n) continue;
        const float* xs = xb + sp * cin + gbase;
        const float* wk = w + k * ipg * cout + c;
        for (long long j = 0; j < ipg; j++) acc += wk[j * cout] * xs[j];
    }
    y[i] = acc;
}
`
}

// ── GRN ─────────────────────────────────────────────────────────────
//
// ConvNeXt-V2's global response normalisation. Where a LayerNorm asks how one
// position compares with itself, GRN asks how one FEATURE compares with the
// others over the whole sequence: the L2 norm down the sequence axis, divided
// by the mean of those norms. Two reductions over the entire block, then one
// elementwise pass.

@ __f5k_grn → s {
    ^ `
extern "C" __global__ void f5_grn_gx(const float* x, float* gx, long long rows, long long d)
{
    long long c = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= d) return;
    float s = 0.0f;
    for (long long r = 0; r < rows; r++) { float v = x[r * d + c]; s += v * v; }
    gx[c] = sqrtf(s);
}

extern "C" __global__ void f5_grn_mean(const float* gx, float* out, long long d)
{
    __shared__ float red[256];
    unsigned int tid = threadIdx.x;
    float s = 0.0f;
    for (long long i = tid; i < d; i += blockDim.x) s += gx[i];
    red[tid] = s;
    __syncthreads();
    for (unsigned int st = blockDim.x / 2; st > 0; st >>= 1) {
        if (tid < st) red[tid] += red[tid + st];
        __syncthreads();
    }
    if (tid == 0) out[0] = red[0] / (float)d;
}

extern "C" __global__ void f5_grn_apply(float* x, const float* gx, const float* meanp,
                                        const float* gamma, const float* beta,
                                        long long rows, long long d)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= rows * d) return;
    long long c = i % d;
    float nx = gx[c] / (meanp[0] + 1e-6f);
    float v = x[i];
    x[i] = gamma[c] * (v * nx) + beta[c] + v;
}
`
}

// ── the odds and ends a sampler needs ───────────────────────────────

@ __f5k_misc → s {
    ^ `
extern "C" __global__ void f5_maskrows(float* x, const float* keep, long long rows, long long d)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < rows * d) x[i] *= keep[i / d];
}

extern "C" __global__ void f5_concat3(const float* x, const float* cond, const float* txt,
                                      float* out, long long batch, long long n,
                                      long long mel, long long td)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    long long w = 2 * mel + td;
    if (i >= batch * n * w) return;
    long long c = i % w;
    long long r = i / w;
    long long t = r % n;
    if (c < mel)          out[i] = x[t * mel + c];
    else if (c < 2 * mel) out[i] = cond[r * mel + (c - mel)];
    else                  out[i] = txt[r * td + (c - 2 * mel)];
}

extern "C" __global__ void f5_cfg(const float* pred, float* out, long long n,
                                  long long d, float cfg)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n * d) return;
    float p = pred[i];
    float u = pred[n * d + i];
    out[i] = p + (p - u) * cfg;
}

extern "C" __global__ void f5_axpy(float* y, const float* v, float a, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) y[i] += a * v[i];
}

extern "C" __global__ void f5_addinto(float* y, const float* a, long long n)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) y[i] += a[i];
}

extern "C" __global__ void f5_scalecols(float* x, const float* g, long long rows, long long d)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < rows * d) x[i] *= g[i % d];
}

extern "C" __global__ void f5_dup(const float* src, float* dst, long long n, long long copies)
{
    long long i = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n * copies) dst[i] = src[i % n];
}
`
}

// ── launchers ───────────────────────────────────────────────────────
//
// gpukit caches a compiled kernel by NAME, so handing it the source text on
// every launch costs a short string compare, not a compile.

@ __f5k_a3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a )
    ( vec_push [i] v b )
    ( vec_push [i] v c )
    ^ v
}

@ f5k_modln * GpuKit kit i xd i yd i scaled i shiftd i rows i d f eps → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a scaled )
    ( vec_push [i] a shiftd )
    ( vec_push [i] a ( gpu_arg_i64 rows ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    ( vec_push [i] a ( gpu_arg_f32 eps ) )
    : b r ( gk_run_dev kit ( __f5k_modln ) `f5_modln` rows 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_lnaff * GpuKit kit i xd i yd i wd i bd i rows i d f eps → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a wd )
    ( vec_push [i] a bd )
    ( vec_push [i] a ( gpu_arg_i64 rows ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    ( vec_push [i] a ( gpu_arg_f32 eps ) )
    : b r ( gk_run_dev kit ( __f5k_lnaff ) `f5_lnaff` rows 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_gated_add * GpuKit kit i xd i yd i gated i rows i d → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a gated )
    ( vec_push [i] a ( gpu_arg_i64 rows ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    : b r ( gk_run_dev kit ( __f5k_gated_add ) `f5_gated_add` ( gk_grid * rows d 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_split_rope * GpuKit kit i srcd i dstd i cosd i sind i batch i n i heads i hd i dorope → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a srcd )
    ( vec_push [i] a dstd )
    ( vec_push [i] a cosd )
    ( vec_push [i] a sind )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 heads ) )
    ( vec_push [i] a ( gpu_arg_i64 hd ) )
    ( vec_push [i] a ( gpu_arg_i64 dorope ) )
    : i tot * * * batch heads n hd
    : b r ( gk_run_dev kit ( __f5k_split_rope ) `f5_split_rope` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_split_rope_s * GpuKit kit i srcd i dstd i cosd i sind i batch i n i heads i hd
i dorope i stride i coff → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a srcd )
    ( vec_push [i] a dstd )
    ( vec_push [i] a cosd )
    ( vec_push [i] a sind )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 heads ) )
    ( vec_push [i] a ( gpu_arg_i64 hd ) )
    ( vec_push [i] a ( gpu_arg_i64 dorope ) )
    ( vec_push [i] a ( gpu_arg_i64 stride ) )
    ( vec_push [i] a ( gpu_arg_i64 coff ) )
    : i tot * * * batch heads n hd
    : b r ( gk_run_dev kit ( __f5k_split_rope ) `f5_split_rope_s` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_merge * GpuKit kit i srcd i dstd i batch i n i heads i hd → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a srcd )
    ( vec_push [i] a dstd )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 heads ) )
    ( vec_push [i] a ( gpu_arg_i64 hd ) )
    : i tot * * * batch heads n hd
    : b r ( gk_run_dev kit ( __f5k_merge ) `f5_merge` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ __f5k_act * GpuKit kit s name i xd i n → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( __f5k_acts ) name ( gk_grid n 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_gelu_erf * GpuKit kit i xd i n → b { ^ ( __f5k_act kit `f5_gelu_erf` xd n ) }

@ f5k_gelu_tanh * GpuKit kit i xd i n → b { ^ ( __f5k_act kit `f5_gelu_tanh` xd n ) }

@ f5k_silu * GpuKit kit i xd i n → b { ^ ( __f5k_act kit `f5_silu` xd n ) }

@ f5k_mish * GpuKit kit i xd i n → b { ^ ( __f5k_act kit `f5_mish` xd n ) }

// One grouped convolution covers all three shapes this port needs:
// depthwise (groups = channels), fully connected across channels
// (groups = 1) and the position embedding's sixteen groups.
@ f5k_conv1d * GpuKit kit i xd i yd i wd i bd i batch i n i cin i cout i K i pad i groups → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a wd )
    ( vec_push [i] a bd )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 cin ) )
    ( vec_push [i] a ( gpu_arg_i64 cout ) )
    ( vec_push [i] a ( gpu_arg_i64 K ) )
    ( vec_push [i] a ( gpu_arg_i64 pad ) )
    ( vec_push [i] a ( gpu_arg_i64 groups ) )
    : i tot * * batch n cout
    : b r ( gk_run_dev kit ( __f5k_convs ) `f5_conv1d` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

// The transposed-weight form. Same arguments, same result.
// The four-position form. Same weights, same result, a quarter of the weight
// traffic.
@ f5k_conv1d_t4 * GpuKit kit i xd i yd i wd i bd i batch i n i cin i cout i K i pad i groups → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a wd )
    ( vec_push [i] a bd )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 cin ) )
    ( vec_push [i] a ( gpu_arg_i64 cout ) )
    ( vec_push [i] a ( gpu_arg_i64 K ) )
    ( vec_push [i] a ( gpu_arg_i64 pad ) )
    ( vec_push [i] a ( gpu_arg_i64 groups ) )
    : i tot * * batch / + n 3 4 cout
    : b r ( gk_run_dev kit ( __f5k_convs ) `f5_conv1d_t4` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_conv1d_t * GpuKit kit i xd i yd i wd i bd i batch i n i cin i cout i K i pad i groups → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a yd )
    ( vec_push [i] a wd )
    ( vec_push [i] a bd )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 cin ) )
    ( vec_push [i] a ( gpu_arg_i64 cout ) )
    ( vec_push [i] a ( gpu_arg_i64 K ) )
    ( vec_push [i] a ( gpu_arg_i64 pad ) )
    ( vec_push [i] a ( gpu_arg_i64 groups ) )
    : i tot * * batch n cout
    : b r ( gk_run_dev kit ( __f5k_convs ) `f5_conv1d_t` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_grn * GpuKit kit i xd i gxd i meand i gammad i betad i rows i d → b {
    : ( Vec i ) a1 ( __f5k_a3 xd gxd ( gpu_arg_i64 rows ) )
    ( vec_push [i] a1 ( gpu_arg_i64 d ) )
    : ~ b r ( gk_run_dev kit ( __f5k_grn ) `f5_grn_gx` ( gk_grid d 256 ) 256 a1 )
    ( vec_free [i] a1 )
    ? r {} { ^ F }
    : ( Vec i ) a2 ( __f5k_a3 gxd meand ( gpu_arg_i64 d ) )
    = r ( gk_run_dev kit ( __f5k_grn ) `f5_grn_mean` 1 256 a2 )
    ( vec_free [i] a2 )
    ? r {} { ^ F }
    : ( Vec i ) a3 ( vec_new [i] )
    ( vec_push [i] a3 xd )
    ( vec_push [i] a3 gxd )
    ( vec_push [i] a3 meand )
    ( vec_push [i] a3 gammad )
    ( vec_push [i] a3 betad )
    ( vec_push [i] a3 ( gpu_arg_i64 rows ) )
    ( vec_push [i] a3 ( gpu_arg_i64 d ) )
    = r ( gk_run_dev kit ( __f5k_grn ) `f5_grn_apply` ( gk_grid * rows d 256 ) 256 a3 )
    ( vec_free [i] a3 )
    ^ r
}

@ f5k_maskrows * GpuKit kit i xd i keepd i rows i d → b {
    : ( Vec i ) a ( __f5k_a3 xd keepd ( gpu_arg_i64 rows ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_maskrows` ( gk_grid * rows d 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_concat3 * GpuKit kit i xd i condd i txtd i outd i batch i n i mel i td → b {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a xd )
    ( vec_push [i] a condd )
    ( vec_push [i] a txtd )
    ( vec_push [i] a outd )
    ( vec_push [i] a ( gpu_arg_i64 batch ) )
    ( vec_push [i] a ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 mel ) )
    ( vec_push [i] a ( gpu_arg_i64 td ) )
    : i tot * * batch n + * 2 mel td
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_concat3` ( gk_grid tot 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_cfg * GpuKit kit i predd i outd i n i d f cfg → b {
    : ( Vec i ) a ( __f5k_a3 predd outd ( gpu_arg_i64 n ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    ( vec_push [i] a ( gpu_arg_f32 cfg ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_cfg` ( gk_grid * n d 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_axpy * GpuKit kit i yd i vd f a i n → b {
    : ( Vec i ) ar ( __f5k_a3 yd vd ( gpu_arg_f32 a ) )
    ( vec_push [i] ar ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_axpy` ( gk_grid n 256 ) 256 ar )
    ( vec_free [i] ar )
    ^ r
}

@ f5k_addinto * GpuKit kit i yd i ad i n → b {
    : ( Vec i ) ar ( __f5k_a3 yd ad ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_addinto` ( gk_grid n 256 ) 256 ar )
    ( vec_free [i] ar )
    ^ r
}

@ f5k_scalecols * GpuKit kit i xd i gd i rows i d → b {
    : ( Vec i ) a ( __f5k_a3 xd gd ( gpu_arg_i64 rows ) )
    ( vec_push [i] a ( gpu_arg_i64 d ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_scalecols` ( gk_grid * rows d 256 ) 256 a )
    ( vec_free [i] a )
    ^ r
}

@ f5k_dup * GpuKit kit i srcd i dstd i n i copies → b {
    : ( Vec i ) ar ( __f5k_a3 srcd dstd ( gpu_arg_i64 n ) )
    ( vec_push [i] ar ( gpu_arg_i64 copies ) )
    : b r ( gk_run_dev kit ( __f5k_misc ) `f5_dup` ( gk_grid * n copies 256 ) 256 ar )
    ( vec_free [i] ar )
    ^ r
}
