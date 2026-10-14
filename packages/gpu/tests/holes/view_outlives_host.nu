$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// A view of a host buffer returned past the buffer's owner.
@ mk → ( Slice f32 ) {
    : GpuHost h ( gpu_host_alloc 64 )
    ^ ( gpu_host_f32 h )
}

@ main → i {
    : ( Slice f32 ) s ( mk )
    ^ # i ( slice_at [f32] s 3 )
}
