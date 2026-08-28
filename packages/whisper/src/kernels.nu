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
    GpuKernel matmul  // 64x64 tiles through shared memory (CUDA only)
    b warp
    GpuKernel layernorm  // one thread per row — portable
    GpuKernel layernorm_b  // one block per row, shared reduction (CUDA)
    GpuKernel gelu
    GpuKernel conv1d
    GpuKernel attn_f  // fused attention, online softmax (CUDA, hd = 64)
    GpuKernel attn_d  // the same, shaped for ONE query (CUDA, hd = 64)
    GpuKernel attn_dm  // and the merge of its per-chunk partials
    GpuKernel attn_sc  // scores = q·k / sqrt(hd), NO causal mask
    GpuKernel attn_out  // softmax(scores) · v
    GpuKernel addv
    GpuKernel addrow
    GpuKernel scale
    GpuKernel cvt_f16  // f16/bf16 weights → f32, ON THE DEVICE
    GpuKernel cvt_bf16
    GpuKernel getrow  // one row of the embedding table → the activation
    GpuKernel setrow  // write a row INTO the KV cache
    GpuKernel argmaxk  // greedy decoding's argmax, on the device
    b ok
}

// The portable matvec: one thread per output row. `bias` may be 0 — whisper's
// k_proj has none, alone among its projections.
@ __wk_matvec → s {
    ^ `
    // f16 -> f32, exact, denormals included — the same conversion cvt_f16 runs
    // as a widening pass; here it runs at the point of use so the weight can
    // STAY half in device memory (half the bytes is half the traffic, and the
    // matvecs are memory-bound). A union for the bit transport: memcpy needs a
    // header the CPU shim lacks, __half needs cuda_fp16.h NVRTC lacks.
    __device__ static inline float wh_h2f(unsigned short h) {
        unsigned int sign = ((unsigned int)h >> 15) << 31;
        unsigned int e = ((unsigned int)h >> 10) & 31u;
        unsigned int m = (unsigned int)h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        union { unsigned int u; float f; } c;
        c.u = bits;
        return c.f;
    }
    __device__ static inline float wh_w(const float* W, int wt, long long i) {
        return wt ? wh_h2f(((const unsigned short*)W)[i]) : W[i];
    }
    extern "C" __global__ void matvec(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch, int wt) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        const float* xb = x + (long long)b*cols;
        long long w0 = (long long)r*cols;
        float acc = 0.f;
        for (int c = 0; c < cols; ++c) acc += wh_w(W, wt, w0 + c)*xb[c];
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

    // f16 -> f32, exact, denormals included — the same conversion cvt_f16 runs
    // as a widening pass; here it runs at the point of use so the weight can
    // STAY half in device memory (half the bytes is half the traffic, and the
    // matvecs are memory-bound). A union for the bit transport: memcpy needs a
    // header the CPU shim lacks, __half needs cuda_fp16.h NVRTC lacks.
    __device__ static inline float wh_h2f(unsigned short h) {
        unsigned int sign = ((unsigned int)h >> 15) << 31;
        unsigned int e = ((unsigned int)h >> 10) & 31u;
        unsigned int m = (unsigned int)h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        union { unsigned int u; float f; } c;
        c.u = bits;
        return c.f;
    }
    __device__ static inline float wh_w(const float* W, int wt, long long i) {
        return wt ? wh_h2f(((const unsigned short*)W)[i]) : W[i];
    }
    extern "C" __global__ void matvec_w(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch, int wt) {
        int gid  = blockIdx.x*blockDim.x + threadIdx.x;
        int warp = gid >> 5, lane = gid & 31;
        if (warp >= rows*batch) return;
        int b = warp / rows, r = warp % rows;
        const float* xb = x + (long long)b*cols;
        long long w0 = (long long)r*cols;
        float acc = 0.f;
        for (int c = lane; c < cols; c += 32) acc += wh_w(W, wt, w0 + c)*xb[c];
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

    __device__ static inline float wh_h2f(unsigned short h) {
        unsigned int sign = ((unsigned int)h >> 15) << 31;
        unsigned int e = ((unsigned int)h >> 10) & 31u;
        unsigned int m = (unsigned int)h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        union { unsigned int u; float f; } c;
        c.u = bits;
        return c.f;
    }
    __device__ static inline float wh_w(const float* W, int wt, long long i) {
        return wt ? wh_h2f(((const unsigned short*)W)[i]) : W[i];
    }
    extern "C" __global__ void matvec_t(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch, int wt) {
        int gid  = blockIdx.x*blockDim.x + threadIdx.x;
        int warp = gid >> 5, lane = gid & 31;
        int tiles = (batch + 7) / 8;
        if (warp >= rows*tiles) return;
        int t = warp / rows, r = warp % rows;
        int b0 = t*8;
        long long w0 = (long long)r*cols;
        float acc[8];
        for (int j = 0; j < 8; ++j) acc[j] = 0.f;
        for (int c = lane; c < cols; c += 32) {
            float wc = wh_w(W, wt, w0 + c);        // ONE load, eight uses
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
// ── The encoder is a GEMM, not a matvec ─────────────────────────────
//
// The encoder projects 1500 positions at once, and matvec_t reads the whole
// weight matrix once per EIGHT of them — 187 passes over 6.5 MB of weights per
// projection. That is not arithmetic, it is memory traffic, and it is where the
// encoder's time went.
//
// A 64x64 output tile held in registers, fed by 64x16 slabs of x and W staged
// through SHARED memory, reads the weight matrix once per 64 positions: eight
// times less traffic, and each of the 256 threads keeps 16 accumulators in
// registers so the arithmetic is dense enough to hide what is left.
//
// This is the kernel packages/gpu could not run on its CPU backend until that
// backend learned __shared__ and __syncthreads() (it runs a block's threads as
// fibers now). It is still launched on CUDA only — shared memory is a hand-rolled
// cache, and a CPU already has a real one, so the flat matvec is the better
// kernel there.
@ __wk_matmul → s {
    ^ `
    #define WH_BM 64
    #define WH_BN 64
    #define WH_BK 16

    __device__ static inline float wh_h2f(unsigned short h) {
        unsigned int sign = ((unsigned int)h >> 15) << 31;
        unsigned int e = ((unsigned int)h >> 10) & 31u;
        unsigned int m = (unsigned int)h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        union { unsigned int u; float f; } c;
        c.u = bits;
        return c.f;
    }
    __device__ static inline float wh_w(const float* W, int wt, long long i) {
        return wt ? wh_h2f(((const unsigned short*)W)[i]) : W[i];
    }
    extern "C" __global__ void matmul(
        const float* __restrict__ W, const float* __restrict__ x,
        const float* __restrict__ bias, float* __restrict__ y,
        int rows, int cols, int batch, int wt) {
        __shared__ float As[WH_BK][WH_BM];   // x  slab: As[k][position]
        __shared__ float Bs[WH_BK][WH_BN];   // W  slab: Bs[k][row]
        int nbb = (batch + WH_BM - 1) / WH_BM;
        int bm  = blockIdx.x % nbb;          // which 64 positions
        int bn  = blockIdx.x / nbb;          // which 64 rows
        int tid = threadIdx.x;               // 256 threads
        int tx  = tid & 15, ty = tid >> 4;   // this thread owns a 4x4 corner
        float acc[4][4];
        for (int i = 0; i < 4; ++i)
            for (int j = 0; j < 4; ++j) acc[i][j] = 0.f;

        for (int k0 = 0; k0 < cols; k0 += WH_BK) {
            // 256 threads stage 16x64 of each slab: four elements apiece.
            // idx splits into (row, k) and NOT (k, row): consecutive threads
            // must read consecutive ADDRESSES, and x and W are row-major in c.
            // The other way round, 32 lanes of a warp each touch a different
            // row — 32 separate memory transactions for what should be one.
            for (int L = 0; L < 4; ++L) {
                int idx = tid + L*256;
                int mm = idx / WH_BK, kk = idx % WH_BK;
                int gk = k0 + kk;
                int gm = bm*WH_BM + mm;
                int gn = bn*WH_BN + mm;
                As[kk][mm] = (gm < batch && gk < cols) ? x[(long long)gm*cols + gk] : 0.f;
                Bs[kk][mm] = (gn < rows  && gk < cols) ? wh_w(W, wt, (long long)gn*cols + gk) : 0.f;
            }
            __syncthreads();
            for (int kk = 0; kk < WH_BK; ++kk) {
                float a[4], b[4];
                for (int i = 0; i < 4; ++i) a[i] = As[kk][ty*4 + i];
                for (int j = 0; j < 4; ++j) b[j] = Bs[kk][tx*4 + j];
                for (int i = 0; i < 4; ++i)
                    for (int j = 0; j < 4; ++j) acc[i][j] += a[i] * b[j];
            }
            __syncthreads();
        }
        for (int i = 0; i < 4; ++i) {
            int gm = bm*WH_BM + ty*4 + i;
            if (gm >= batch) continue;
            for (int j = 0; j < 4; ++j) {
                int gn = bn*WH_BN + tx*4 + j;
                if (gn < rows)
                    y[(long long)gm*rows + gn] = acc[i][j] + (bias ? bias[gn] : 0.f);
            }
        }
    }`
}

// LayerNorm normalises a ROW, so a row's mean and variance are computed once
// per row — not once per element of it. The kernel this replaces gave one thread
// one ELEMENT and had it walk the whole row twice to find them, which is 2n reads
// to produce one output and 2n² per row: 4.9 BILLION reads for the encoder's
// 1500 x 1280, and it cost as much as a 19-GFLOP feed-forward layer. Arithmetic
// is not what a normalisation should be paying for.
//
// One thread per row, and the row is walked twice — total.
@ __wk_layernorm → s {
    ^ `extern "C" __global__ void layernorm(
        const float* __restrict__ x, const float* __restrict__ w,
        const float* __restrict__ b, float* __restrict__ y,
        int n, float eps, int batch) {
        int row = blockIdx.x*blockDim.x + threadIdx.x;
        if (row >= batch) return;
        const float* xr = x + (long long)row*n;
        float mean = 0.f;
        for (int j = 0; j < n; ++j) mean += xr[j];
        mean /= (float)n;
        float var = 0.f;
        for (int j = 0; j < n; ++j) { float d = xr[j] - mean; var += d*d; }
        var /= (float)n;
        float inv = rsqrtf(var + eps);
        for (int j = 0; j < n; ++j)
            y[(long long)row*n + j] = (xr[j] - mean)*inv*w[j] + b[j];
    }`
}

// And on a GPU, one thread per row is 1500 threads — a rounding error of the
// machine. One BLOCK per row instead: 256 threads share the row's sums through
// a shared-memory reduction, so the row is read twice by 256 threads at once and
// every access is coalesced.
@ __wk_layernorm_b → s {
    ^ `extern "C" __global__ void layernorm_b(
        const float* __restrict__ x, const float* __restrict__ w,
        const float* __restrict__ b, float* __restrict__ y,
        int n, float eps, int batch) {
        __shared__ float red[256];
        int row = blockIdx.x;
        if (row >= batch) return;
        int t = threadIdx.x;
        const float* xr = x + (long long)row*n;
        float s = 0.f;
        for (int j = t; j < n; j += 256) s += xr[j];
        red[t] = s;
        __syncthreads();
        for (int off = 128; off > 0; off >>= 1) {
            if (t < off) red[t] += red[t + off];
            __syncthreads();
        }
        float mean = red[0] / (float)n;
        __syncthreads();
        float v = 0.f;
        for (int j = t; j < n; j += 256) { float d = xr[j] - mean; v += d*d; }
        red[t] = v;
        __syncthreads();
        for (int off = 128; off > 0; off >>= 1) {
            if (t < off) red[t] += red[t + off];
            __syncthreads();
        }
        float inv = rsqrtf(red[0] / (float)n + eps);
        for (int j = t; j < n; j += 256)
            y[(long long)row*n + j] = (xr[j] - mean)*inv*w[j] + b[j];
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
// ── Attention, fused ────────────────────────────────────────────────
//
// The encoder's attention was where the time actually was, and it was not the
// arithmetic. attn_sc launches nh·nq·nkey threads — 45 MILLION for one layer of
// distil — and each one re-reads a whole query row and a whole key row from
// global memory to produce a single score. That is ~23 GB of traffic per layer,
// 740 GB per 30-second window, and it also materialises an nh × 1500 × 1500
// score matrix (180 MB) that exists only to be read back by attn_out.
//
// This is the flash-attention shape. One block owns 64 queries of one head and
// keeps them — and its 64 output accumulators — in REGISTERS. Keys and values
// stream past in 64-row slabs through shared memory, so each is read once per
// query tile rather than once per query: about a hundred times less traffic. The
// softmax is computed online (running max and running sum, rescaling the
// accumulator when the max moves), which is what removes the score matrix
// entirely — there is nothing left to store.
//
// The registers are the constraint, and they are why this asks for head_dim =
// 64: `qr[64] + acc[64]` only stays in registers if the loops over them are
// unrollable, so the depth is a compile-time constant. Every whisper has
// head_dim 64 (384/6, 512/8, 768/12, 1024/16, 1280/20 — all 64). Anything else
// falls back to the two-kernel path, which is still correct, just slower.
@ __wk_attn_f → s {
    ^ `
    #define WH_BQ 64
    #define WH_HD 64
    extern "C" __global__ void attn_f(
        const float* __restrict__ q, const float* __restrict__ K,
        const float* __restrict__ V, float* __restrict__ out,
        int nh, int hd, int nq, int nkey, float qscale) {
        __shared__ float Ks[WH_BQ][WH_HD];
        __shared__ float Vs[WH_BQ][WH_HD];
        int h  = blockIdx.x % nh;
        int qt = blockIdx.x / nh;
        int t  = threadIdx.x;
        int i  = qt*WH_BQ + t;
        float qr[WH_HD], acc[WH_HD];
        for (int d = 0; d < WH_HD; ++d) {
            qr[d]  = (i < nq) ? q[(long long)i*nh*WH_HD + (long long)h*WH_HD + d] : 0.f;
            acc[d] = 0.f;
        }
        float m = -1e30f, l = 0.f;
        for (int k0 = 0; k0 < nkey; k0 += WH_BQ) {
            int nn = nkey - k0; if (nn > WH_BQ) nn = WH_BQ;
            for (int idx = t; idx < nn*WH_HD; idx += WH_BQ) {
                int r = idx / WH_HD, d = idx % WH_HD;
                long long o = (long long)(k0 + r)*nh*WH_HD + (long long)h*WH_HD + d;
                Ks[r][d] = K[o];
                Vs[r][d] = V[o];
            }
            __syncthreads();
            for (int j = 0; j < nn; ++j) {
                float s = 0.f;
                for (int d = 0; d < WH_HD; ++d) s += qr[d]*Ks[j][d];
                s *= qscale;
                float mn   = s > m ? s : m;
                float corr = expf(m - mn);
                float p    = expf(s - mn);
                l = l*corr + p;
                for (int d = 0; d < WH_HD; ++d) acc[d] = acc[d]*corr + p*Vs[j][d];
                m = mn;
            }
            __syncthreads();
        }
        if (i < nq) {
            for (int d = 0; d < WH_HD; ++d)
                out[(long long)i*nh*WH_HD + (long long)h*WH_HD + d] = acc[d] / l;
        }
    }`
}

// ── Attention, fused, for ONE query ─────────────────────────────────
//
// attn_f amortises the key/value stream over 64 queries. The DECODER has one
// query — there is nothing to amortise — so it took the two-kernel path, and
// that path is the wrong shape twice over at nq = 1:
//
//   attn_sc  launches nh*1*nkey threads that each read a whole key row to
//            produce one score, and writes an nh x nkey score matrix.
//   attn_out launches nh*1*hd threads — 384 of them on whisper-tiny, 1280 on
//            large — and each ONE walks the whole score row twice (max, then
//            sum) and strides through V with a stride of nh*hd. A 4090 has 128
//            SMs; this uses twelve warps, and every load is its own
//            transaction.
//
// Measured on whisper-tiny: 95 us for one cross-attention (nkey = 1500), 33 us
// for one self-attention — 54% of the whole decode step, against 31 us for the
// 51865-row vocabulary projection that does sixty times the arithmetic.
//
// The shape the machine wants is a SPLIT over the keys. One query and one head
// is a few hundred kilobytes of K and V to stream; handing it to one block
// leaves 122 of 128 SMs idle, which is why simply widening that block from 256
// threads to 1024 bought nothing (62 us to 55). So the keys are cut into
// chunks, one block per (query, head, chunk):
//
//   * scoring: thread t scores key kbeg+t, so a whole pass of keys is scored at
//     once and each key row is read once, by one thread, sequentially.
//   * accumulating: the block splits into WH_S sub-blocks of hd threads; thread
//     d of sub-block s owns output element d and walks its own share of the
//     chunk's keys, reading V[key][d] — CONSECUTIVE d across the sub-block, so
//     the row lands in one transaction.
//   * every sub-block keeps its own online-softmax state (running max, running
//     denominator, accumulator); the sub-blocks merge into one partial, and
//     attn_dm merges the chunks' partials the same way — rescale by
//     exp(m - M). Merging partial softmaxes is associative, so the split is
//     invisible in the answer.
//
// Like attn_f this is NOT bit-identical to the composed path — an online
// softmax rescales a running sum instead of dividing a finished one — and like
// attn_f it is the same value to f32 rounding.
@ __wk_attn_d → s {
    ^ `
    #define WH_HD 64
    #define WH_S  4
    #define WH_NT (WH_HD*WH_S)
    extern "C" __global__ void attn_d(
        const float* __restrict__ q, const float* __restrict__ K,
        const float* __restrict__ V, float* __restrict__ part,
        int nh, int hd, int nq, int nkey, float qscale, int causal,
        int chunk, int nchunk) {
        __shared__ float qs[WH_HD];
        __shared__ float sc[WH_NT];
        __shared__ float pm[WH_S], pl[WH_S], pacc[WH_S][WH_HD];
        int b  = blockIdx.x;
        int c  = b % nchunk;
        int qh = b / nchunk;
        int h  = qh % nh;
        int i  = qh / nh;
        int t  = threadIdx.x;
        int sb = t / WH_HD, d = t % WH_HD;
        if (t < WH_HD) qs[t] = q[(long long)i*nh*WH_HD + (long long)h*WH_HD + t];
        __syncthreads();
        int lim = causal ? (i + 1) : nkey;
        if (lim > nkey) lim = nkey;
        int kbeg = c*chunk;
        int kend = kbeg + chunk; if (kend > lim) kend = lim;
        float m = -1e30f, l = 0.f, acc = 0.f;
        for (int k0 = kbeg; k0 < kend; k0 += WH_NT) {
            int nn = kend - k0; if (nn > WH_NT) nn = WH_NT;
            float sv = -1e30f;
            if (t < nn) {
                const float* kv = K + (long long)(k0+t)*nh*WH_HD + (long long)h*WH_HD;
                float a = 0.f;
                for (int j = 0; j < WH_HD; ++j) a += qs[j]*kv[j];
                sv = a * qscale;
            }
            sc[t] = sv;
            __syncthreads();
            int base = sb*WH_HD;
            int cnt = nn - base; if (cnt > WH_HD) cnt = WH_HD; if (cnt < 0) cnt = 0;
            for (int j = 0; j < cnt; ++j) {
                float sj   = sc[base+j];
                float mn   = sj > m ? sj : m;
                float corr = expf(m - mn);
                float p    = expf(sj - mn);
                l   = l*corr + p;
                acc = acc*corr + p*V[(long long)(k0+base+j)*nh*WH_HD + (long long)h*WH_HD + d];
                m   = mn;
            }
            __syncthreads();
        }
        pacc[sb][d] = acc;
        if (d == 0) { pm[sb] = m; pl[sb] = l; }
        __syncthreads();
        if (t < WH_HD) {
            float M = -1e30f;
            for (int u = 0; u < WH_S; ++u) if (pm[u] > M) M = pm[u];
            float L = 0.f, A = 0.f;
            for (int u = 0; u < WH_S; ++u) {
                float cf = expf(pm[u] - M);
                L += pl[u]*cf;
                A += pacc[u][d]*cf;
            }
            float* po = part + (long long)b*(WH_HD+2);
            po[d] = A;
            if (d == 0) { po[WH_HD] = M; po[WH_HD+1] = L; }
        }
    }`
}

// The chunks' partial softmaxes, merged: one block per (query, head), one
// thread per output element.
@ __wk_attn_dm → s {
    ^ `
    #define WH_HD 64
    extern "C" __global__ void attn_dm(
        const float* __restrict__ part, float* __restrict__ out,
        int nh, int hd, int nq, int nchunk) {
        int qh = blockIdx.x;
        int h  = qh % nh;
        int i  = qh / nh;
        int d  = threadIdx.x;
        float M = -1e30f;
        for (int c = 0; c < nchunk; ++c) {
            float mc = part[(long long)(qh*nchunk + c)*(WH_HD+2) + WH_HD];
            if (mc > M) M = mc;
        }
        float L = 0.f, A = 0.f;
        for (int c = 0; c < nchunk; ++c) {
            const float* po = part + (long long)(qh*nchunk + c)*(WH_HD+2);
            float cf = expf(po[WH_HD] - M);
            L += po[WH_HD+1]*cf;
            A += po[d]*cf;
        }
        out[(long long)i*nh*WH_HD + (long long)h*WH_HD + d] = A / L;
    }`
}

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
    ^ `
    __device__ static inline float wh_h2f(unsigned short h) {
        unsigned int sign = ((unsigned int)h >> 15) << 31;
        unsigned int e = ((unsigned int)h >> 10) & 31u;
        unsigned int m = (unsigned int)h & 1023u;
        unsigned int bits;
        if (e == 0u) {
            if (m == 0u) bits = sign;
            else {
                int ex = 113;
                while (!(m & 1024u)) { m <<= 1; ex--; }
                bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13);
            }
        } else if (e == 31u) {
            bits = sign | 0x7F800000u | (m << 13);
        } else {
            bits = sign | ((e + 112u) << 23) | (m << 13);
        }
        union { unsigned int u; float f; } c;
        c.u = bits;
        return c.f;
    }
    __device__ static inline float wh_w(const float* W, int wt, long long i) {
        return wt ? wh_h2f(((const unsigned short*)W)[i]) : W[i];
    }
    extern "C" __global__ void getrow(const float* table, float* y, int row, int n, int wt) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) y[i] = wh_w(table, wt, (long long)row*n + i);
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

// ── Greedy decoding's argmax, on the device ─────────────────────────
//
// Whisper decodes greedily, and the only thing greedy decoding wants from a
// step is WHICH row of the logits is largest. Fetching the row to find out
// costs a 51865-float transfer and a 51865-iteration host loop — measured at
// 185 us for the fetch and conversion and another 180 for the scan, per token,
// against a 477 us decode step. Reduce it where it already lives and the answer
// is one integer.
//
// Ties go to the LOWER index, in the thread loop and in the reduction both,
// which is what the host scan's `>` gives — so the token stream is unchanged,
// not merely equivalent.
@ __wk_argmax → s {
    ^ `
    #define WH_AT 256
    extern "C" __global__ void argmaxk(const float* __restrict__ x, int n,
                                       int* __restrict__ out) {
        __shared__ float sv[WH_AT];
        __shared__ int   si[WH_AT];
        int t = threadIdx.x;
        float bv = -1e30f; int bi = 0;
        for (int i = t; i < n; i += WH_AT) {
            float v = x[i];
            if (v > bv) { bv = v; bi = i; }
        }
        sv[t] = bv; si[t] = bi;
        __syncthreads();
        for (int s = WH_AT/2; s > 0; s >>= 1) {
            if (t < s) {
                if (sv[t+s] > sv[t] || (sv[t+s] == sv[t] && si[t+s] < si[t])) {
                    sv[t] = sv[t+s]; si[t] = si[t+s];
                }
            }
            __syncthreads();
        }
        if (t == 0) out[0] = si[0];
    }`
}

@ wk_build Gpu g → WhKernels {
    : GpuKernel k1 ( gpu_compile g ( __wk_matvec ) `matvec` )
    : b want_warp == ( gpu_backend ) 0
    : GpuKernel k1w ? want_warp ( gpu_compile g ( __wk_matvec_w ) `matvec_w` ) @ GpuKernel { 0 0 }
    : GpuKernel k1t ? want_warp ( gpu_compile g ( __wk_matvec_t ) `matvec_t` ) @ GpuKernel { 0 0 }
    : GpuKernel k1m ? want_warp ( gpu_compile g ( __wk_matmul ) `matmul` ) @ GpuKernel { 0 0 }
    : ~ b warp & want_warp & & ( gpu_kernel_ok k1w ) ( gpu_kernel_ok k1t ) ( gpu_kernel_ok k1m )
    : GpuKernel k2 ( gpu_compile g ( __wk_layernorm ) `layernorm` )
    : GpuKernel k2b ? want_warp ( gpu_compile g ( __wk_layernorm_b ) `layernorm_b` ) @ GpuKernel { 0 0 }
    : GpuKernel k3 ( gpu_compile g ( __wk_gelu ) `gelu` )
    : GpuKernel k4 ( gpu_compile g ( __wk_conv1d ) `conv1d` )
    : GpuKernel k5f ? want_warp ( gpu_compile g ( __wk_attn_f ) `attn_f` ) @ GpuKernel { 0 0 }
    : GpuKernel k5d ? want_warp ( gpu_compile g ( __wk_attn_d ) `attn_d` ) @ GpuKernel { 0 0 }
    : GpuKernel k5m ? want_warp ( gpu_compile g ( __wk_attn_dm ) `attn_dm` ) @ GpuKernel { 0 0 }
    : GpuKernel k5 ( gpu_compile g ( __wk_attn_sc ) `attn_sc` )
    : GpuKernel k6 ( gpu_compile g ( __wk_attn_out ) `attn_out` )
    : GpuKernel k7 ( gpu_compile g ( __wk_addv ) `addv` )
    : GpuKernel k8 ( gpu_compile g ( __wk_addrow ) `addrow` )
    : GpuKernel k9 ( gpu_compile g ( __wk_scale ) `scale` )
    : GpuKernel k12 ( gpu_compile g ( __wk_cvt_f16 ) `cvt_f16` )
    : GpuKernel k13 ( gpu_compile g ( __wk_cvt_bf16 ) `cvt_bf16` )
    : GpuKernel k10 ( gpu_compile g ( __wk_getrow ) `getrow` )
    : GpuKernel k11 ( gpu_compile g ( __wk_setrow ) `setrow` )
    : GpuKernel k14 ( gpu_compile g ( __wk_argmax ) `argmaxk` )
    : b ok1 & & ( gpu_kernel_ok k1 ) ( gpu_kernel_ok k2 ) & ( gpu_kernel_ok k3 ) ( gpu_kernel_ok k4 )
    : b ok2 & & ( gpu_kernel_ok k5 ) ( gpu_kernel_ok k6 ) & ( gpu_kernel_ok k7 ) ( gpu_kernel_ok k8 )
    : b ok3 & ( gpu_kernel_ok k9 ) & ( gpu_kernel_ok k10 ) ( gpu_kernel_ok k11 )
    : b ok4 & & ( gpu_kernel_ok k12 ) ( gpu_kernel_ok k13 ) ( gpu_kernel_ok k14 )
    : b ok & & ok1 ok2 & ok3 ok4
    // the fused attentions are part of the warp path: if either failed to
    // compile, the composed one must run, and the scratch the caller sizes
    // from `warp` has to exist
    = warp & warp & ( gpu_kernel_ok k5f ) & ( gpu_kernel_ok k5d ) ( gpu_kernel_ok k5m )
    ^ @ WhKernels { k1 k1w k1t k1m warp k2 k2b k3 k4 k5f k5d k5m k5 k6 k7 k8 k9 k12 k13 k10 k11 k14 ok }
}

@ wk_free WhKernels ks → v {
    ( gpu_kernel_free . ks matvec )
    ? . ks warp {
        ( gpu_kernel_free . ks matvec_w )
        ( gpu_kernel_free . ks matvec_t )
        ( gpu_kernel_free . ks matmul )
        ( gpu_kernel_free . ks attn_f )
        ( gpu_kernel_free . ks attn_d )
        ( gpu_kernel_free . ks attn_dm )
        ( gpu_kernel_free . ks layernorm_b )
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
    ( gpu_kernel_free . ks argmaxk )
}

// ── launchers ───────────────────────────────────────────────────────

// y[batch][rows] = W[rows][cols] · x[batch][cols] + bias[rows]. `bd` may be 0.
// `wt` = 1 when W's elements are raw f16 halves (the checkpoint's own
// precision, kept on the device); 0 for f32. The kernels widen at the point
// of use — exactly, denormals included — so the arithmetic is f32 either way
// and the result is bit-identical; what changes is that the weight bytes on
// the device (and through the memory bus of a memory-bound matvec) are half.
@ wk_matvec WhKernels ks i wd i xd i bd i yd i rows i cols i batch i wt → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 rows ) )
    ( vec_push [i] a ( gpu_arg_i32 cols ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    ( vec_push [i] a ( gpu_arg_i32 wt ) )
    ? . ks warp {
        // Many positions at once (the encoder): amortise the weight matrix over
        // eight of them. One position (the decoder): there is nothing to
        // amortise, and the plain warp kernel is the right one.
        ? >= batch 64 {
            // a real GEMM shape: 64x64 output tiles through shared memory
            : i nbb / + batch 63 64
            : i nbr / + rows 63 64
            : i _r ( gpu_launch . ks matmul * nbb nbr 256 a )
        } {
            ? >= batch 8 {
                : i tiles / + batch 7 8
                : i threads * * rows tiles 32
                : i _r ( gpu_launch . ks matvec_t ( gpu_grid threads 128 ) 128 a )
            } {
                : i threads * * rows batch 32
                : i _r ( gpu_launch . ks matvec_w ( gpu_grid threads 128 ) 128 a )
            }
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
    ? . ks warp {
        : i _rb ( gpu_launch . ks layernorm_b batch 256 a )
    } {
        : i _r ( gpu_launch . ks layernorm ( gpu_grid batch 256 ) 256 a )
    }
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
    // The encoder: many queries, no mask, head_dim 64 — one fused kernel, no
    // score matrix. The decoder (one query at a time, causal) has nothing to
    // amortise and takes the two-kernel path.
    // One query — the decoder, every step of it. Its own fused kernel: no
    // score matrix, and the keys split across blocks so the work reaches more
    // than a handful of SMs. `scd` carries the per-chunk partials.
    ? & & . ks warp == hd 64 < nq 64 {
        : i lim ? != causal 0 nkey nkey
        : ~ i chunk 128
        : ~ i nchunk / + lim - chunk 1 chunk
        ? < nchunk 1 { = nchunk 1 } {}
        ? > nchunk 32 { = nchunk 32 = chunk / + lim 31 32 } {}
        : ( Vec i ) ad ( vec_new [i] )
        ( vec_push [i] ad ( gpu_arg_i64 qd ) )
        ( vec_push [i] ad ( gpu_arg_i64 kd ) )
        ( vec_push [i] ad ( gpu_arg_i64 vd ) )
        ( vec_push [i] ad ( gpu_arg_i64 scd ) )
        ( vec_push [i] ad ( gpu_arg_i32 nh ) )
        ( vec_push [i] ad ( gpu_arg_i32 hd ) )
        ( vec_push [i] ad ( gpu_arg_i32 nq ) )
        ( vec_push [i] ad ( gpu_arg_i32 nkey ) )
        ( vec_push [i] ad ( gpu_arg_f32 qscale ) )
        ( vec_push [i] ad ( gpu_arg_i32 causal ) )
        ( vec_push [i] ad ( gpu_arg_i32 chunk ) )
        ( vec_push [i] ad ( gpu_arg_i32 nchunk ) )
        : i _rd ( gpu_launch . ks attn_d * * nh nq nchunk 256 ad )
        ( vec_free [i] ad )
        : ( Vec i ) am ( vec_new [i] )
        ( vec_push [i] am ( gpu_arg_i64 scd ) )
        ( vec_push [i] am ( gpu_arg_i64 outd ) )
        ( vec_push [i] am ( gpu_arg_i32 nh ) )
        ( vec_push [i] am ( gpu_arg_i32 hd ) )
        ( vec_push [i] am ( gpu_arg_i32 nq ) )
        ( vec_push [i] am ( gpu_arg_i32 nchunk ) )
        : i _rm ( gpu_launch . ks attn_dm * nh nq 64 am )
        ( vec_free [i] am )
        ^ {}
    } {}
    ? & & & . ks warp == causal 0 == hd 64 >= nq 64 {
        : ( Vec i ) af ( vec_new [i] )
        ( vec_push [i] af ( gpu_arg_i64 qd ) )
        ( vec_push [i] af ( gpu_arg_i64 kd ) )
        ( vec_push [i] af ( gpu_arg_i64 vd ) )
        ( vec_push [i] af ( gpu_arg_i64 outd ) )
        ( vec_push [i] af ( gpu_arg_i32 nh ) )
        ( vec_push [i] af ( gpu_arg_i32 hd ) )
        ( vec_push [i] af ( gpu_arg_i32 nq ) )
        ( vec_push [i] af ( gpu_arg_i32 nkey ) )
        ( vec_push [i] af ( gpu_arg_f32 qscale ) )
        : i _rf ( gpu_launch . ks attn_f * nh ( gpu_grid nq 64 ) 64 af )
        ( vec_free [i] af )
        ^ {}
    } {}
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

@ wk_getrow WhKernels ks i table i yd i row i n i wt → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 table ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 row ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_i32 wt ) )
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
// The index of the largest logit, written as one int to `outd`.
@ wk_argmax WhKernels ks i xd i n i outd → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_i64 outd ) )
    : i _r ( gpu_launch . ks argmaxk 1 256 a )
    ( vec_free [i] a )
}

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
