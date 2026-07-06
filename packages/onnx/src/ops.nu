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
    GpuKernel gemm GpuKernel relu
    GpuKernel conv GpuKernel pool
    GpuKernel bn GpuKernel lrelu GpuKernel elt
    GpuKernel sig GpuKernel resize GpuKernel perm
    GpuKernel softm GpuKernel cpyax
    GpuKernel rl2 GpuKernel clip GpuKernel expand GpuKernel slice
    GpuKernel lnorm GpuKernel erf GpuKernel gather GpuKernel bmm GpuKernel amax GpuKernel amax64
    GpuKernel eos GpuKernel convt
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

// 2-D transposed convolution (a.k.a. deconv), NCHW, batch 1, group 1. Used
// by the YOLOE segmentation Proto module to 2× upsample the mask prototypes
// (256ch, 2×2 kernel, stride 2: 80²→160²). The PyTorch weight layout for
// ConvTranspose2d is [Cin, Cout, kh, kw] (note: Cin first, unlike Conv).
// Gather form, one thread per output element: Y[oc,oy,ox] = bias +
// Σ_{ic,ky,kx} X[ic,iy,ix]·W[ic,oc,ky,kx] where oy = iy·sh − ph + ky (so
// iy = (oy + ph − ky)/sh, taken only when it divides evenly and is in range).
@ __k_convt → s {
    ^ `extern "C" __global__ void convtranspose2d(
        const float* X, const float* Wt, const float* B, float* Y,
        int Cin, int H, int W, int Cout, int kh, int kw,
        int OH, int OW, int ph, int pw, int sh, int sw, int hasB) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        int total = Cout*OH*OW;
        if (idx >= total) return;
        int ox = idx % OW, oy = (idx / OW) % OH, oc = idx / (OW*OH);
        float acc = hasB ? B[oc] : 0.f;
        for (int ic = 0; ic < Cin; ++ic) {
            const float* xp = X + ic*H*W;
            for (int ky = 0; ky < kh; ++ky) {
                int ty = oy + ph - ky;
                if (ty % sh != 0) continue;
                int iy = ty / sh;
                if (iy < 0 || iy >= H) continue;
                for (int kx = 0; kx < kw; ++kx) {
                    int tx = ox + pw - kx;
                    if (tx % sw != 0) continue;
                    int ix = tx / sw;
                    if (ix < 0 || ix >= W) continue;
                    acc += xp[iy*W + ix] * Wt[(((ic*Cout)+oc)*kh + ky)*kw + kx];
                }
            }
        }
        Y[(oc*OH + oy)*OW + ox] = acc;
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

// Broadcast elementwise. op: 0=mul 1=add 2=sub 3=div (X op B, order kept).
// bmode: 0=scalar B[0], 1=per-channel B[i/per], 2=full B[i], 3=per-inner
// B[i%per] (e.g. a per-anchor stride vector broadcast over coordinates).
@ __k_elt → s {
    ^ `extern "C" __global__ void eltwise(const float* X, const float* B, float* Y,
        int n, int per, int op, int bmode) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i >= n) return;
        float b;
        if (bmode==0) b = B[0];
        else if (bmode==1) b = B[i/per];
        else if (bmode==3) b = B[i%per];
        else b = B[i];
        float x = X[i];
        Y[i] = op==0 ? x*b : (op==1 ? x+b : (op==2 ? x-b : x/b));
    }`
}

// ── extra YOLO ops ────────────────────────────────────────────────
@ __k_sig → s {
    ^ `extern "C" __global__ void osigmoid(const float* X, float* Y, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) Y[i] = 1.f / (1.f + expf(-X[i]));
    }`
}

// Nearest-neighbour upsample by integer factors (NCHW). Y[c,oy,ox] = X[c,oy/sh,ox/sw].
@ __k_resize → s {
    ^ `extern "C" __global__ void resize_nn(const float* X, float* Y,
        int C, int H, int W, int OH, int OW, int sh, int sw) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= C*OH*OW) return;
        int ox = idx % OW, oy = (idx / OW) % OH, c = idx / (OW*OH);
        Y[idx] = X[(c*H + oy/sh)*W + ox/sw];
    }`
}

// General N-D (≤6) transpose. d* = input dims (size-1 padded), p* = perm
// (output axis k reads input axis p[k]). One thread per output element.
@ __k_perm → s {
    ^ `extern "C" __global__ void perm6(const float* X, float* Y,
        int d0,int d1,int d2,int d3,int d4,int d5,
        int p0,int p1,int p2,int p3,int p4,int p5) {
        int D[6] = {d0,d1,d2,d3,d4,d5};
        int P[6] = {p0,p1,p2,p3,p4,p5};
        int O[6]; for (int i=0;i<6;i++) O[i] = D[P[i]];
        int tot = O[0]*O[1]*O[2]*O[3]*O[4]*O[5];
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= tot) return;
        int oc[6]; int t = idx;
        for (int i=5;i>=0;i--){ oc[i] = t % O[i]; t /= O[i]; }
        int in[6]; for (int i=0;i<6;i++) in[P[i]] = oc[i];
        int si = ((((in[0]*d1 + in[1])*d2 + in[2])*d3 + in[3])*d4 + in[4])*d5 + in[5];
        Y[idx] = X[si];
    }`
}

// Softmax along an axis viewed as (outer, ax, inner): for each (outer,inner)
// the `ax` elements at stride `inner` form one distribution.
@ __k_softmax → s {
    ^ `extern "C" __global__ void softmax_ax(const float* X, float* Y,
        int outer, int ax, int inner) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= outer*inner) return;
        int io = idx / inner, ii = idx % inner;
        int base = io*ax*inner + ii;
        float m = -1e30f;
        for (int a=0;a<ax;a++){ float v=X[base+a*inner]; if(v>m)m=v; }
        float s=0.f;
        for (int a=0;a<ax;a++){ s += expf(X[base+a*inner]-m); }
        for (int a=0;a<ax;a++){ Y[base+a*inner] = expf(X[base+a*inner]-m)/s; }
    }`
}

// Copy one source tensor into a concat output along an axis viewed as
// (outer, src_ax, inner); the slot starts at `off` in the output's axis of
// size `dst_ax`.  out[outer, off+a, inner] = src[outer, a, inner].
@ __k_cpyax → s {
    ^ `extern "C" __global__ void copy_ax(const float* S, float* D,
        int outer, int src_ax, int inner, int dst_ax, int off) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= outer*src_ax*inner) return;
        int ii = idx % inner; int t = idx / inner;
        int a = t % src_ax; int o = t / src_ax;
        D[(o*dst_ax + (off+a))*inner + ii] = S[idx];
    }`
}

// Extract a contiguous axis slice into a fresh tensor: viewing src as
// (outer, src_ax, inner), D[o,a,i] = S[o, soff+a, i] for a in [0,sz).
// (Split where outer>1 — the slices interleave and can't be aliased.)
@ __k_slice → s {
    ^ `extern "C" __global__ void slice_ax(const float* S, float* D,
        int outer, int sz, int inner, int src_ax, int soff) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= outer*sz*inner) return;
        int ii = idx % inner; int t = idx / inner;
        int a = t % sz; int o = t / sz;
        D[idx] = S[(o*src_ax + (soff+a))*inner + ii];
    }`
}
// ── transformer ops ───────────────────────────────────────────────
// LayerNormalization over the last axis: per (outer) row of `ax` elements,
// y = (x-mean)/sqrt(var+eps)*scale[j] + bias[j].
@ __k_lnorm → s {
    ^ `extern "C" __global__ void layernorm(const float* X, const float* sc, const float* bi,
        float* Y, int outer, int ax, float eps) {
        int o = blockIdx.x*blockDim.x + threadIdx.x;
        if (o >= outer) return;
        const float* p = X + o*ax;
        float m = 0.f; for (int j=0;j<ax;j++) m += p[j]; m /= ax;
        float v = 0.f; for (int j=0;j<ax;j++){ float d=p[j]-m; v += d*d; } v /= ax;
        float inv = 1.f/sqrtf(v+eps);
        float* q = Y + o*ax;
        for (int j=0;j<ax;j++) q[j] = (p[j]-m)*inv*sc[j] + bi[j];
    }`
}

@ __k_erf → s {
    ^ `extern "C" __global__ void erfk(const float* X, float* Y, int n) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) Y[i] = erff(X[i]);
    }`
}
// Gather along `axis`: out replaces the axis coordinate with idx[g]. Viewed
// as (outer, axis_in, inner) for the data and outer*nidx*inner for output.
@ __k_gather → s {
    ^ `extern "C" __global__ void gather(const float* D, const long long* idx, float* Y,
        int outer, int axis_in, int inner, int nidx) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i >= outer*nidx*inner) return;
        int ii = i % inner; int t = i / inner;
        int g = t % nidx; int o = t / nidx;
        long long ix = idx[g];
        Y[i] = D[(o*axis_in + (int)ix)*inner + ii];
    }`
}
// Batched matmul: A[batch,M,K] @ B[batch,K,N] -> Y[batch,M,N].
@ __k_bmm → s {
    ^ `extern "C" __global__ void bmm(const float* A, const float* B, float* Y,
        int batch, int M, int N, int K) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= batch*M*N) return;
        int c = idx % N; int t = idx / N; int r = t % M; int b = t / M;
        const float* a = A + b*M*K; const float* bb = B + b*K*N;
        float acc = 0.f;
        for (int k=0;k<K;k++) acc += a[r*K+k]*bb[k*N+c];
        Y[idx] = acc;
    }`
}
// ArgMax along the last axis: input (outer, ax) -> int64 indices (outer).
@ __k_amax → s {
    ^ `extern "C" __global__ void argmaxk(const float* X, long long* Y, int outer, int ax) {
        int o = blockIdx.x*blockDim.x + threadIdx.x;
        if (o >= outer) return;
        const float* p = X + o*ax;
        int bi = 0; float bv = p[0];
        for (int j=1;j<ax;j++){ if (p[j]>bv){ bv=p[j]; bi=j; } }
        Y[o] = bi;
    }`
}

// CLIP EOS read-out: given per-row sequences `tok` [B,L] (int64) and the
// transformer output `data` [B,L,D], select each row's EOS token (the
// argmax token id) features → Y [B,D]. One thread per output element.
// Same, over int64 input (CLIP token ids: the EOT position is the row's
// max id). Output int64 indices, one per outer row.
@ __k_amax_i64 → s {
    ^ `extern "C" __global__ void argmaxk_i64(const long long* X, long long* Y, int outer, int ax) {
        int o = blockIdx.x*blockDim.x + threadIdx.x;
        if (o >= outer) return;
        const long long* p = X + o*ax;
        int bi = 0; long long bv = p[0];
        for (int j=1;j<ax;j++){ if (p[j]>bv){ bv=p[j]; bi=j; } }
        Y[o] = bi;
    }`
}

@ __k_eosgather → s {
    ^ `extern "C" __global__ void eos_gather(const float* data, const long long* tok,
        float* Y, int B, int L, int D) {
        int idx = blockIdx.x*blockDim.x + threadIdx.x;
        if (idx >= B*D) return;
        int d = idx % D; int b = idx / D;
        const long long* t = tok + b*L;
        int pos = 0; long long mx = t[0];
        for (int j=1;j<L;j++){ if (t[j]>mx){ mx=t[j]; pos=j; } }
        Y[idx] = data[(b*L + pos)*D + d];
    }`
}

// L2 norm along the last axis: input viewed as (outer, ax) → (outer, 1).
@ __k_rl2 → s {
    ^ `extern "C" __global__ void reducel2(const float* X, float* Y, int outer, int ax) {
        int o = blockIdx.x*blockDim.x + threadIdx.x;
        if (o >= outer) return;
        const float* p = X + o*ax;
        float s = 0.f;
        for (int a=0;a<ax;a++) s += p[a]*p[a];
        Y[o] = sqrtf(s);
    }`
}
// Clip / clamp to [lo, hi].
@ __k_clip → s {
    ^ `extern "C" __global__ void clipk(const float* X, float* Y, int n, float lo, float hi) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) { float v = X[i]; Y[i] = v < lo ? lo : (v > hi ? hi : v); }
    }`
}
// Expand the last axis: input (outer,1) → (outer,rep), Y[o,r] = X[o].
@ __k_expand → s {
    ^ `extern "C" __global__ void expandlast(const float* X, float* Y, int outer, int rep) {
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < outer*rep) Y[i] = X[i/rep];
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
    : GpuKernel ksg ( gpu_compile g ( __k_sig ) `osigmoid` )
    : GpuKernel krz ( gpu_compile g ( __k_resize ) `resize_nn` )
    : GpuKernel kpm ( gpu_compile g ( __k_perm ) `perm6` )
    : GpuKernel ksm ( gpu_compile g ( __k_softmax ) `softmax_ax` )
    : GpuKernel kcp ( gpu_compile g ( __k_cpyax ) `copy_ax` )
    : GpuKernel krl ( gpu_compile g ( __k_rl2 ) `reducel2` )
    : GpuKernel kcl ( gpu_compile g ( __k_clip ) `clipk` )
    : GpuKernel kex ( gpu_compile g ( __k_expand ) `expandlast` )
    : GpuKernel ksl ( gpu_compile g ( __k_slice ) `slice_ax` )
    : GpuKernel kln ( gpu_compile g ( __k_lnorm ) `layernorm` )
    : GpuKernel ker ( gpu_compile g ( __k_erf ) `erfk` )
    : GpuKernel kga ( gpu_compile g ( __k_gather ) `gather` )
    : GpuKernel kbm ( gpu_compile g ( __k_bmm ) `bmm` )
    : GpuKernel kam ( gpu_compile g ( __k_amax ) `argmaxk` )
    : GpuKernel ka6 ( gpu_compile g ( __k_amax_i64 ) `argmaxk_i64` )
    : GpuKernel keo ( gpu_compile g ( __k_eosgather ) `eos_gather` )
    : GpuKernel kct ( gpu_compile g ( __k_convt ) `convtranspose2d` )
    : b ok1 & & & ( gpu_kernel_ok kg ) ( gpu_kernel_ok kr ) & ( gpu_kernel_ok kc ) ( gpu_kernel_ok kp )
    & & ( gpu_kernel_ok kb ) ( gpu_kernel_ok kl ) ( gpu_kernel_ok ke )
    : b ok2 & & ( gpu_kernel_ok ksg ) ( gpu_kernel_ok krz )
    & & ( gpu_kernel_ok kpm ) ( gpu_kernel_ok ksm ) ( gpu_kernel_ok kcp )
    : b ok3 & & & ( gpu_kernel_ok krl ) ( gpu_kernel_ok kcl ) ( gpu_kernel_ok kex ) ( gpu_kernel_ok ksl )
    : b ok4 & & & & & & & ( gpu_kernel_ok kln ) ( gpu_kernel_ok ker ) ( gpu_kernel_ok kga ) ( gpu_kernel_ok kbm ) ( gpu_kernel_ok kam ) ( gpu_kernel_ok ka6 ) ( gpu_kernel_ok keo ) ( gpu_kernel_ok kct )
    ^ @ Kernels { kg kr kc kp kb kl ke ksg krz kpm ksm kcp krl kcl kex ksl kln ker kga kbm kam ka6 keo kct & & & ok1 ok2 ok3 ok4 }
}

