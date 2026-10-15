// diag_raw_mmio_address.nu — mmio_write32 writes wherever the number it
// is given points: only unsafe code may call it.

$ `stdlib/hal/mmio.nu`

@ main → i {
    ( mmio_write32 4096 0 1 )
    ^ 0
}
