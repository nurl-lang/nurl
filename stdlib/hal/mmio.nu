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
// IMPORTANT — no `volatile` in NURL (yet). At -O2 the optimizer may hoist a
// read out of a polling loop (LICM), so anything that *spins on* an MMIO
// read (UART FIFO status, etc.) must be compiled at -O0/-O1. Plain one-shot
// reads/writes are fine at any optimization level. See examples/esp32.

@ mmio_read32 i addr → i {
    : *i32 p # *i32 addr
    ^ # i . p 0
}

@ mmio_write32 i addr i32 val → v {
    : *i32 p # *i32 addr
    = . p 0 val
}

@ mmio_set32 i addr i32 mask → v {
    : *i32 p # *i32 addr
    = . p 0 # i32 | # i . p 0 # i mask
}

@ mmio_clear32 i addr i32 mask → v {
    : *i32 p # *i32 addr
    = . p 0 # i32 & # i . p 0 ~ # i mask
}
