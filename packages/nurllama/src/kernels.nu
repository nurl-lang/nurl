// packages/nurllama/src/kernels.nu — the LLM decode ops as GPU kernels.
//
// CUDA-C sources compiled once through packages/gpu (NVRTC on the CUDA
// backend; the SAME source runs on the CPU/OpenMP backend, so every
// kernel below deliberately avoids __shared__ / __syncthreads__ —
// each thread computes its output independently, exactly like the
// onnx op set). Decode-step shapes (one token at a time) keep the
// naive forms honest: the matvecs dominate and each row is one
// thread's serial dot product.
//
// Layout contracts (ggml row-major, ne0 fastest):
//   weight W[out,in]  → W[r*in + c], matvec y[r] = Σc W[r*in+c]·x[c]
//   K/V cache         → cache[t*(n_kv·hd) + kh*hd + d]
//   q/k activations   → x[h*hd + d]

$ `stdlib/core/vec.nu`
$ `deps/gpu/src/gpu.nu`

: LlmKernels {
    GpuKernel matvec
    GpuKernel mv_q4_0
    GpuKernel mv_q8_0
    GpuKernel mv_q5_0
    GpuKernel mv_q5_1
    GpuKernel mv_q4_k
    GpuKernel mv_q5_k
    GpuKernel mv_q6_k
    GpuKernel mv_f16
    GpuKernel w_f32
    GpuKernel w_q4_0
    GpuKernel w_q8_0
    GpuKernel w_q4_k
    GpuKernel w_q6_k
    GpuKernel w_q5_0
    GpuKernel w_q5_1
    GpuKernel w_q5_k
    b warp
    GpuKernel rmsnorm
    GpuKernel rope
    GpuKernel rope_neox
    GpuKernel attn
    GpuKernel attn_sc
    GpuKernel attn_out
    GpuKernel silumul
    GpuKernel gelumul
    GpuKernel scale
    GpuKernel addv
    GpuKernel addrow
    GpuKernel copyat
    GpuKernel axpy
    b ok
}

@ __lk_matvec → s {
    ^ `extern "C" __global__ void matvec(
        const float* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        const float* w = W + (long long)r*cols;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int c = 0; c < cols; ++c) acc += w[c]*xb[c];
        y[(long long)b*rows + r] = acc;
    }`
}

// Every thread recomputes the sum of squares — O(n²) total, but norms
// are dwarfed by the matvecs at decode shapes and this keeps the
// kernel valid on the block-serial CPU backend (no cross-thread sync).
// gemma's RMSNorm is documented as `x * inv * (1 + w)`, but the GGUF
// converter folds that +1 into the stored weights (every norm weight in a
// gemma GGUF is exactly the HF weight plus one — verified against the HF
// checkpoint). Adding it again here is a double count, so this kernel is the
// plain form for every architecture.
@ __lk_rmsnorm → s {
    ^ `extern "C" __global__ void rmsnorm(
        const float* x, const float* w, float* y, int n, float eps, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= n*batch) return;
        int b = idx / n, i = idx % n;
        const float* xb = x + (long long)b*n;
        float ss = 0.f;
        for (int j = 0; j < n; ++j) ss += xb[j]*xb[j];
        float inv = rsqrtf(ss/n + eps);
        y[(long long)b*n + i] = xb[i]*inv*w[i];
    }`
}

// Rotary embedding, ggml NORM style (llama): adjacent pairs (2j, 2j+1)
// of the first rd dims of every head rotate by pos·base^(-2j/rd).
@ __lk_rope → s {
    ^ `extern "C" __global__ void rope(
        float* x, int nh, int hd, int rd, int pos0, float base, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int pairs = rd/2;
        if (idx >= nh*pairs*batch) return;
        int b = idx / (nh*pairs), p = idx % (nh*pairs);
        x += (long long)b*nh*hd;
        int pos = pos0 + b;
        {
            int h = p / pairs, j = p % pairs;
            float theta = pos * powf(base, -2.f*j/rd);
            float c = cosf(theta), s = sinf(theta);
            float* v = x + h*hd + 2*j;
            float a = v[0], b = v[1];
            v[0] = a*c - b*s;
            v[1] = a*s + b*c;
        }
    }`
}

// NEOX-style rotary (qwen2, phi, …): the rotated pairs are (j, j + rd/2)
// — the two halves of the head's rotary span — not the adjacent (2j,
// 2j+1) of the llama/NORM layout. Feeding a model the wrong variant
// still runs and still produces fluent-looking garbage, which is why
// the architecture selects it rather than a heuristic.
@ __lk_rope_neox → s {
    ^ `extern "C" __global__ void rope_neox(
        float* x, int nh, int hd, int rd, int pos0, float base, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int pairs = rd/2;
        if (idx >= nh*pairs*batch) return;
        int b = idx / (nh*pairs), p = idx % (nh*pairs);
        x += (long long)b*nh*hd;
        int pos = pos0 + b;
        {
            int h = p / pairs, j = p % pairs;
            float theta = pos * powf(base, -2.f*j/rd);
            float c = cosf(theta), s = sinf(theta);
            float* v = x + h*hd;
            float a = v[j], b = v[j + pairs];
            v[j]         = a*c - b*s;
            v[j + pairs] = a*s + b*c;
        }
    }`
}

