$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// A device buffer conjured from a number: safe code may not build one.
@ main → i {
    : GpuBuffer b @ GpuBuffer { 4096 1048576 ( __gpu_nores ) }
    ^ . b bytes
}
