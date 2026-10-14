$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// A view of any address: gpu_buffer_view is raw.
@ main → i {
    : GpuBuffer b ( gpu_buffer_view 4096 1048576 )
    ^ . b bytes
}