// Causal attention for ONE decode position: head h attends over cache
// rows 0..pos. One thread per head — serial softmax keeps it exact and
// sync-free; npos·hd·2 flops per head is noise next to the matvecs.
// GQA: query head h reads kv head h/(nh/nkv).
@ __lk_attn → s {
    ^ `extern "C" __global__ void attn(
        const float* q, const float* K, const float* V, float* out,
        float* scores, int nh, int nkv, int hd, int npos0, int batch, int maxpos) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx < nh*batch) {
            int b = idx / nh, h = idx % nh;
            // batch element b is at absolute position (npos0-1)+b, so it
            // attends over npos0+b cache rows — its own causal window
            int npos = npos0 + b;
            q   += (long long)b*nh*hd;
            out += (long long)b*nh*hd;
            int kvdim = nkv*hd;
            int kh = h / (nh/nkv);
            const float* qh = q + h*hd;
            float* sc = scores + (long long)idx*maxpos;
            float scale = rsqrtf((float)hd);
            float mx = -1e30f;
            for (int t = 0; t < npos; ++t) {
                const float* kr = K + (long long)t*kvdim + kh*hd;
                float d = 0.f;
                for (int j = 0; j < hd; ++j) d += qh[j]*kr[j];
                d *= scale;
                sc[t] = d;
                if (d > mx) mx = d;
            }
            float sum = 0.f;
            for (int t = 0; t < npos; ++t) { sc[t] = expf(sc[t]-mx); sum += sc[t]; }
            float invs = 1.f/sum;
            for (int j = 0; j < hd; ++j) {
                float acc = 0.f;
                for (int t = 0; t < npos; ++t)
                    acc += sc[t] * V[(long long)t*kvdim + kh*hd + j];
                out[h*hd + j] = acc*invs;
            }
        }
    }`
}

// ── Attention, two passes ───────────────────────────────────────────
//
// The single-kernel form gives ONE THREAD a whole head: with 14 heads a
// decode step ran 14 threads on a 16 000-core GPU, each looping over the
// whole cache. Splitting the work parallelises it by three orders of
// magnitude — and needs no cross-thread communication, so it stays on
// the portable path (both backends).
//
//   pass 1: one thread per (position, head, cache row) → the raw score
//   pass 2: one thread per (position, head, head-dim) → softmax over the
//           row's scores (each thread folds them serially — npos is small)
//           and the value-weighted sum
// `qscale` is the query scale (1/sqrt(head_dim) for llama; gemma states it
// separately as query_pre_attn_scalar). `window` > 0 is a sliding attention
// window: a key older than `window` positions is not attended to at all —
// gemma3 does this on five of every six layers. `window` = 0 is full causal
// attention. attn_sc and attn_out compute the same lower bound `lo`, so the
// masked score slots are never read rather than being written with -inf.
// `causal` — 1: batch element b attends its own causal window
// (npos0 + b cache rows, autoregressive decode). 0: every element
// attends the SAME fixed range npos0 (block-diffusion: a query in the
// active block sees the whole window, later positions included).
@ __lk_attn_sc → s {
    ^ `extern "C" __global__ void attn_sc(
        const float* q, const float* K, float* scores,
        int nh, int nkv, int hd, int npos0, int batch, int maxpos,
        float qscale, int window, int causal) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int total = nh*batch*maxpos;
        if (idx >= total) return;
        int t  = idx % maxpos;
        int hb = idx / maxpos;
        int h  = hb % nh, b = hb / nh;
        int npos = causal ? npos0 + b : npos0;
        if (t >= npos) return;
        int lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
        if (t < lo) return;
        int kvdim = nkv*hd;
        int kh = h / (nh/nkv);
        const float* qh = q + (long long)b*nh*hd + h*hd;
        const float* kr = K + (long long)t*kvdim + kh*hd;
        float d = 0.f;
        for (int j = 0; j < hd; ++j) d += qh[j]*kr[j];
        scores[(long long)hb*maxpos + t] = d * qscale;
    }`
}

@ __lk_attn_out → s {
    ^ `extern "C" __global__ void attn_out(
        const float* V, const float* scores, float* out,
        int nh, int nkv, int hd, int npos0, int batch, int maxpos, int window,
        int causal) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= nh*batch*hd) return;
        int d  = idx % hd;
        int hb = idx / hd;
        int h  = hb % nh, b = hb / nh;
        int npos = causal ? npos0 + b : npos0;
        int lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
        int kvdim = nkv*hd;
        int kh = h / (nh/nkv);
        const float* sc = scores + (long long)hb*maxpos;
        float mx = -1e30f;
        for (int t = lo; t < npos; ++t) if (sc[t] > mx) mx = sc[t];
        float sum = 0.f, acc = 0.f;
        for (int t = lo; t < npos; ++t) {
            float p = expf(sc[t] - mx);
            sum += p;
            acc += p * V[(long long)t*kvdim + kh*hd + d];
        }
        out[(long long)b*nh*hd + h*hd + d] = acc / sum;
    }`
}

// y ← y + a·x (see lk_axpy).
@ __lk_axpy → s {
    ^ `extern "C" __global__ void axpy(float* y, const float* x, float a, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) y[i] += a * x[i];
    }`
}

// SwiGLU gate: g = silu(g) · u, in place on g.
@ __lk_silumul → s {
    ^ `extern "C" __global__ void silumul(float* g, const float* u, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) {
            float v = g[i];
            g[i] = (v / (1.f + expf(-v))) * u[i];
        }
    }`
}

// Residual add, in place: a += b.
// GeGLU — gemma's FFN gate. The tanh approximation is what gemma was
// trained with (gelu_pytorch_tanh), so the exact erf form would be the
// wrong function here, not a more accurate one.
@ __lk_gelumul → s {
    ^ `extern "C" __global__ void gelumul(float* g, const float* u, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) {
            float v = g[i];
            float c = 0.7978845608028654f * (v + 0.044715f*v*v*v);
            g[i] = (0.5f*v*(1.f + tanhf(c))) * u[i];
        }
    }`
}

// gemma scales the embedding row by sqrt(n_embd) before the first block.
@ __lk_scale → s {
    ^ `extern "C" __global__ void scale(float* x, float s, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) x[i] *= s;
    }`
}

@ __lk_addv → s {
    ^ `extern "C" __global__ void addv(float* a, const float* b, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) a[i] += b[i];
    }`
}

// Broadcast add: every row of a batch gets the same vector (a bias).
@ __lk_addrow → s {
    ^ `extern "C" __global__ void addrow(float* a, const float* v, int n, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx < n*batch) a[idx] += v[idx % n];
    }`
}

