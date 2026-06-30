// packages/onnx/src/ops.nu — ONNX operators as GPU kernels.
//
// Each op is a CUDA-C kernel compiled once via the gpu package's NVRTC
// path and launched over the gpu.nu interface. Tensors live on the device
// as raw CUdeviceptr (i64); shapes are tracked by the executor (runtime.nu).
//
// Op set: Gemm, Relu (dense MLP) + Conv, MaxPool, BatchNormalization,
// LeakyRelu, and broadcast Mul/Add (CNNs, NCHW) — enough to run a
// tiny-YOLO-class detector. All launches are 1-D: thread idx → output
// element; batch N is assumed 1.

$ `stdlib/core/vec.nu`
$ `deps/gpu/src/gpu.nu`

// Compiled kernels, built once and reused across nodes.
: Kernels {
    GpuKernel gemm   GpuKernel relu
    GpuKernel conv   GpuKernel pool
    GpuKernel bn     GpuKernel lrelu  GpuKernel elt
    b ok
}

@ __k_gemm → s {
    ^ `extern "C" __global__ void gemm(
        const float* A, const float* B, const float* C, float* Y,
        int M, int N, int K, float alpha, float beta, int transB) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx < M*N) {
            int r = idx / N, c = idx % N;
            float acc = 0.f;
            for (int k = 0; k < K; ++k) {
                float b = transB ? B[c*K + k] : B[k*N + c];
                acc += A[r*K + k] * b;
            }
            float bias = (C != 0) ? C[c] : 0.f;
            Y[idx] = alpha*acc + beta*bias;
        }
    }`
}

@ __k_relu → s {
    ^ `extern "C" __global__ void relu(const float* X, float* Y, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) { float v = X[i]; Y[i] = v > 0.f ? v : 0.f; }
    }`
}

// 2-D convolution, NCHW, batch 1, group 1. X[Cin,H,W] * W[Cout,Cin,kh,kw]
// (+ optional bias[Cout]) → Y[Cout,OH,OW]. Asymmetric padding via the
// begin pads (ph,pw); out-of-range taps are skipped (zero padding).
@ __k_conv → s {
    ^ `extern "C" __global__ void conv2d(
        const float* X, const float* Wt, const float* B, float* Y,
        int Cin, int H, int W, int Cout, int kh, int kw,
        int OH, int OW, int ph, int pw, int sh, int sw, int hasB) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int total = Cout*OH*OW;
        if (idx >= total) return;
        int ow = idx % OW, oh = (idx / OW) % OH, oc = idx / (OW*OH);
        float acc = hasB ? B[oc] : 0.f;
        for (int ic = 0; ic < Cin; ++ic) {
            const float* xp = X + ic*H*W;
            const float* wp = Wt + ((oc*Cin) + ic)*kh*kw;
            for (int r = 0; r < kh; ++r) {
                int ih = oh*sh - ph + r;
                if (ih < 0 || ih >= H) continue;
                for (int s = 0; s < kw; ++s) {
                    int iw = ow*sw - pw + s;
                    if (iw < 0 || iw >= W) continue;
                    acc += xp[ih*W + iw] * wp[r*kw + s];
                }
            }
        }
        Y[(oc*OH + oh)*OW + ow] = acc;
    }`
}

// 2-D max pool, NCHW. Out-of-range taps (padding) are ignored, i.e. -inf.
@ __k_pool → s {
    ^ `extern "C" __global__ void maxpool2d(
        const float* X, float* Y, int C, int H, int W,
        int kh, int kw, int OH, int OW, int sh, int sw, int ph, int pw) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int total = C*OH*OW;
        if (idx >= total) return;
        int ow = idx % OW, oh = (idx / OW) % OH, c = idx / (OW*OH);
        const float* xp = X + c*H*W;
        float m = -1e30f;
        for (int r = 0; r < kh; ++r) {
            int ih = oh*sh - ph + r;
            if (ih < 0 || ih >= H) continue;
            for (int s = 0; s < kw; ++s) {
                int iw = ow*sw - pw + s;
                if (iw < 0 || iw >= W) continue;
                float v = xp[ih*W + iw];
                if (v > m) m = v;
            }
        }
        Y[(c*OH + oh)*OW + ow] = m;
    }`
}

// BatchNormalization (inference): Y = scale·(X-mean)/sqrt(var+eps) + B,
// per channel. X is C×HW.
@ __k_bn → s {
    ^ `extern "C" __global__ void batchnorm(
        const float* X, const float* sc, const float* B,
        const float* mean, const float* var, float* Y, int C, int HW, float eps) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= C*HW) return;
        int c = idx / HW;
        Y[idx] = sc[c]*(X[idx]-mean[c]) / sqrtf(var[c]+eps) + B[c];
    }`
}

@ __k_lrelu → s {
    ^ `extern "C" __global__ void leakyrelu(const float* X, float* Y, int n, float alpha) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) { float v = X[i]; Y[i] = v >= 0.f ? v : alpha*v; }
    }`
}

// Broadcast elementwise: op 0=mul,1=add; bmode 0=scalar B[0], 1=per-channel
// B[idx/HW], 2=full B[i].
@ __k_elt → s {
    ^ `extern "C" __global__ void eltwise(const float* X, const float* B, float* Y,
        int n, int HW, int op, int bmode) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i >= n) return;
        float b = bmode==0 ? B[0] : (bmode==1 ? B[i/HW] : B[i]);
        Y[i] = op==0 ? X[i]*b : X[i]+b;
    }`
}

