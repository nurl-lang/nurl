$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// A device-to-device copy from any address.
@ main → i {
    : Gpu g ( gpu_open 0 )
    : GpuBuffer b ( gpu_alloc g 64 )
    ^ ( gpu_dtod b 4096 )
}
