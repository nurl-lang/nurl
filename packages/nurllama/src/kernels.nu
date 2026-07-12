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
    GpuKernel rmsnorm
    GpuKernel rope
    GpuKernel attn
    GpuKernel silumul
    GpuKernel addv
    GpuKernel copyat
    b ok
}

@ __lk_matvec → s {
    ^ `extern "C" __global__ void matvec(
        const float* W, const float* x, float* y, int rows, int cols) {
        int r = blockIdx.x*blockDim.x + threadIdx.x;
        if (r < rows) {
            const float* w = W + (long long)r*cols;
            float acc = 0.f;
            for (int c = 0; c < cols; ++c) acc += w[c]*x[c];
            y[r] = acc;
        }
    }`
}

// Every thread recomputes the sum of squares — O(n²) total, but norms
// are dwarfed by the matvecs at decode shapes and this keeps the
// kernel valid on the block-serial CPU backend (no cross-thread sync).
@ __lk_rmsnorm → s {
    ^ `extern "C" __global__ void rmsnorm(
        const float* x, const float* w, float* y, int n, float eps) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) {
            float ss = 0.f;
            for (int j = 0; j < n; ++j) ss += x[j]*x[j];
            float inv = rsqrtf(ss/n + eps);
            y[i] = x[i]*inv*w[i];
        }
    }`
}

// Rotary embedding, ggml NORM style (llama): adjacent pairs (2j, 2j+1)
// of the first rd dims of every head rotate by pos·base^(-2j/rd).
@ __lk_rope → s {
    ^ `extern "C" __global__ void rope(
        float* x, int nh, int hd, int rd, int pos, float base) {
        int p = blockIdx.x*blockDim.x + threadIdx.x;
        int pairs = rd/2;
        if (p < nh*pairs) {
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

// Causal attention for ONE decode position: head h attends over cache
// rows 0..pos. One thread per head — serial softmax keeps it exact and
// sync-free; npos·hd·2 flops per head is noise next to the matvecs.
// GQA: query head h reads kv head h/(nh/nkv).
@ __lk_attn → s {
    ^ `extern "C" __global__ void attn(
        const float* q, const float* K, const float* V, float* out,
        float* scores, int nh, int nkv, int hd, int npos) {
        int h = blockIdx.x*blockDim.x + threadIdx.x;
        if (h < nh) {
            int kvdim = nkv*hd;
            int kh = h / (nh/nkv);
            const float* qh = q + h*hd;
            float* sc = scores + (long long)h*npos;
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

// Element copy into an offset — appends k/v rows into the cache.
@ __lk_copyat → s {
    ^ `extern "C" __global__ void copyat(float* dst, const float* src, int off, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) dst[off + i] = src[i];
    }`
}

@ lk_build Gpu g → LlmKernels {
    : GpuKernel k1 ( gpu_compile g ( __lk_matvec ) `matvec` )
    : GpuKernel k2 ( gpu_compile g ( __lk_rmsnorm ) `rmsnorm` )
    : GpuKernel k3 ( gpu_compile g ( __lk_rope ) `rope` )
    : GpuKernel k4 ( gpu_compile g ( __lk_attn ) `attn` )
    : GpuKernel k5 ( gpu_compile g ( __lk_silumul ) `silumul` )
    : GpuKernel k6 ( gpu_compile g ( __lk_addv ) `addv` )
    : GpuKernel k7 ( gpu_compile g ( __lk_copyat ) `copyat` )
    : b ok & & & ( gpu_kernel_ok k1 ) ( gpu_kernel_ok k2 )
    & ( gpu_kernel_ok k3 ) ( gpu_kernel_ok k4 )
    & & ( gpu_kernel_ok k5 ) ( gpu_kernel_ok k6 ) ( gpu_kernel_ok k7 )
    ^ @ LlmKernels { k1 k2 k3 k4 k5 k6 k7 ok }
}

@ lk_free LlmKernels ks → v {
    ( gpu_kernel_free . ks matvec )
    ( gpu_kernel_free . ks rmsnorm )
    ( gpu_kernel_free . ks rope )
    ( gpu_kernel_free . ks attn )
    ( gpu_kernel_free . ks silumul )
    ( gpu_kernel_free . ks addv )
    ( gpu_kernel_free . ks copyat )
}

// ── launch wrappers (raw device pointers, onnx op idiom) ────────────

@ lk_matvec LlmKernels ks i wd i xd i yd i rows i cols → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 rows ) )
    ( vec_push [i] a ( gpu_arg_i32 cols ) )
    : i _r ( gpu_launch . ks matvec ( gpu_grid rows 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_rmsnorm LlmKernels ks i xd i wd i yd i n f eps → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_f32 eps ) )
    : i _r ( gpu_launch . ks rmsnorm ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_rope LlmKernels ks i xd i nh i hd i rd i pos f base → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) )
    ( vec_push [i] a ( gpu_arg_i32 nh ) )
    ( vec_push [i] a ( gpu_arg_i32 hd ) )
    ( vec_push [i] a ( gpu_arg_i32 rd ) )
    ( vec_push [i] a ( gpu_arg_i32 pos ) )
    ( vec_push [i] a ( gpu_arg_f32 base ) )
    : i total * nh / rd 2
    : i _r ( gpu_launch . ks rope ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a )
}

@ lk_attn LlmKernels ks i qd i kcd i vcd i outd i scd i nh i nkv i hd i npos → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 qd ) )
    ( vec_push [i] a ( gpu_arg_i64 kcd ) )
    ( vec_push [i] a ( gpu_arg_i64 vcd ) )
    ( vec_push [i] a ( gpu_arg_i64 outd ) )
    ( vec_push [i] a ( gpu_arg_i64 scd ) )
    ( vec_push [i] a ( gpu_arg_i32 nh ) )
    ( vec_push [i] a ( gpu_arg_i32 nkv ) )
    ( vec_push [i] a ( gpu_arg_i32 hd ) )
    ( vec_push [i] a ( gpu_arg_i32 npos ) )
    : i _r ( gpu_launch . ks attn ( gpu_grid nh 32 ) 32 a )
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

@ lk_copyat LlmKernels ks i dstd i srcd i off i n → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 dstd ) )
    ( vec_push [i] a ( gpu_arg_i64 srcd ) )
    ( vec_push [i] a ( gpu_arg_i32 off ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) )
    : i _r ( gpu_launch . ks copyat ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a )
}