@ ops_free Kernels ks → v {
    ( gpu_kernel_free . ks gemm ) ( gpu_kernel_free . ks relu )
    ( gpu_kernel_free . ks conv ) ( gpu_kernel_free . ks pool )
    ( gpu_kernel_free . ks bn ) ( gpu_kernel_free . ks lrelu ) ( gpu_kernel_free . ks elt )
    ( gpu_kernel_free . ks sig ) ( gpu_kernel_free . ks resize ) ( gpu_kernel_free . ks perm )
    ( gpu_kernel_free . ks softm ) ( gpu_kernel_free . ks cpyax )
    ( gpu_kernel_free . ks rl2 ) ( gpu_kernel_free . ks clip ) ( gpu_kernel_free . ks expand )
    ( gpu_kernel_free . ks slice )
    ( gpu_kernel_free . ks lnorm ) ( gpu_kernel_free . ks erf ) ( gpu_kernel_free . ks gather )
    ( gpu_kernel_free . ks bmm ) ( gpu_kernel_free . ks amax ) ( gpu_kernel_free . ks eos )
    ( gpu_kernel_free . ks convt )
}

@ op_eos_gather Gpu g Kernels ks i datad i tokd i yd i B i L i D → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 datad ) ) ( vec_push [i] a ( gpu_arg_i64 tokd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 B ) ) ( vec_push [i] a ( gpu_arg_i32 L ) ) ( vec_push [i] a ( gpu_arg_i32 D ) )
    : i total * B D
    ( gpu_launch . ks eos ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_layernorm Gpu g Kernels ks i xd i scd i bd i yd i outer i ax f eps → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 scd ) ) ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 ax ) ) ( vec_push [i] a ( gpu_arg_f32 eps ) )
    ( gpu_launch . ks lnorm ( gpu_grid outer 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_erf Gpu g Kernels ks i xd i yd i n → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) ) ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( gpu_launch . ks erf ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_gather Gpu g Kernels ks i dd i idd i yd i outer i axis_in i inner i nidx → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 dd ) ) ( vec_push [i] a ( gpu_arg_i64 idd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 axis_in ) ) ( vec_push [i] a ( gpu_arg_i32 inner ) ) ( vec_push [i] a ( gpu_arg_i32 nidx ) )
    : i total * * outer nidx inner
    ( gpu_launch . ks gather ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_bmm Gpu g Kernels ks i ad i bd i yd i batch i M i N i K → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 ad ) ) ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 batch ) ) ( vec_push [i] a ( gpu_arg_i32 M ) ) ( vec_push [i] a ( gpu_arg_i32 N ) ) ( vec_push [i] a ( gpu_arg_i32 K ) )
    : i total * * batch M N
    ( gpu_launch . ks bmm ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_argmax Gpu g Kernels ks i xd i yd i outer i ax → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 ax ) )
    ( gpu_launch . ks amax ( gpu_grid outer 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_argmax_i64 Gpu g Kernels ks i xd i yd i outer i ax → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 ax ) )
    ( gpu_launch . ks amax64 ( gpu_grid outer 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_slice_ax Gpu g Kernels ks i sd i dd i outer i sz i inner i src_ax i soff → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 sd ) ) ( vec_push [i] a ( gpu_arg_i64 dd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 sz ) ) ( vec_push [i] a ( gpu_arg_i32 inner ) )
    ( vec_push [i] a ( gpu_arg_i32 src_ax ) ) ( vec_push [i] a ( gpu_arg_i32 soff ) )
    : i total * * outer sz inner
    ( gpu_launch . ks slice ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ dd
}

