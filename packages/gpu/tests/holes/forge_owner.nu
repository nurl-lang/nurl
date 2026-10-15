$ `stdlib/core/io.nu`
$ `src/gpu.nu`
// An owner that would free an address it never allocated on its drop.
@ main → i {
    : Gpu g ( gpu_open 0 )
    : ?GpuRes r ( __gpu_res g GPU_RES_MEM 4096 )
    ^ 0
}
