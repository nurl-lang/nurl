$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// A view of a host buffer used after the buffer was let go.
@ main → i {
    : GpuHost h ( gpu_host_alloc 64 )
    : ( Slice u ) s ( gpu_host_u8 h )
    ( gpu_host_free h )
    ^ # i ( slice_at [u] s 3 )
}
