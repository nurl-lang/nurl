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
    GpuKernel rmsnorm
    GpuKernel rope
    GpuKernel rope_neox
    GpuKernel attn
    GpuKernel silumul
    GpuKernel addv
    GpuKernel addrow
    GpuKernel copyat
    b ok
}

@ __lk_matvec → s {
    ^ `extern "C" __global__ void matvec(
        const float* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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
        const unsigned char* W, const float* x, float* y, int rows, int cols, int batch) {
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

@ lk_build Gpu g → LlmKernels {
    : GpuKernel k1 ( gpu_compile g ( __lk_matvec ) `matvec` )
    : GpuKernel k2 ( gpu_compile g ( __lk_rmsnorm ) `rmsnorm` )
    : GpuKernel k3 ( gpu_compile g ( __lk_rope ) `rope` )
    : GpuKernel k3n ( gpu_compile g ( __lk_rope_neox ) `rope_neox` )
    : GpuKernel k4 ( gpu_compile g ( __lk_attn ) `attn` )
    : GpuKernel k5 ( gpu_compile g ( __lk_silumul ) `silumul` )
    : GpuKernel k6 ( gpu_compile g ( __lk_addv ) `addv` )
    : GpuKernel k6b ( gpu_compile g ( __lk_addrow ) `addrow` )
    : GpuKernel k7 ( gpu_compile g ( __lk_copyat ) `copyat` )
    : GpuKernel q1 ( gpu_compile g ( __lk_mv_q4_0 ) `mv_q4_0` )
    : GpuKernel q2 ( gpu_compile g ( __lk_mv_q8_0 ) `mv_q8_0` )
    : GpuKernel q3 ( gpu_compile g ( __lk_mv_q4_k ) `mv_q4_k` )
    : GpuKernel q4 ( gpu_compile g ( __lk_mv_q6_k ) `mv_q6_k` )
    : GpuKernel q5 ( gpu_compile g ( __lk_mv_f16 ) `mv_f16` )
    : GpuKernel q6 ( gpu_compile g ( __lk_mv_q5_0 ) `mv_q5_0` )
    : GpuKernel q7 ( gpu_compile g ( __lk_mv_q5_1 ) `mv_q5_1` )
    : GpuKernel q8 ( gpu_compile g ( __lk_mv_q5_k ) `mv_q5_k` )
    : b ok0 & & & ( gpu_kernel_ok k1 ) ( gpu_kernel_ok k2 )
    & ( gpu_kernel_ok k3 ) ( gpu_kernel_ok k4 )
    & & ( gpu_kernel_ok k5 ) ( gpu_kernel_ok k6 ) ( gpu_kernel_ok k7 )
    : b ok1 & & ( gpu_kernel_ok q1 ) ( gpu_kernel_ok q2 )
    & & ( gpu_kernel_ok q3 ) ( gpu_kernel_ok q4 ) ( gpu_kernel_ok q5 )
    : b ok & & & ok0 ( gpu_kernel_ok k3n ) ( gpu_kernel_ok k6b ) & ok1 & & ( gpu_kernel_ok q6 ) ( gpu_kernel_ok q7 ) ( gpu_kernel_ok q8 )
    ^ @ LlmKernels { k1 q1 q2 q6 q7 q3 q8 q4 q5 k2 k3 k3n k4 k5 k6 k6b k7 ok }
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
    ( gpu_kernel_free . ks rmsnorm )
    ( gpu_kernel_free . ks rope )
    ( gpu_kernel_free . ks rope_neox )
    ( gpu_kernel_free . ks attn )
    ( gpu_kernel_free . ks silumul )
    ( gpu_kernel_free . ks addv )
    ( gpu_kernel_free . ks addrow )
    ( gpu_kernel_free . ks copyat )
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
@ lk_attn LlmKernels ks i qd i kcd i vcd i outd i scd i nh i nkv i hd i npos0 i batch i maxpos → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 qd ) )
    ( vec_push [i] a ( gpu_arg_i64 kcd ) )
    ( vec_push [i] a ( gpu_arg_i64 vcd ) )
    ( vec_push [i] a ( gpu_arg_i64 outd ) )
    ( vec_push [i] a ( gpu_arg_i64 scd ) )
    ( vec_push [i] a ( gpu_arg_i32 nh ) )
    ( vec_push [i] a ( gpu_arg_i32 nkv ) )
    ( vec_push [i] a ( gpu_arg_i32 hd ) )
    ( vec_push [i] a ( gpu_arg_i32 npos0 ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) )
    ( vec_push [i] a ( gpu_arg_i32 maxpos ) )
    : i _r ( gpu_launch . ks attn ( gpu_grid * nh batch 32 ) 32 a )
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
