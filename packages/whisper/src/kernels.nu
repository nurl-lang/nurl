// packages/whisper/src/kernels.nu — the encoder/decoder kernels.
//
// CUDA-C sources compiled by packages/gpu, which runs the SAME text on the CUDA
// backend (via NVRTC) and on the CPU/OpenMP backend (via a compat shim). No
// __shared__, no __syncthreads: whatever runs on the GPU runs identically on the
// host, and the test suite requires the two to agree.
//
// Whisper is not the llama shape, and every kernel here is a place it differs:
//
//   * LAYERNORM, not RMSNorm — it subtracts the mean and it has a BIAS.
//   * GELU with the ERROR FUNCTION, not the tanh approximation. HF's
//     ACT2FN["gelu"] is the exact one; the tanh form is a different function and
//     using it would be a quiet, small, everywhere-wrong bias.
//   * CONV1D: two of them in front of the encoder (stride 1 then stride 2),
//     which is what turns 3000 spectrogram frames into 1500 encoder positions.
//   * NON-CAUSAL attention. Everything in this ecosystem so far has masked the
//     future; the whisper encoder looks at the whole 30 seconds at once, and the
//     decoder's cross-attention looks at all of it too.
//
// Weights are f32 (safetensors), so there is no quantised matvec zoo here — one
// warp-per-row matvec, coalesced the way nurllama's is.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`

: WhKernels {
    GpuKernel matvec  // y = W x (+ bias), one thread per row — portable
    GpuKernel matvec_w  // the same, one WARP per row (CUDA only)
    GpuKernel matvec_t  // one warp per row × EIGHT positions (CUDA only)
    b warp
    GpuKernel layernorm
    GpuKernel gelu
    GpuKernel conv1d
    GpuKernel attn_sc  // scores = q·k / sqrt(hd), NO causal mask
    GpuKernel attn_out  // softmax(scores) · v
    GpuKernel addv
    GpuKernel addrow
    GpuKernel scale
    GpuKernel cvt_f16  // f16/bf16 weights → f32, ON THE DEVICE
    GpuKernel cvt_bf16
    GpuKernel getrow  // one row of the embedding table → the activation
    GpuKernel setrow  // write a row INTO the KV cache
    b ok
}

// The portable matvec: one thread per output row. `bias` may be 0 — whisper's
// k_proj has none, alone among its projections.
@ __wk_matvec → s {
    ^ `extern "C" __global__ void matvec(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        const float* w  = W + (long long)r*cols;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int c = 0; c < cols; ++c) acc += w[c]*xb[c];
        y[(long long)b*rows + r] = acc + (bias ? bias[r] : 0.f);
    }`
}

// One WARP per output row: the 32 lanes stride through the row together, so each
// warp's loads are one contiguous span, and a shuffle reduction folds the lane
// partials. __shfl_down_sync exists only on CUDA, so the CPU/OpenMP backend runs
// the portable kernel above — and the test suite requires the two to agree.
@ __wk_matvec_w → s {
    ^ `
    __device__ static inline float wh_warp_sum(float v) {
        for (int off = 16; off > 0; off >>= 1) v += __shfl_down_sync(0xffffffffu, v, off);
        return v;
    }
    extern "C" __global__ void matvec_w(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch) {
        int gid  = blockIdx.x*blockDim.x + threadIdx.x;
        int warp = gid >> 5, lane = gid & 31;
        if (warp >= rows*batch) return;
        int b = warp / rows, r = warp % rows;
        const float* w  = W + (long long)r*cols;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int c = lane; c < cols; c += 32) acc += w[c]*xb[c];
        acc = wh_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc + (bias ? bias[r] : 0.f);
    }`
}

