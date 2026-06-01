// stdlib/hal/mmio.nu — memory-mapped I/O primitives.
//
// The whole of an MMIO peripheral driver is "read/write a 32-bit word at a
// fixed physical address". NURL pointers express that directly: cast an
// integer address to `*i32` and load/store element 0.
//
// API:
//   ( mmio_read32   i addr )          → i      load  *(u32*)addr (zero-ish widened to i64)
//   ( mmio_write32  i addr i32 val )  → v      store *(u32*)addr = val
//   ( mmio_set32    i addr i32 mask ) → v      *(u32*)addr |= mask
//   ( mmio_clear32  i addr i32 mask ) → v      *(u32*)addr &= ~mask
//
// VOLATILE — these use the compiler's `volatile_load` / `volatile_store`
// intrinsics, which emit `load volatile` / `store volatile`. The optimizer
// therefore never hoists an MMIO read out of a polling loop (LICM),
// reorders the accesses, or coalesces repeated reads/writes. Spinning on a
// device status register (UART FIFO, etc.) is now correct at ANY
// optimization level — the former -O0 workaround is no longer needed. Pure
// IR, no runtime call, so this works on a freestanding target.

@ mmio_read32 i addr → i {
    : *i32 p # *i32 addr
    ^ # i ( volatile_load p )
}

@ mmio_write32 i addr i32 val → v {
    : *i32 p # *i32 addr
    ( volatile_store p val )
}

@ mmio_set32 i addr i32 mask → v {
    : *i32 p # *i32 addr
    ( volatile_store p # i32 | # i ( volatile_load p ) # i mask )
}

@ mmio_clear32 i addr i32 mask → v {
    : *i32 p # *i32 addr
    ( volatile_store p # i32 & # i ( volatile_load p ) ~ # i mask )
}