@ op_reducel2 Gpu g Kernels ks i xd i yd i outer i ax → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 ax ) )
    ( gpu_launch . ks rl2 ( gpu_grid outer 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_clip Gpu g Kernels ks i xd i yd i n f lo f hi → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) ) ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( vec_push [i] a ( gpu_arg_f32 lo ) ) ( vec_push [i] a ( gpu_arg_f32 hi ) )
    ( gpu_launch . ks clip ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_expand Gpu g Kernels ks i xd i yd i outer i rep → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 rep ) )
    : i total * outer rep
    ( gpu_launch . ks expand ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
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

@ op_convtranspose Gpu g Kernels ks i xd i wd i bd i yd i Cin i H i W i Cout i kh i kw i OH i OW i ph i pw i sh i sw i hasB → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 wd ) )
    ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 Cin ) ) ( vec_push [i] a ( gpu_arg_i32 H ) ) ( vec_push [i] a ( gpu_arg_i32 W ) )
    ( vec_push [i] a ( gpu_arg_i32 Cout ) ) ( vec_push [i] a ( gpu_arg_i32 kh ) ) ( vec_push [i] a ( gpu_arg_i32 kw ) )
    ( vec_push [i] a ( gpu_arg_i32 OH ) ) ( vec_push [i] a ( gpu_arg_i32 OW ) )
    ( vec_push [i] a ( gpu_arg_i32 ph ) ) ( vec_push [i] a ( gpu_arg_i32 pw ) )
    ( vec_push [i] a ( gpu_arg_i32 sh ) ) ( vec_push [i] a ( gpu_arg_i32 sw ) ) ( vec_push [i] a ( gpu_arg_i32 hasB ) )
    : i total * * Cout OH OW
    ( gpu_launch . ks convt ( gpu_grid total 256 ) 256 a )
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