// Element copy into an offset — appends k/v rows into the cache.
@ __lk_copyat → s {
    ^ `extern "C" __global__ void copyat(float* dst, const float* src, int off, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) dst[off + i] = src[i];
    }`
}

// ── Quantised matvec: dequantise IN the matmul ──────────────────────
//
// The weights stay on the device in their GGUF block form — a Q4_K
// row is 4.5 bits/weight instead of 32, so a model needs ~7× less
// device memory than the f32 expansion and the matvec reads ~7× fewer
// bytes (these kernels are memory-bound, so that is also the speed).
// Each thread owns one output row and walks its blocks, decoding each
// on the fly into registers. Block layouts are ggml's, byte for byte —
// the same ones packages/gguf's host dequant decodes, which is the
// bit-exact oracle these kernels are verified against.

@ __lk_f16_dev → s {
    ^ `
    // IEEE half → float, integer bit transport. Deliberately NOT
    // __half2float: that needs cuda_fp16.h, which NVRTC does not have
    // by default and the CPU backend's shim has no notion of. A union
    // and shifts compile identically on both backends.
    __device__ static inline float nl_f16(const unsigned char* p) {
        unsigned int h = (unsigned int)p[0] | ((unsigned int)p[1] << 8);
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
        union { unsigned int u; float f; } cv;
        cv.u = bits;
        return cv.f;
    }
    `
}

@ __lk_mv_q4_0 → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q4_0(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 18;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*18;
            float d = nl_f16(bp);
            const float* xb = x + blk*32;
            for (int j = 0; j < 16; ++j) {
                unsigned char q = bp[2+j];
                acc += d * ((float)((q & 0xF) - 8)) * xb[j];
                acc += d * ((float)((q >> 4)  - 8)) * xb[j+16];
            }
        }
        y[r] = acc;
    }` )
}

@ __lk_mv_q8_0 → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q8_0(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 34;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*34;
            float d = nl_f16(bp);
            const signed char* q = (const signed char*)(bp + 2);
            const float* xb = x + blk*32;
            float sub = 0.f;
            for (int j = 0; j < 32; ++j) sub += (float)q[j] * xb[j];
            acc += d * sub;
        }
        y[r] = acc;
    }` )
}

// Q4_K: 144-byte super-block of 256 — d, dmin (f16), 12 packed 6-bit
// scale/min pairs, 128 nibble bytes. Sub-block s takes its 32 values
// from the low (even s) or high (odd s) nibbles of bytes [s/2*32 …].
@ __lk_mv_q4_k → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q4_k(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 144;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*144;
            float d    = nl_f16(bp);
            float dmin = nl_f16(bp + 2);
            const unsigned char* sc = bp + 4;
            const unsigned char* qs = bp + 16;
            const float* xb = x + blk*256;
            for (int s = 0; s < 8; ++s) {
                int sV, mV;
                if (s < 4) { sV = sc[s] & 63; mV = sc[s+4] & 63; }
                else {
                    sV = (sc[s+4] & 0xF) | ((sc[s-4] >> 6) << 4);
                    mV = (sc[s+4] >>  4) | ((sc[s]   >> 6) << 4);
                }
                float d1 = d * sV, m1 = dmin * mV;
                const unsigned char* qb = qs + (s/2)*32;
                const float* xs = xb + s*32;
                int hi = s & 1;
                float sub = 0.f, msum = 0.f;
                for (int l = 0; l < 32; ++l) {
                    int q = hi ? (qb[l] >> 4) : (qb[l] & 0xF);
                    sub  += (float)q * xs[l];
                    msum += xs[l];
                }
                acc += d1 * sub - m1 * msum;
            }
        }
        y[r] = acc;
    }` )
}

// Q6_K: 210-byte super-block of 256 — 128 low-nibble bytes, 64 bytes
// of upper 2 bits, 16 int8 scales, f16 d. Sixteen 16-element groups.
@ __lk_mv_q6_k → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q6_k(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 210;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*210;
            const unsigned char* ql = bp;
            const unsigned char* qh = bp + 128;
            const signed char*   sc = (const signed char*)(bp + 192);
            float d = nl_f16(bp + 208);
            const float* xb = x + blk*256;
            for (int n = 0; n < 2; ++n) {
                const unsigned char* ql0 = ql + n*64;
                const unsigned char* qh0 = qh + n*32;
                const signed char*   sc0 = sc + n*8;
                const float* xn = xb + n*128;
                for (int l = 0; l < 32; ++l) {
                    int is = l/16;
                    unsigned char h = qh0[l];
                    int b1 = ql0[l], b2 = ql0[l+32];
                    int q1 = ((b1 & 0xF) | (( h       & 3) << 4)) - 32;
                    int q2 = ((b2 & 0xF) | (((h >> 2) & 3) << 4)) - 32;
                    int q3 = ((b1 >>  4) | (((h >> 4) & 3) << 4)) - 32;
                    int q4 = ((b2 >>  4) | (((h >> 6) & 3) << 4)) - 32;
                    acc += d * (float)sc0[is    ] * (float)q1 * xn[l];
                    acc += d * (float)sc0[is + 2] * (float)q2 * xn[l + 32];
                    acc += d * (float)sc0[is + 4] * (float)q3 * xn[l + 64];
                    acc += d * (float)sc0[is + 6] * (float)q4 * xn[l + 96];
                }
            }
        }
        y[r] = acc;
    }` )
}