// The encoder runs 1500 positions through the same weight matrix, and the
// warp-per-row kernel above re-reads that matrix FOR EVERY ONE OF THEM: for
// distil-large-v3 that is 1500 x 840 MB of weight traffic per encoder pass, and
// it is the whole reason a transcription spent 2.5 s in the encoder.
//
// This one gives a warp a row AND EIGHT POSITIONS: w[c] is loaded once and
// multiplied into eight accumulators. Eight times less weight traffic, the same
// arithmetic. (nurllama tried the same trick on its DECODE path and it lost —
// there the batch is 1, so there is nothing to amortise. The regime is what
// decides, not the trick.)
@ __wk_matvec_t → s {
    ^ `
    __device__ static inline float wh_warp_sum_t(float v) {
        for (int off = 16; off > 0; off >>= 1) v += __shfl_down_sync(0xffffffffu, v, off);
        return v;
    }
    extern "C" __global__ void matvec_t(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch) {
        int gid  = blockIdx.x*blockDim.x + threadIdx.x;
        int warp = gid >> 5, lane = gid & 31;
        int tiles = (batch + 7) / 8;
        if (warp >= rows*tiles) return;
        int t = warp / rows, r = warp % rows;
        int b0 = t*8;
        const float* w = W + (long long)r*cols;
        float acc[8];
        for (int j = 0; j < 8; ++j) acc[j] = 0.f;
        for (int c = lane; c < cols; c += 32) {
            float wc = w[c];                       // ONE load, eight uses
            for (int j = 0; j < 8; ++j) {
                int b = b0 + j;
                if (b < batch) acc[j] += wc * x[(long long)b*cols + c];
            }
        }
        float bs = bias ? bias[r] : 0.f;
        for (int j = 0; j < 8; ++j) {
            float v = wh_warp_sum_t(acc[j]);
            int b = b0 + j;
            if (lane == 0 && b < batch) y[(long long)b*rows + r] = v + bs;
        }
    }`
}

// LayerNorm: subtract the mean, divide by the standard deviation, scale and
// SHIFT. RMSNorm does none of the mean and none of the shift, which is why a
// model trained with one cannot be run with the other.
@ __wk_layernorm → s {
    ^ `extern "C" __global__ void layernorm(
        const float* __restrict__ x, const float* __restrict__ w,
        const float* __restrict__ b, float* __restrict__ y,
        int n, float eps, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= n*batch) return;
        int row = idx / n, i = idx % n;
        const float* xr = x + (long long)row*n;
        float mean = 0.f;
        for (int j = 0; j < n; ++j) mean += xr[j];
        mean /= (float)n;
        float var = 0.f;
        for (int j = 0; j < n; ++j) { float d = xr[j] - mean; var += d*d; }
        var /= (float)n;
        float inv = rsqrtf(var + eps);
        y[(long long)row*n + i] = (xr[i] - mean)*inv*w[i] + b[i];
    }`
}

// GELU, exact: 0.5·x·(1 + erf(x/√2)). NOT the tanh approximation — whisper was
// trained with this one, and the two differ by enough to matter once it has run
// through 32 encoder layers.
@ __wk_gelu → s {
    ^ `extern "C" __global__ void gelu(float* x, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) {
            float v = x[i];
            x[i] = 0.5f*v*(1.f + erff(v*0.70710678118654752440f));
        }
    }`
}

// Conv1d over time, kernel 3, `pad` on both sides, `stride` between outputs.
// Layout: x is [T_in][C_in] (a spectrogram frame is contiguous), W is
// [C_out][C_in][3] as safetensors stores it, y is [T_out][C_out].
@ __wk_conv1d → s {
    ^ `extern "C" __global__ void conv1d(
        const float* __restrict__ x, const float* __restrict__ W,
        const float* __restrict__ bias, float* __restrict__ y,
        int T_in, int C_in, int C_out, int stride, int pad) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int T_out = (T_in + 2*pad - 3)/stride + 1;
        if (idx >= T_out*C_out) return;
        int t = idx / C_out, o = idx % C_out;
        float acc = bias ? bias[o] : 0.f;
        for (int k = 0; k < 3; ++k) {
            int ti = t*stride + k - pad;
            if (ti < 0 || ti >= T_in) continue;     // zero padding
            const float* xi = x + (long long)ti*C_in;
            const float* wi = W + ((long long)o*C_in)*3 + k;
            for (int c = 0; c < C_in; ++c) acc += xi[c] * wi[(long long)c*3];
        }
        y[(long long)t*C_out + o] = acc;
    }`
}

// Attention scores, NON-CAUSAL: every query sees every key. `nkey` is the number
// of keys (the encoder's own length for self-attention, the encoder's length for
// the decoder's cross-attention, the tokens so far for the decoder's causal
// self-attention — which passes its own mask through `causal`).
@ __wk_attn_sc → s {
    ^ `extern "C" __global__ void attn_sc(
        const float* __restrict__ q, const float* __restrict__ K,
        float* __restrict__ scores,
        int nh, int hd, int nq, int nkey, float qscale, int causal) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= nh*nq*nkey) return;
        int t  = idx % nkey;
        int qh = idx / nkey;
        int h  = qh % nh, i = qh / nh;      // head, query position
        if (causal && t > i) {              // the decoder's self-attention
            scores[(long long)qh*nkey + t] = -1e30f;
            return;
        }
        const float* qv = q + (long long)i*nh*hd + (long long)h*hd;
        const float* kv = K + (long long)t*nh*hd + (long long)h*hd;
        float d = 0.f;
        for (int j = 0; j < hd; ++j) d += qv[j]*kv[j];
        scores[(long long)qh*nkey + t] = d * qscale;
    }`
}