@ op_eltwise Gpu g Kernels ks i xd i bd i yd i n i per i op i bmode → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 bd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 n ) ) ( vec_push [i] a ( gpu_arg_i32 per ) )
    ( vec_push [i] a ( gpu_arg_i32 op ) ) ( vec_push [i] a ( gpu_arg_i32 bmode ) )
    ( gpu_launch . ks elt ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_sigmoid Gpu g Kernels ks i xd i yd i n → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) ) ( vec_push [i] a ( gpu_arg_i32 n ) )
    ( gpu_launch . ks sig ( gpu_grid n 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_resize Gpu g Kernels ks i xd i yd i C i H i W i OH i OW i sh i sw → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 C ) ) ( vec_push [i] a ( gpu_arg_i32 H ) ) ( vec_push [i] a ( gpu_arg_i32 W ) )
    ( vec_push [i] a ( gpu_arg_i32 OH ) ) ( vec_push [i] a ( gpu_arg_i32 OW ) )
    ( vec_push [i] a ( gpu_arg_i32 sh ) ) ( vec_push [i] a ( gpu_arg_i32 sw ) )
    : i total * * C OH OW
    ( gpu_launch . ks resize ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_perm6 Gpu g Kernels ks i xd i yd i d0 i d1 i d2 i d3 i d4 i d5 i p0 i p1 i p2 i p3 i p4 i p5 → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 d0 ) ) ( vec_push [i] a ( gpu_arg_i32 d1 ) ) ( vec_push [i] a ( gpu_arg_i32 d2 ) )
    ( vec_push [i] a ( gpu_arg_i32 d3 ) ) ( vec_push [i] a ( gpu_arg_i32 d4 ) ) ( vec_push [i] a ( gpu_arg_i32 d5 ) )
    ( vec_push [i] a ( gpu_arg_i32 p0 ) ) ( vec_push [i] a ( gpu_arg_i32 p1 ) ) ( vec_push [i] a ( gpu_arg_i32 p2 ) )
    ( vec_push [i] a ( gpu_arg_i32 p3 ) ) ( vec_push [i] a ( gpu_arg_i32 p4 ) ) ( vec_push [i] a ( gpu_arg_i32 p5 ) )
    : i total * * * * * d0 d1 d2 d3 d4 d5
    ( gpu_launch . ks perm ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

@ op_softmax Gpu g Kernels ks i xd i yd i outer i ax i inner → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 xd ) ) ( vec_push [i] a ( gpu_arg_i64 yd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 ax ) ) ( vec_push [i] a ( gpu_arg_i32 inner ) )
    : i total * outer inner
    ( gpu_launch . ks softm ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a ) ^ yd
}

// Copy one source into a concat output's axis slot at `off`.
@ op_copy_ax Gpu g Kernels ks i sd i dd i outer i src_ax i inner i dst_ax i off → v {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a ( gpu_arg_i64 sd ) ) ( vec_push [i] a ( gpu_arg_i64 dd ) )
    ( vec_push [i] a ( gpu_arg_i32 outer ) ) ( vec_push [i] a ( gpu_arg_i32 src_ax ) ) ( vec_push [i] a ( gpu_arg_i32 inner ) )
    ( vec_push [i] a ( gpu_arg_i32 dst_ax ) ) ( vec_push [i] a ( gpu_arg_i32 off ) )
    : i total * * outer src_ax inner
    ( gpu_launch . ks cpyax ( gpu_grid total 256 ) 256 a )
    ( vec_free [i] a )
}
