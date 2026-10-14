$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// Compiling and launching kernel source: the caller vouches for the code
// and for every address it indexes.
@ main → i {
    : Gpu g ( gpu_open 0 )
    : GpuKernel k ( gpu_compile g `extern "C" __global__ void w(long long p){ *(int*)p = 1; }` `w` )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 4096 )
    ^ ( gpu_launch k 1 1 a )
}