@ __wk_attn_out → s {
    ^ `extern "C" __global__ void attn_out(
        const float* __restrict__ V, const float* __restrict__ scores,
        float* __restrict__ out, int nh, int hd, int nq, int nkey) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= nh*nq*hd) return;
        int d  = idx % hd;
        int qh = idx / hd;
        int h  = qh % nh, i = qh / nh;
        const float* sc = scores + (long long)qh*nkey;
        float mx = -1e30f;
        for (int t = 0; t < nkey; ++t) if (sc[t] > mx) mx = sc[t];
        float sum = 0.f, acc = 0.f;
        for (int t = 0; t < nkey; ++t) {
            float p = expf(sc[t] - mx);
            sum += p;
            acc += p * V[(long long)t*nh*hd + (long long)h*hd + d];
        }
        out[(long long)i*nh*hd + (long long)h*hd + d] = acc / sum;
    }`
}

// Widen f16 / bf16 weights to f32 ON THE DEVICE.
//
// A whisper checkpoint is f16, and the host loop that widened it — one function
// call and four byte-writes per element, 378 million of them for
// distil-large-v3 — was most of what a transcription cost. Uploading the raw
// halves and widening them here does the same arithmetic where there are
// thousands of threads for it, and halves the PCIe traffic on the way.
//
// The decode is a bit trick rather than __half: NVRTC has no cuda_fp16.h and the
// CPU backend's shim has no half type at all. Same source, both backends.
@ __wk_cvt_f16 → s {
    ^ `extern "C" __global__ void cvt_f16(const unsigned char* src, float* dst, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i >= n) return;
        unsigned int h = (unsigned int)src[2*i] | ((unsigned int)src[2*i+1] << 8);
        unsigned int sign = (h >> 15) << 31;
        unsigned int e = (h >> 10) & 31u;
        unsigned int m = h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                m &= 1023u;
                bits = sign | ((unsigned int)ex << 23) | (m << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        // a UNION, not memcpy and not __half: memcpy needs a header the CPU
        // shim does not include, and __half needs cuda_fp16.h, which NVRTC does
        // not have. This compiles identically on both backends — the same trick
        // nurllama's quant kernels use.
        union { unsigned int u; float f; } cv;
        cv.u = bits;
        dst[i] = cv.f;
    }`
}

// bf16 is the top 16 bits of an f32 — the widening is a shift.
@ __wk_cvt_bf16 → s {
    ^ `extern "C" __global__ void cvt_bf16(const unsigned char* src, float* dst, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i >= n) return;
        unsigned int bits = (((unsigned int)src[2*i] | ((unsigned int)src[2*i+1] << 8))) << 16;
        union { unsigned int u; float f; } cv;
        cv.u = bits;
        dst[i] = cv.f;
    }`
}

// The embedding table is on the device (it is also the output projection —
// whisper ties them), so a token's row is a copy, not a host round-trip.
@ __wk_getrow → s {
    ^ `extern "C" __global__ void getrow(const float* table, float* y, int row, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) y[i] = table[(long long)row*n + i];
    }`
}

// Append a vector to a cache at `row` — the decoder's KV cache grows one
// position per token, and the k/v it just computed belong at the end.
@ __wk_setrow → s {
    ^ `extern "C" __global__ void setrow(float* cache, const float* v, int row, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) cache[(long long)row*n + i] = v[i];
    }`
}

@ __wk_addv → s {
    ^ `extern "C" __global__ void addv(float* a, const float* b, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) a[i] += b[i];
    }`
}

// Add a row vector to every row of a batch (a bias, or the positional
// embedding).
@ __wk_addrow → s {
    ^ `extern "C" __global__ void addrow(float* a, const float* v, int n, int batch) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n*batch) a[i] += v[i % n];
    }`
}

@ __wk_scale → s {
    ^ `extern "C" __global__ void scale(float* x, float s, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) x[i] *= s;
    }`
}

