// packages/onnx/src/ops.nu — ONNX operators as GPU kernels.
//
// Each op is a CUDA-C kernel compiled once via the gpu package's NVRTC
// path and launched over the gpu.nu interface. Tensors live on the device
// as raw CUdeviceptr (i64); shapes are tracked by the executor (runtime.nu).
//
// v0.1.0 op set: Gemm (Y = alpha·A·Bᵀ? + beta·C, bias broadcast) and Relu
// — enough for a feed-forward MLP. 1-D launches: a Gemm of M×N outputs
// maps thread idx → (row, col); Relu is elementwise.

$ `stdlib/core/vec.nu`
$ `deps/gpu/src/gpu.nu`

// Compiled kernels, built once and reused across nodes.
: Kernels { GpuKernel gemm  GpuKernel relu  b ok }

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

@ ops_compile Gpu g → Kernels {
    : GpuKernel kg ( gpu_compile g ( __k_gemm ) `gemm` )
    : GpuKernel kr ( gpu_compile g ( __k_relu ) `relu` )
    : b ok & ( gpu_kernel_ok kg ) ( gpu_kernel_ok kr )
    ^ @ Kernels { kg kr ok }
}

@ ops_free Kernels ks → v {
    ( gpu_kernel_free . ks gemm )
    ( gpu_kernel_free . ks relu )
}

// Gemm: A is M×K, B is K×N (transB=0) or N×K (transB=1), C is the length-N
// bias (cdptr=0 for none), Y is M×N. dptrs are raw device addresses (i64).
// Returns Y's device address (caller allocated it).
@ op_gemm Gpu g Kernels ks i adptr i bdptr i cdptr i ydptr i M i N i K f alpha f beta i transB → i {
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_i64 adptr ) )
    ( vec_push [i] args ( gpu_arg_i64 bdptr ) )
    ( vec_push [i] args ( gpu_arg_i64 cdptr ) )
    ( vec_push [i] args ( gpu_arg_i64 ydptr ) )
    ( vec_push [i] args ( gpu_arg_i32 M ) )
    ( vec_push [i] args ( gpu_arg_i32 N ) )
    ( vec_push [i] args ( gpu_arg_i32 K ) )
    ( vec_push [i] args ( gpu_arg_f32 alpha ) )
    ( vec_push [i] args ( gpu_arg_f32 beta ) )
    ( vec_push [i] args ( gpu_arg_i32 transB ) )
    : i total * M N
    : i block 256
    ( gpu_launch . ks gemm ( gpu_grid total block ) block args )
    ( vec_free [i] args )
    ^ ydptr
}

// Relu: Y = max(0, X), elementwise over n elements.
@ op_relu Gpu g Kernels ks i xdptr i ydptr i n → i {
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_i64 xdptr ) )
    ( vec_push [i] args ( gpu_arg_i64 ydptr ) )
    ( vec_push [i] args ( gpu_arg_i32 n ) )
    : i block 256
    ( gpu_launch . ks relu ( gpu_grid n block ) block args )
    ( vec_free [i] args )
    ^ ydptr
}