@ __lk_mv_q5_0 → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q5_0(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 22;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*22;
            float d = nl_f16(bp);
            unsigned int qh = (unsigned int)bp[2] | ((unsigned int)bp[3] << 8)
                            | ((unsigned int)bp[4] << 16) | ((unsigned int)bp[5] << 24);
            const unsigned char* qs = bp + 6;
            const float* xb = x + blk*32;
            float sub = 0.f;
            for (int j = 0; j < 16; ++j) {
                int h0 = ((qh >> j) & 1u) << 4;
                int h1 = ((qh >> (j + 16)) & 1u) << 4;
                sub += (float)(((qs[j] & 0xF) | h0) - 16) * xb[j];
                sub += (float)(((qs[j] >> 4)  | h1) - 16) * xb[j + 16];
            }
            acc += d * sub;
        }
        y[r] = acc;
    }` )
}

@ __lk_mv_q5_1 → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q5_1(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 24;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*24;
            float d = nl_f16(bp);
            float m = nl_f16(bp + 2);
            unsigned int qh = (unsigned int)bp[4] | ((unsigned int)bp[5] << 8)
                            | ((unsigned int)bp[6] << 16) | ((unsigned int)bp[7] << 24);
            const unsigned char* qs = bp + 8;
            const float* xb = x + blk*32;
            float sub = 0.f, msum = 0.f;
            for (int j = 0; j < 16; ++j) {
                int h0 = ((qh >> j) & 1u) << 4;
                int h1 = ((qh >> (j + 16)) & 1u) << 4;
                sub  += (float)((qs[j] & 0xF) | h0) * xb[j];
                sub  += (float)((qs[j] >> 4)  | h1) * xb[j + 16];
                msum += xb[j] + xb[j + 16];
            }
            acc += d * sub + m * msum;
        }
        y[r] = acc;
    }` )
}