@ wk_build Gpu g → WhKernels {
    : GpuKernel k1 ( gpu_compile g ( __wk_matvec ) `matvec` )
    : b want_warp == ( gpu_backend ) 0
    : GpuKernel k1w ? want_warp ( gpu_compile g ( __wk_matvec_w ) `matvec_w` ) @ GpuKernel { 0 0 }
    : GpuKernel k1t ? want_warp ( gpu_compile g ( __wk_matvec_t ) `matvec_t` ) @ GpuKernel { 0 0 }
    : b warp & want_warp & ( gpu_kernel_ok k1w ) ( gpu_kernel_ok k1t )
    : GpuKernel k2 ( gpu_compile g ( __wk_layernorm ) `layernorm` )
    : GpuKernel k3 ( gpu_compile g ( __wk_gelu ) `gelu` )
    : GpuKernel k4 ( gpu_compile g ( __wk_conv1d ) `conv1d` )
    : GpuKernel k5 ( gpu_compile g ( __wk_attn_sc ) `attn_sc` )
    : GpuKernel k6 ( gpu_compile g ( __wk_attn_out ) `attn_out` )
    : GpuKernel k7 ( gpu_compile g ( __wk_addv ) `addv` )
    : GpuKernel k8 ( gpu_compile g ( __wk_addrow ) `addrow` )
    : GpuKernel k9 ( gpu_compile g ( __wk_scale ) `scale` )
    : GpuKernel k12 ( gpu_compile g ( __wk_cvt_f16 ) `cvt_f16` )
    : GpuKernel k13 ( gpu_compile g ( __wk_cvt_bf16 ) `cvt_bf16` )
    : GpuKernel k10 ( gpu_compile g ( __wk_getrow ) `getrow` )
    : GpuKernel k11 ( gpu_compile g ( __wk_setrow ) `setrow` )
    : b ok1 & & ( gpu_kernel_ok k1 ) ( gpu_kernel_ok k2 ) & ( gpu_kernel_ok k3 ) ( gpu_kernel_ok k4 )
    : b ok2 & & ( gpu_kernel_ok k5 ) ( gpu_kernel_ok k6 ) & ( gpu_kernel_ok k7 ) ( gpu_kernel_ok k8 )
    : b ok3 & ( gpu_kernel_ok k9 ) & ( gpu_kernel_ok k10 ) ( gpu_kernel_ok k11 )
    : b ok4 & ( gpu_kernel_ok k12 ) ( gpu_kernel_ok k13 )
    : b ok & & ok1 ok2 & ok3 ok4
    ^ @ WhKernels { k1 k1w k1t warp k2 k3 k4 k5 k6 k7 k8 k9 k12 k13 k10 k11 ok }
}

@ wk_free WhKernels ks → v {
    ( gpu_kernel_free . ks matvec )
    ? . ks warp {
        ( gpu_kernel_free . ks matvec_w )
        ( gpu_kernel_free . ks matvec_t )
    } {}
    ( gpu_kernel_free . ks layernorm )
    ( gpu_kernel_free . ks gelu )
    ( gpu_kernel_free . ks conv1d )
    ( gpu_kernel_free . ks attn_sc )
    ( gpu_kernel_free . ks attn_out )
    ( gpu_kernel_free . ks addv )
    ( gpu_kernel_free . ks addrow )
    ( gpu_kernel_free . ks scale )
    ( gpu_kernel_free . ks cvt_f16 )
    ( gpu_kernel_free . ks cvt_bf16 )
    ( gpu_kernel_free . ks getrow )
    ( gpu_kernel_free . ks setrow )
}

// ── launchers ───────────────────────────────────────────────────────

