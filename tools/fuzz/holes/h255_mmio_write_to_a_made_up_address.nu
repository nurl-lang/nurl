// H255: safe code wrote through mmio_write32 (stdlib/hal/mmio.nu) to a made-up address: the HAL casts its integer to a pointer and stores there.
// Closed: the HAL functions over a physical address (mmio_*, virtio_* over a register block, virtq_desc_set / virtq_add_single, which hand an address to the device) are `unsafe` only.
// main's compiler: AddressSanitizer: SEGV on a wild write.
$ `stdlib/hal/mmio.nu`

@ main → i {
    ( mmio_write32 123456789 # i32 7 )
    ( nurl_println `survived` )
    ^ 0
}