// Q5_K: 176-byte super-block of 256 — d, dmin (f16), 12 packed scale/
// min bytes, 32 bytes carrying each value's 5th bit, 128 nibble bytes.
@ __lk_mv_q5_k → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_q5_k(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 176;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*176;
            float d    = nl_f16(bp);
            float dmin = nl_f16(bp + 2);
            const unsigned char* sc = bp + 4;
            const unsigned char* qh = bp + 16;
            const unsigned char* qs = bp + 48;
            const float* xb = x + blk*256;
            for (int s = 0; s < 8; ++s) {
                int sV, mV;
                if (s < 4) { sV = sc[s] & 63; mV = sc[s+4] & 63; }
                else {
                    sV = (sc[s+4] & 0xF) | ((sc[s-4] >> 6) << 4);
                    mV = (sc[s+4] >>  4) | ((sc[s]   >> 6) << 4);
                }
                float d1 = d * sV, m1 = dmin * mV;
                const unsigned char* qb = qs + (s/2)*32;
                const float* xs = xb + s*32;
                int hi = s & 1;
                float sub = 0.f, msum = 0.f;
                for (int l = 0; l < 32; ++l) {
                    int q = hi ? (qb[l] >> 4) : (qb[l] & 0xF);
                    int hbit = (qh[l] >> s) & 1;
                    sub  += (float)(q + (hbit << 4)) * xs[l];
                    msum += xs[l];
                }
                acc += d1 * sub - m1 * msum;
            }
        }
        y[r] = acc;
    }` )
}

@ __lk_mv_f16 → s {
    ^ ( nurl_str_cat ( __lk_f16_dev ) `extern "C" __global__ void mv_f16(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= rows*batch) return;
        int b = idx / rows, r = idx % rows;
        x += (long long)b*cols;
        y += (long long)b*rows;
        const unsigned char* w = W + (long long)r*cols*2;
        float acc = 0.f;
        for (int c = 0; c < cols; ++c) acc += nl_f16(w + c*2) * x[c];
        y[r] = acc;
    }` )
}

// ── CUDA-only: one WARP per output row ──────────────────────────────
//
// The portable kernels above give one THREAD a whole row: lane-adjacent
// threads then read addresses a full row apart, so a warp's memory
// requests scatter across the weight matrix and the matvec — which is
// memory-bound — runs at a fraction of the device's bandwidth.
//
// These variants give one WARP a row: the 32 lanes stride through the
// row together (lane l takes block l, l+32, …), so each warp request is
// a contiguous span, and a shuffle reduction folds the lane partials.
// They use __shfl_down_sync, which exists only on CUDA — the CPU
// backend keeps the portable kernels, and lk_build picks per backend.
// Both paths are verified to produce the same text.

@ __lk_warp_red → s {
    ^ `
    __device__ static inline float nl_warp_sum(float v) {
        for (int off = 16; off > 0; off >>= 1) v += __shfl_down_sync(0xffffffffu, v, off);
        return v;
    }
    #define NL_WARP_PROLOGUE(ROWS, BATCH)                       \
        int gid  = blockIdx.x*blockDim.x + threadIdx.x;         \
        int warp = gid >> 5, lane = gid & 31;                   \
        if (warp >= (ROWS)*(BATCH)) return;                     \
        int b = warp / (ROWS), r = warp % (ROWS);
    `
}

@ __lk_mv_f32_w → s {
    ^ ( nurl_str_cat ( __lk_warp_red ) `extern "C" __global__ void mv_f32_w(
        const float* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        const float* w = W + (long long)r*cols;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int c = lane; c < cols; c += 32) acc += w[c]*xb[c];
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q4_0_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q4_0_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 18;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int blk = lane; blk < nb; blk += 32) {
            const unsigned char* bp = w + blk*18;
            float d = nl_f16(bp);
            const float* xs = xb + blk*32;
            for (int j = 0; j < 16; ++j) {
                unsigned char q = bp[2+j];
                acc += d * ((float)((q & 0xF) - 8)) * xs[j];
                acc += d * ((float)((q >> 4)  - 8)) * xs[j+16];
            }
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q8_0_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q8_0_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 34;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int blk = lane; blk < nb; blk += 32) {
            const unsigned char* bp = w + blk*34;
            float d = nl_f16(bp);
            const signed char* q = (const signed char*)(bp + 2);
            const float* xs = xb + blk*32;
            float sub = 0.f;
            for (int j = 0; j < 32; ++j) sub += (float)q[j] * xs[j];
            acc += d * sub;
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q4_k_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q4_k_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 144;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        // The whole warp walks the row's blocks TOGETHER, and the 32 lanes
        // split each block's quants: lane l takes byte l of each 32-byte
        // nibble group, so one warp load is 32 contiguous bytes (and the
        // matching x load is 32 contiguous floats). Giving each lane its own
        // 144-byte block instead — the obvious partition — makes every warp
        // load touch 32 separate cache lines.
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*144;
            float d    = nl_f16(bp);
            float dmin = nl_f16(bp + 2);
            const unsigned char* sc = bp + 4;
            const unsigned char* qs = bp + 16;
            const float* xblk = xb + blk*256;
            for (int j = 0; j < 4; ++j) {
                unsigned char q = qs[j*32 + lane];
                for (int t = 0; t < 2; ++t) {
                    int sb = 2*j + t;               // sub-block: low nibble, then high
                    int sV, mV;
                    if (sb < 4) { sV = sc[sb] & 63; mV = sc[sb+4] & 63; }
                    else {
                        sV = (sc[sb+4] & 0xF) | ((sc[sb-4] >> 6) << 4);
                        mV = (sc[sb+4] >>  4) | ((sc[sb]   >> 6) << 4);
                    }
                    float xv = xblk[sb*32 + lane];
                    int   qq = t ? (q >> 4) : (q & 0xF);
                    acc += (d * sV) * ((float)qq * xv) - (dmin * mV) * xv;
                }
            }
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q6_k_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q6_k_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 210;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int blk = lane; blk < nb; blk += 32) {
            const unsigned char* bp = w + blk*210;
            const unsigned char* ql = bp;
            const unsigned char* qh = bp + 128;
            const signed char*   sc = (const signed char*)(bp + 192);
            float d = nl_f16(bp + 208);
            const float* xblk = xb + blk*256;
            for (int n = 0; n < 2; ++n) {
                const unsigned char* ql0 = ql + n*64;
                const unsigned char* qh0 = qh + n*32;
                const signed char*   sc0 = sc + n*8;
                const float* xn = xblk + n*128;
                for (int l = 0; l < 32; ++l) {
                    int is = l/16;
                    unsigned char h = qh0[l];
                    int b1 = ql0[l], b2 = ql0[l+32];
                    int q1 = ((b1 & 0xF) | (( h       & 3) << 4)) - 32;
                    int q2 = ((b2 & 0xF) | (((h >> 2) & 3) << 4)) - 32;
                    int q3 = ((b1 >>  4) | (((h >> 4) & 3) << 4)) - 32;
                    int q4 = ((b2 >>  4) | (((h >> 6) & 3) << 4)) - 32;
                    acc += d * (float)sc0[is    ] * (float)q1 * xn[l];
                    acc += d * (float)sc0[is + 2] * (float)q2 * xn[l + 32];
                    acc += d * (float)sc0[is + 4] * (float)q3 * xn[l + 64];
                    acc += d * (float)sc0[is + 6] * (float)q4 * xn[l + 96];
                }
            }
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

// Q5_0 / Q5_1 / Q5_K warp variants. The 5-bit quants were the last matvecs
// without one — and a Q5_0-heavy model (which is what most llama.cpp
// "q4_k_m" files actually are: 166 of this one's 272 tensors) therefore ran
// entirely on the one-thread-per-row kernel, where the 32 lanes of a warp
// read 32 rows at once, i.e. 32 unrelated cache lines per load. Same warp
// split as the K-quants: the warp walks blocks together, lane l takes byte l.

@ __lk_mv_q5_0_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q5_0_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 22;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        // 32 lanes, 16 bytes of quants per block: lanes 0..15 take the block's
        // bytes, lanes 16..31 take the next block's — two blocks per step.
        for (int blk = lane >> 4; blk < nb; blk += 2) {
            const unsigned char* bp = w + blk*22;
            int j = lane & 15;
            float d = nl_f16(bp);
            unsigned int qh = (unsigned int)bp[2] | ((unsigned int)bp[3] << 8)
                            | ((unsigned int)bp[4] << 16) | ((unsigned int)bp[5] << 24);
            unsigned char q = bp[6 + j];
            const float* xs = xb + blk*32;
            int h0 = ((qh >> j) & 1u) << 4;
            int h1 = ((qh >> (j + 16)) & 1u) << 4;
            acc += d * (float)(((q & 0xF) | h0) - 16) * xs[j];
            acc += d * (float)(((q >> 4)  | h1) - 16) * xs[j + 16];
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q5_1_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q5_1_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 32;
        const unsigned char* w = W + (long long)r * nb * 24;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int blk = lane >> 4; blk < nb; blk += 2) {
            const unsigned char* bp = w + blk*24;
            int j = lane & 15;
            float d = nl_f16(bp);
            float m = nl_f16(bp + 2);
            unsigned int qh = (unsigned int)bp[4] | ((unsigned int)bp[5] << 8)
                            | ((unsigned int)bp[6] << 16) | ((unsigned int)bp[7] << 24);
            unsigned char q = bp[8 + j];
            const float* xs = xb + blk*32;
            int h0 = ((qh >> j) & 1u) << 4;
            int h1 = ((qh >> (j + 16)) & 1u) << 4;
            acc += (d * (float)((q & 0xF) | h0) + m) * xs[j];
            acc += (d * (float)((q >> 4)  | h1) + m) * xs[j + 16];
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ __lk_mv_q5_k_w → s {
    ^ ( nurl_str_cat ( nurl_str_cat ( __lk_warp_red ) ( __lk_f16_dev ) ) `extern "C" __global__ void mv_q5_k_w(
        const unsigned char* __restrict__ W, const float* __restrict__ x, float* __restrict__ y, int rows, int cols, int batch) {
        NL_WARP_PROLOGUE(rows, batch)
        int nb = cols / 256;
        const unsigned char* w = W + (long long)r * nb * 176;
        const float* xb = x + (long long)b*cols;
        float acc = 0.f;
        for (int blk = 0; blk < nb; ++blk) {
            const unsigned char* bp = w + blk*176;
            float d    = nl_f16(bp);
            float dmin = nl_f16(bp + 2);
            const unsigned char* sc = bp + 4;
            const unsigned char* qh = bp + 16;
            const unsigned char* qs = bp + 48;
            const float* xblk = xb + blk*256;
            unsigned char hbits = qh[lane];
            for (int j = 0; j < 4; ++j) {
                unsigned char q = qs[j*32 + lane];
                for (int t = 0; t < 2; ++t) {
                    int sb = 2*j + t;
                    int sV, mV;
                    if (sb < 4) { sV = sc[sb] & 63; mV = sc[sb+4] & 63; }
                    else {
                        sV = (sc[sb+4] & 0xF) | ((sc[sb-4] >> 6) << 4);
                        mV = (sc[sb+4] >>  4) | ((sc[sb]   >> 6) << 4);
                    }
                    float xv = xblk[sb*32 + lane];
                    int qq = (t ? (q >> 4) : (q & 0xF)) | (((hbits >> sb) & 1u) << 4);
                    acc += (d * sV) * ((float)qq * xv) - (dmin * mV) * xv;
                }
            }
        }
        acc = nl_warp_sum(acc);
        if (lane == 0) y[(long long)b*rows + r] = acc;
    }` )
}

@ lk_build Gpu g → LlmKernels {
    : GpuKernel k1 ( gpu_compile g ( __lk_matvec ) `matvec` )
    : GpuKernel k2 ( gpu_compile g ( __lk_rmsnorm ) `rmsnorm` )
    : GpuKernel k3 ( gpu_compile g ( __lk_rope ) `rope` )
    : GpuKernel k3n ( gpu_compile g ( __lk_rope_neox ) `rope_neox` )
    : GpuKernel k4 ( gpu_compile g ( __lk_attn ) `attn` )
    : GpuKernel k4a ( gpu_compile g ( __lk_attn_sc ) `attn_sc` )
    : GpuKernel k4b ( gpu_compile g ( __lk_attn_out ) `attn_out` )
    : GpuKernel k5 ( gpu_compile g ( __lk_silumul ) `silumul` )
    : GpuKernel k5g ( gpu_compile g ( __lk_gelumul ) `gelumul` )
    : GpuKernel k5s ( gpu_compile g ( __lk_scale ) `scale` )
    : GpuKernel k6 ( gpu_compile g ( __lk_addv ) `addv` )
    : GpuKernel k6b ( gpu_compile g ( __lk_addrow ) `addrow` )
    : GpuKernel k7 ( gpu_compile g ( __lk_copyat ) `copyat` )
    : GpuKernel k8 ( gpu_compile g ( __lk_axpy ) `axpy` )
    : GpuKernel q1 ( gpu_compile g ( __lk_mv_q4_0 ) `mv_q4_0` )
    : GpuKernel q2 ( gpu_compile g ( __lk_mv_q8_0 ) `mv_q8_0` )
    : GpuKernel q3 ( gpu_compile g ( __lk_mv_q4_k ) `mv_q4_k` )
    : GpuKernel q4 ( gpu_compile g ( __lk_mv_q6_k ) `mv_q6_k` )
    : GpuKernel q5 ( gpu_compile g ( __lk_mv_f16 ) `mv_f16` )
    : GpuKernel q6 ( gpu_compile g ( __lk_mv_q5_0 ) `mv_q5_0` )
    : GpuKernel q7 ( gpu_compile g ( __lk_mv_q5_1 ) `mv_q5_1` )
    : GpuKernel q8 ( gpu_compile g ( __lk_mv_q5_k ) `mv_q5_k` )
    : b ok0 & & & ( gpu_kernel_ok k1 ) ( gpu_kernel_ok k2 )
    & & & ( gpu_kernel_ok k3 ) ( gpu_kernel_ok k4 ) ( gpu_kernel_ok k4a ) ( gpu_kernel_ok k4b )
    & & ( gpu_kernel_ok k5 ) ( gpu_kernel_ok k6 ) ( gpu_kernel_ok k7 )
    : b ok1 & & ( gpu_kernel_ok q1 ) ( gpu_kernel_ok q2 )
    & & ( gpu_kernel_ok q3 ) ( gpu_kernel_ok q4 ) ( gpu_kernel_ok q5 )
    : b ok & & & & & ok0 ( gpu_kernel_ok k3n ) ( gpu_kernel_ok k6b ) ( gpu_kernel_ok k8 )
    & ( gpu_kernel_ok k5g ) ( gpu_kernel_ok k5s ) & ok1 & & ( gpu_kernel_ok q6 ) ( gpu_kernel_ok q7 ) ( gpu_kernel_ok q8 )
    // The warp-per-row matvecs use __shfl_down_sync — CUDA only. On any
    // other backend the portable kernels above stay in charge, and the
    // flag below turns the dispatch off.
    : b want_warp == ( gpu_backend ) 0
    : GpuKernel w1 ? want_warp ( gpu_compile g ( __lk_mv_f32_w ) `mv_f32_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w2 ? want_warp ( gpu_compile g ( __lk_mv_q4_0_w ) `mv_q4_0_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w3 ? want_warp ( gpu_compile g ( __lk_mv_q8_0_w ) `mv_q8_0_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w4 ? want_warp ( gpu_compile g ( __lk_mv_q4_k_w ) `mv_q4_k_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w5 ? want_warp ( gpu_compile g ( __lk_mv_q6_k_w ) `mv_q6_k_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w6 ? want_warp ( gpu_compile g ( __lk_mv_q5_0_w ) `mv_q5_0_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w7 ? want_warp ( gpu_compile g ( __lk_mv_q5_1_w ) `mv_q5_1_w` ) @ GpuKernel { 0 0 }
    : GpuKernel w8 ? want_warp ( gpu_compile g ( __lk_mv_q5_k_w ) `mv_q5_k_w` ) @ GpuKernel { 0 0 }
    : b warp & want_warp
    & & & ( gpu_kernel_ok w1 ) ( gpu_kernel_ok w2 ) & ( gpu_kernel_ok w3 ) ( gpu_kernel_ok w4 )
    & & ( gpu_kernel_ok w5 ) ( gpu_kernel_ok w6 ) & ( gpu_kernel_ok w7 ) ( gpu_kernel_ok w8 )
    ^ @ LlmKernels { k1 q1 q2 q6 q7 q3 q8 q4 q5 w1 w2 w3 w4 w5 w6 w7 w8 warp k2 k3 k3n k4 k4a k4b k5 k5g k5s k6 k6b k7 k8 ok }
}

@ lk_free LlmKernels ks → v {
    ( gpu_kernel_free . ks matvec )
    ( gpu_kernel_free . ks mv_q4_0 )
    ( gpu_kernel_free . ks mv_q8_0 )
    ( gpu_kernel_free . ks mv_q5_0 )
    ( gpu_kernel_free . ks mv_q5_1 )
    ( gpu_kernel_free . ks mv_q4_k )
    ( gpu_kernel_free . ks mv_q5_k )
    ( gpu_kernel_free . ks mv_q6_k )
    ( gpu_kernel_free . ks mv_f16 )
    ? . ks warp {
        ( gpu_kernel_free . ks w_f32 )
        ( gpu_kernel_free . ks w_q4_0 )
        ( gpu_kernel_free . ks w_q8_0 )
        ( gpu_kernel_free . ks w_q4_k )
        ( gpu_kernel_free . ks w_q6_k )
        ( gpu_kernel_free . ks w_q5_0 )
        ( gpu_kernel_free . ks w_q5_1 )
        ( gpu_kernel_free . ks w_q5_k )
    } {}
    ( gpu_kernel_free . ks rmsnorm )
    ( gpu_kernel_free . ks rope )
    ( gpu_kernel_free . ks rope_neox )
    ( gpu_kernel_free . ks attn )
    ( gpu_kernel_free . ks attn_sc )
    ( gpu_kernel_free . ks attn_out )
    ( gpu_kernel_free . ks silumul )
    ( gpu_kernel_free . ks gelumul )
    ( gpu_kernel_free . ks scale )
    ( gpu_kernel_free . ks addv )
    ( gpu_kernel_free . ks addrow )
    ( gpu_kernel_free . ks copyat )
    ( gpu_kernel_free . ks axpy )
}

// ── launch wrappers (raw device pointers, onnx op idiom) ────────────

@ lk_matvec LlmKernels ks i wd i xd i yd i rows i cols i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 rows ) )
    ( vec_push [i] a ( gpu_arg_i32 cols ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i _r ( gpu_launch . ks matvec ( gpu_grid * rows batch 256 ) 256 a )
    ( vec_free [i] a )
}

// Quantised matvec dispatch: `gt` is the ggml tensor type of W.
// Returns F when the type has no device kernel (the caller then falls
// back to the f32 path — correctness first, always).
@ lk_matvec_q LlmKernels ks i gt i wd i xd i yd i rows i cols i batch → b {
    : ~ i which -1
    ? == gt 0 { = which 0 } {}
    ? == gt 1 { = which 5 } {}
    ? == gt 2 { = which 1 } {}
    ? == gt 8 { = which 2 } {}
    ? == gt 12 { = which 3 } {}
    ? == gt 14 { = which 4 } {}
    ? == gt 6 { = which 6 } {}
    ? == gt 7 { = which 7 } {}
    ? == gt 13 { = which 8 } {}
    ? < which 0 { ^ F } {}
    // warp-per-row variants (CUDA): f32, Q4_0, Q8_0, Q4_K, Q6_K, Q5_0, Q5_1, Q5_K
    ? & . ks warp | | | | | | | == which 0 == which 1 == which 2 == which 3 == which 4
    == which 6 == which 7 == which 8 {
        : ( Vec i ) wa ( vec_new [i] )
        ( vec_push [i] wa ( gpu_arg_i64 wd ) )
        ( vec_push [i] wa ( gpu_arg_i64 xd ) )
        ( vec_push [i] wa ( gpu_arg_i64 yd ) )
        ( vec_push [i] wa ( gpu_arg_i32 rows ) )
        ( vec_push [i] wa ( gpu_arg_i32 cols ) )
        ( vec_push [i] wa ( gpu_arg_i32 batch ) )
        // 128 threads = 4 warps per block, one row each
        : i threads * * rows batch 32
        : i wg ( gpu_grid threads 128 )
        ? == which 0 { : i _r ( gpu_launch . ks w_f32 wg 128 wa ) } {}
        ? == which 1 { : i _r ( gpu_launch . ks w_q4_0 wg 128 wa ) } {}
        ? == which 2 { : i _r ( gpu_launch . ks w_q8_0 wg 128 wa ) } {}
        ? == which 3 { : i _r ( gpu_launch . ks w_q4_k wg 128 wa ) } {}
        ? == which 4 { : i _r ( gpu_launch . ks w_q6_k wg 128 wa ) } {}
        ? == which 6 { : i _r ( gpu_launch . ks w_q5_0 wg 128 wa ) } {}
        ? == which 7 { : i _r ( gpu_launch . ks w_q5_1 wg 128 wa ) } {}
        ? == which 8 { : i _r ( gpu_launch . ks w_q5_k wg 128 wa ) } {}
        ( vec_free [i] wa )
        ^ T
    } {}
    ? == which 0 {
        ( lk_matvec ks wd xd yd rows cols batch )
        ^ T
    } {}
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 rows ) )
    ( vec_push [i] a ( gpu_arg_i32 cols ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i grid ( gpu_grid * rows batch 64 )
    ? == which 1 { : i _r ( gpu_launch . ks mv_q4_0 grid 64 a ) } {}
    ? == which 2 { : i _r ( gpu_launch . ks mv_q8_0 grid 64 a ) } {}
    ? == which 3 { : i _r ( gpu_launch . ks mv_q4_k grid 64 a ) } {}
    ? == which 4 { : i _r ( gpu_launch . ks mv_q6_k grid 64 a ) } {}
    ? == which 5 { : i _r ( gpu_launch . ks mv_f16 grid 64 a ) } {}
    ? == which 6 { : i _r ( gpu_launch . ks mv_q5_0 grid 64 a ) } {}
    ? == which 7 { : i _r ( gpu_launch . ks mv_q5_1 grid 64 a ) } {}
    ? == which 8 { : i _r ( gpu_launch . ks mv_q5_k grid 64 a ) } {}
    ( vec_free [i] a )
    ^ T
}

@ lk_rmsnorm LlmKernels ks i xd i wd i yd i n f eps i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_f32 eps ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i _r ( gpu_launch . ks rmsnorm ( gpu_grid * n batch 256 ) 256 a )
    ( vec_free [i] a )
}

// style: 0 = NORM (llama), 1 = NEOX (qwen2)
@ lk_rope LlmKernels ks i xd i nh i hd i rd i pos f base i style i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i32 nh ) )
    ( vec_push [i] a ( gpu_arg_i32 hd ) )
    ( vec_push [i] a ( gpu_arg_i32 rd ) )
    ( vec_push [i] a ( gpu_arg_i32 pos ) )
    ( vec_push [i] a ( gpu_arg_f32 base ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i total * * nh / rd 2 batch
    ? == style 1 {
        : i _r ( gpu_launch . ks rope_neox ( gpu_grid total 256 ) 256 a )
    } {
        : i _r ( gpu_launch . ks rope ( gpu_grid total 256 ) 256 a )
    }
    ( vec_free [i] a )
}

// npos0 = the causal window of the FIRST batch element (element b sees
// npos0 + b rows). maxpos strides the per-(batch,head) score scratch.
// Two-pass attention: scores, then softmax + value-weighted sum.
@ lk_attn LlmKernels ks i qd i kcd i vcd i outd i scd i nh i nkv i hd i npos0 i batch i maxpos f qscale i window i causal → v {
    : ( Vec i ) a1 ( vec_new [i] )
    ( vec_push [i] a1 ( gpu_arg_i64 qd ) )
    ( vec_push [i] a1 ( gpu_arg_i64 kcd ) )
    ( vec_push [i] a1 ( gpu_arg_i64 scd ) )
    ( vec_push [i] a1 ( gpu_arg_i32 nh ) )
    ( vec_push [i] a1 ( gpu_arg_i32 nkv ) )
    ( vec_push [i] a1 ( gpu_arg_i32 hd ) )
    ( vec_push [i] a1 ( gpu_arg_i32 npos0 ) )
    ( vec_push [i] a1 ( gpu_arg_i32 batch ) )
    ( vec_push [i] a1 ( gpu_arg_i32 maxpos ) )
    ( vec_push [i] a1 ( gpu_arg_f32 qscale ) )
    ( vec_push [i] a1 ( gpu_arg_i32 window ) )
    ( vec_push [i] a1 ( gpu_arg_i32 causal ) )
    : i _r1 ( gpu_launch . ks attn_sc ( gpu_grid * * * nh batch maxpos 1 256 ) 256 a1 )
    ( vec_free [i] a1 )
    : ( Vec i ) a2 ( vec_new [i] )
    ( vec_push [i] a2 ( gpu_arg_i64 vcd ) )
    ( vec_push [i] a2 ( gpu_arg_i64 scd ) )
    ( vec_push [i] a2 ( gpu_arg_i64 outd ) )
    ( vec_push [i] a2 ( gpu_arg_i32 nh ) )
    ( vec_push [i] a2 ( gpu_arg_i32 nkv ) )
    ( vec_push [i] a2 ( gpu_arg_i32 hd ) )
    ( vec_push [i] a2 ( gpu_arg_i32 npos0 ) )
    ( vec_push [i] a2 ( gpu_arg_i32 batch ) )
    ( vec_push [i] a2 ( gpu_arg_i32 maxpos ) )
    ( vec_push [i] a2 ( gpu_arg_i32 window ) )
    ( vec_push [i] a2 ( gpu_arg_i32 causal ) )
    : i _r2 ( gpu_launch . ks attn_out ( gpu_grid * * nh batch hd 256 ) 256 a2 )
    ( vec_free [i] a2 )
}

// y ← y + a·x — the routed-expert accumulator (each selected expert's
// down-projection lands weighted onto the residual stream).
@ lk_axpy LlmKernels ks i yd i xd f a i n → v {
    : ( Vec i ) ar ( vec_new [i] )
    ( vec_push [i] ar ( gpu_arg_i64 yd ) )
    ( vec_push [i] ar ( gpu_arg_i64 xd ) )
    ( vec_push [i] ar ( gpu_arg_f32 a ) )
    ( vec_push [i] ar ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks axpy ( gpu_grid n 256 ) 256 ar )
    ( vec_free [i] ar )
}

// GeGLU: g ← gelu(g) * u, in place. Same shape as lk_silumul.
@ lk_gelumul LlmKernels ks i gd i ud i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 gd ) )
    ( vec_push [i] a ( gpu_arg_i64 ud ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks gelumul ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

// x ← x * s, in place.
@ lk_scale LlmKernels ks i xd f s i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_f32 s ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks scale ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_silumul LlmKernels ks i gd i ud i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 gd ) )
    ( vec_push [i] a ( gpu_arg_i64 ud ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks silumul ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_addv LlmKernels ks i ad i bd i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 ad ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks addv ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

// a[b][i] += v[i] for every row of the batch
@ lk_addrow LlmKernels ks i ad i vd i n i batch → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 ad ) )
    ( vec_push [i] a ( gpu_arg_i64 vd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    : i _r ( gpu_launch . ks addrow ( gpu_grid * n batch 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_copyat LlmKernels ks i dstd i srcd i off i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 dstd ) )
    ( vec_push [i] a ( gpu_arg_i64 srcd ) )
    ( vec_push [i] a ( gpu_arg_i32 off ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks copyat ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}