// y[batch][rows] = W[rows][cols] · x[batch][cols] + bias[rows]. `bd` may be 0.
@ wk_matvec WhKernels ks i wd i xd i bd i yd i rows i cols i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 rows ) )
    ( vec_push [i] a ( gpu_arg_i32 cols ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    ? . ks warp {
        // Many positions at once (the encoder): amortise the weight matrix over
        // eight of them. One position (the decoder): there is nothing to
        // amortise, and the plain warp kernel is the right one.
        ? >= batch 8 {
            : i tiles / + batch 7 8
            : i threads * * rows tiles 32
            : i _r ( gpu_launch . ks matvec_t ( gpu_grid threads 128 ) 128 a )
        } {
            : i threads * * rows batch 32
            : i _r ( gpu_launch . ks matvec_w ( gpu_grid threads 128 ) 128 a )
        }
    } {
        : i _r ( gpu_launch . ks matvec ( gpu_grid * rows batch 128 ) 128 a )
    }
    ( vec_free [i] a )
}

@ wk_layernorm WhKernels ks i xd i wd i bd i yd i n f eps i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_f32 eps ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i _r ( gpu_launch . ks layernorm ( gpu_grid * n batch 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_gelu WhKernels ks i xd i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks gelu ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_conv1d WhKernels ks i xd i wd i bd i yd i t_in i c_in i c_out i stride i pad → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 t_in ) )
    ( vec_push [i] a ( gpu_arg_i32 c_in ) )
    ( vec_push [i] a ( gpu_arg_i32 c_out ) )
    ( vec_push [i] a ( gpu_arg_i32 stride ) )
    ( vec_push [i] a ( gpu_arg_i32 pad ) )
    : i t_out + / - + t_in * 2 pad 3 stride 1
    : i _r ( gpu_launch . ks conv1d ( gpu_grid * t_out c_out 256 ) 256 a )
    ( vec_free [i] a )
}

// Attention. `causal` 0 = every query sees every key (the encoder, and the
// decoder's cross-attention); 1 = a query sees only keys at or before it (the
// decoder's self-attention).
@ wk_attn WhKernels ks i qd i kd i vd i scd i outd i nh i hd i nq i nkey f qscale i causal → v {
    : ( Vec i ) a1 ( vec_new [i] )
    ( vec_push [i] a1 ( gpu_arg_i64 qd ) )
    ( vec_push [i] a1 ( gpu_arg_i64 kd ) )
    ( vec_push [i] a1 ( gpu_arg_i64 scd ) )
    ( vec_push [i] a1 ( gpu_arg_i32 nh ) )
    ( vec_push [i] a1 ( gpu_arg_i32 hd ) )
    ( vec_push [i] a1 ( gpu_arg_i32 nq ) )
    ( vec_push [i] a1 ( gpu_arg_i32 nkey ) )
    ( vec_push [i] a1 ( gpu_arg_f32 qscale ) )
    ( vec_push [i] a1 ( gpu_arg_i32 causal ) )
    : i _r1 ( gpu_launch . ks attn_sc ( gpu_grid * * nh nq nkey 256 ) 256 a1 )
    ( vec_free [i] a1 )
    : ( Vec i ) a2 ( vec_new [i] )
    ( vec_push [i] a2 ( gpu_arg_i64 vd ) )
    ( vec_push [i] a2 ( gpu_arg_i64 scd ) )
    ( vec_push [i] a2 ( gpu_arg_i64 outd ) )
    ( vec_push [i] a2 ( gpu_arg_i32 nh ) )
    ( vec_push [i] a2 ( gpu_arg_i32 hd ) )
    ( vec_push [i] a2 ( gpu_arg_i32 nq ) )
    ( vec_push [i] a2 ( gpu_arg_i32 nkey ) )
    : i _r2 ( gpu_launch . ks attn_out ( gpu_grid * * nh nq hd 256 ) 256 a2 )
    ( vec_free [i] a2 )
}

@ wk_addv WhKernels ks i ad i bd i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 ad ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks addv ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_addrow WhKernels ks i ad i vd i n i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 ad ) )
    ( vec_push [i] a ( gpu_arg_i64 vd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i _r ( gpu_launch . ks addrow ( gpu_grid * n batch 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_scale WhKernels ks i xd f s i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_f32 s ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks scale ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_getrow WhKernels ks i table i yd i row i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 table ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 row ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks getrow ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ wk_setrow WhKernels ks i cache i vd i row i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 cache ) )
    ( vec_push [i] a ( gpu_arg_i64 vd ) )
    ( vec_push [i] a ( gpu_arg_i32 row ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks setrow ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

// `half` = 1 for f16, 0 for bf16.
@ wk_cvt WhKernels ks i srcd i dstd i n b half → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 srcd ) )
    ( vec_push [i] a ( gpu_arg_i64 dstd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ? half
    { : i _r ( gpu_launch . ks cvt_f16 ( gpu_grid n 256 ) 256 a ) }
    { : i _r ( gpu_launch . ks cvt_bf16 ( gpu_grid n 256 ) 256 a ) }
    ( vec_free [i] a )
}
