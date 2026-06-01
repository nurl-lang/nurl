// volatile_mmio.nu — exercises the volatile MMIO HAL (stdlib/hal/mmio.nu),
// which is built on the compiler's `volatile_load` / `volatile_store`
// intrinsics (emit `load volatile` / `store volatile`).
//
// Here the "device register" is just a heap word, so the read/write/
// set/clear round-trip is fully deterministic and runs on the host. The
// point of `volatile` — that the optimizer must not hoist an MMIO read
// out of a polling loop at -O2 — is verified structurally elsewhere
// (the load stays inside the loop in the optimized IR); this test pins
// the functional read-modify-write semantics.

$ `stdlib/core/string.nu`
$ `stdlib/hal/mmio.nu`

@ main → i {
    : i reg # i ( nurl_alloc 8 )

    ( mmio_write32 reg # i32 0x1234 )
    ( nurl_print `w=` ) ( nurl_print ( nurl_str_int ( mmio_read32 reg ) ) ) ( nurl_print `\n` )

    ( mmio_set32 reg # i32 0x0F00 )
    ( nurl_print `set=` ) ( nurl_print ( nurl_str_int ( mmio_read32 reg ) ) ) ( nurl_print `\n` )

    ( mmio_clear32 reg # i32 0x00FF )
    ( nurl_print `clr=` ) ( nurl_print ( nurl_str_int ( mmio_read32 reg ) ) ) ( nurl_print `\n` )

    ( nurl_free # s reg )
    ^ 0
}
