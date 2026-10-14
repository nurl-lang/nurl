$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// RUNS: an index past a host buffer panics instead of writing past it.
@ main → i {
    : GpuHost h ( gpu_host_alloc 16 )
    ( gpu_host_set_f32 h 4 1.0 )
    ^ 0
}