@ ops_compile Gpu g → Kernels {
    : GpuKernel kg ( gpu_compile g ( __k_gemm ) `gemm` )
    : GpuKernel kr ( gpu_compile g ( __k_relu ) `relu` )
    : GpuKernel kc ( gpu_compile g ( __k_conv ) `conv2d` )
    : GpuKernel kp ( gpu_compile g ( __k_pool ) `maxpool2d` )
    : GpuKernel kb ( gpu_compile g ( __k_bn ) `batchnorm` )
    : GpuKernel kl ( gpu_compile g ( __k_lrelu ) `leakyrelu` )
    : GpuKernel ke ( gpu_compile g ( __k_elt ) `eltwise` )
    : b ok & & & ( gpu_kernel_ok kg ) ( gpu_kernel_ok kr )
            & ( gpu_kernel_ok kc ) ( gpu_kernel_ok kp )
            & & ( gpu_kernel_ok kb ) ( gpu_kernel_ok kl ) ( gpu_kernel_ok ke )
    ^ @ Kernels { kg kr kc kp kb kl ke ok }
}

@ ops_free Kernels ks → v {
    ( gpu_kernel_free . ks gemm ) ( gpu_kernel_free . ks relu )
    ( gpu_kernel_free . ks conv ) ( gpu_kernel_free . ks pool )
    ( gpu_kernel_free . ks bn ) ( gpu_kernel_free . ks lrelu ) ( gpu_kernel_free . ks elt )
}

// ── launches (dptrs are raw device addresses, i64) ────────────────

@ op_gemm Gpu g Kernels ks i adptr i bdptr i cdptr i ydptr i M i N i K f alpha f beta i transB → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 adptr ) ) ( vec_push [i] a ( gpu_arg_i64 bdptr ) )
    ( vec_push [i] a ( gpu_arg_i64 cdptr ) ) ( vec_push [i] a ( gpu_arg_i64 ydptr ) )
    ( vec_push [i] a ( gpu_arg_i32 M ) ) ( vec_push [i] a ( gpu_arg_i32 N ) ) ( vec_push [i] a ( gpu_arg_i32 K ) )
    ( vec_push [i] a ( gpu_arg_f32 alpha ) ) ( vec_push [i] a ( gpu_arg_f32 beta ) ) ( vec_push [i] a ( gpu_arg_i32 transB ) )
    : i total * M N
    ( gpu_launch . ks gemm ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ ydptr
}

@ op_relu Gpu g Kernels ks i xdptr i ydptr i n → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xdptr ) ) ( vec_push [i] a ( gpu_arg_i64 ydptr ) ) ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( gpu_launch . ks relu ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ ydptr
}

@ op_conv Gpu g Kernels ks i xd i wd i bd i yd i Cin i H i W i Cout i kh i kw i OH i OW i ph i pw i sh i sw i hasB → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 Cin ) ) ( vec_push [i] a ( gpu_arg_i32 H ) ) ( vec_push [i] a ( gpu_arg_i32 W ) )
    ( vec_push [i] a ( gpu_arg_i32 Cout ) ) ( vec_push [i] a ( gpu_arg_i32 kh ) ) ( vec_push [i] a ( gpu_arg_i32 kw ) )
    ( vec_push [i] a ( gpu_arg_i32 OH ) ) ( vec_push [i] a ( gpu_arg_i32 OW ) )
    ( vec_push [i] a ( gpu_arg_i32 ph ) ) ( vec_push [i] a ( gpu_arg_i32 pw ) )
    ( vec_push [i] a ( gpu_arg_i32 sh ) ) ( vec_push [i] a ( gpu_arg_i32 sw ) ) ( vec_push [i] a ( gpu_arg_i32 hasB ) )
    : i total * * Cout OH OW
    ( gpu_launch . ks conv ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_maxpool Gpu g Kernels ks i xd i yd i C i H i W i kh i kw i OH i OW i sh i sw i ph i pw → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 C ) ) ( vec_push [i] a ( gpu_arg_i32 H ) ) ( vec_push [i] a ( gpu_arg_i32 W ) )
    ( vec_push [i] a ( gpu_arg_i32 kh ) ) ( vec_push [i] a ( gpu_arg_i32 kw ) )
    ( vec_push [i] a ( gpu_arg_i32 OH ) ) ( vec_push [i] a ( gpu_arg_i32 OW ) )
    ( vec_push [i] a ( gpu_arg_i32 sh ) ) ( vec_push [i] a ( gpu_arg_i32 sw ) )
    ( vec_push [i] a ( gpu_arg_i32 ph ) ) ( vec_push [i] a ( gpu_arg_i32 pw ) )
    : i total * * C OH OW
    ( gpu_launch . ks pool ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_batchnorm Gpu g Kernels ks i xd i scd i bd i md i vd i yd i C i HW f eps → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 scd ) ) ( vec_push [i] a ( gpu_arg_i64 bd ) )
    ( vec_push [i] a ( gpu_arg_i64 md ) ) ( vec_push [i] a ( gpu_arg_i64 vd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 C ) ) ( vec_push [i] a ( gpu_arg_i32 HW ) ) ( vec_push [i] a ( gpu_arg_f32 eps ) )
    : i total * C HW
    ( gpu_launch . ks bn ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_leakyrelu Gpu g Kernels ks i xd i yd i n f alpha → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) ) ( vec_push [i] a ( gpu_arg_f32 alpha ) )
    ( gpu_launch . ks lrelu ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_eltwise Gpu g Kernels ks i xd i bd i yd i n i HW i op i bmode → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) ) ( vec_push [i] a ( gpu_arg_i32 HW ) )
    ( vec_push [i] a ( gpu_arg_i32 op ) ) ( vec_push [i] a ( gpu_arg_i32 bmode ) )
    ( gpu_launch . ks elt ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}
