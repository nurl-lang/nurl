// stdlib/hal/blockdev.nu — the seam a filesystem sits on: a numbered
// array of 512-byte sectors, and nothing else.
//
// WHY IT IS SPELLED AS FFI. The four `nurl_blk_*` symbols below are
// DECLARED here and DEFINED by whichever provider the build links —
// `stdlib/fs/blkdev_file.nu` on a host, `unikernel/fs/blkdev_virtio.nu`
// in a guest, `unikernel/fs/blkdev_none.nu` in a guest with no disk.
// That is the same trick `stdlib/std/net.nu` plays with `nurl_tcp_*`
// and `unikernel/net/sockets.nu` answers: a NURL definition supersedes
// an FFI declaration of the same name, so the layer above compiles on
// its own and the machine underneath is chosen at link time rather
// than by a conditional.
//
// WIDTHS. Every one of them returns `i` — 64 bits — because a provider
// written in C returning `int` would have its negative answers read
// through a register whose top half a `movl` had just zeroed, which is
// the bug class that made the guest read `-1` as 4294967295 and take a
// refusal for a success. A C provider must return `long long`.
//
// SECTORS ARE 512 BYTES, always. That is not a simplification of
// virtio: the virtio-blk request unit IS 512 bytes regardless of what
// the device reports as its logical block size (spec 1.1 §5.2.6), and
// a host file is whatever we say it is. A filesystem whose own idea of
// a sector differs says so and refuses to mount rather than reading
// every structure at the wrong offset.
$ `stdlib/core/vec.nu`

& `libc` @ nurl_blk_sector_count → i

& `libc` @ nurl_blk_read i lba s buf i nsec → i

& `libc` @ nurl_blk_write i lba s buf i nsec → i

& `libc` @ nurl_blk_flush → i

@ blk_sector_size → i { ^ 512 }

// How many sectors the device has; 0 means there is no device, which
// is a fact about the machine rather than an error.
@ blk_sector_count → i {
    : i n ( nurl_blk_sector_count )
    ^ ? < n 0 0 n
}

@ blk_present → b { ^ > ( blk_sector_count ) 0 }

// The three calls below take a byte offset INTO a Vec rather than a
// bare pointer, so the bounds check happens once, here, instead of at
// every caller — and a caller that got it wrong reads a refusal rather
// than the allocator's neighbouring bytes.
@ __blk_ptr ( Vec u ) buf i off i nbytes → i {
    ? < off 0 { ^ 0 } {}
    ? < nbytes 0 { ^ 0 } {}
    ? > + off nbytes ( vec_len [u] buf ) { ^ 0 } {}
    ^ + # i ( vec_data [u] buf ) off
}

@ __blk_range_ok i lba i nsec → b {
    ? < lba 0 { ^ F } {}
    ? <= nsec 0 { ^ F } {}
    : i cap ( blk_sector_count )
    ? == cap 0 { ^ F } {}
    ? > + lba nsec cap { ^ F } {}
    ^ T
}

@ blk_read ( Vec u ) buf i off i lba i nsec → b {
    : i p ( __blk_ptr buf off * nsec ( blk_sector_size ) )
    ? == p 0 { ^ F } {}
    ^ ( blk_read_raw # s p lba nsec )
}

@ blk_write ( Vec u ) buf i off i lba i nsec → b {
    : i p ( __blk_ptr buf off * nsec ( blk_sector_size ) )
    ? == p 0 { ^ F } {}
    ^ ( blk_write_raw # s p lba nsec )
}

// The same two, straight at a pointer. A filesystem transferring whole
// sectors into a caller's buffer has nowhere to put a Vec, and copying
// through one would double every byte of every read.
@ blk_read_raw s buf i lba i nsec → b {
    ? ! ( __blk_range_ok lba nsec ) { ^ F } {}
    ^ == ( nurl_blk_read lba buf nsec ) nsec
}

@ blk_write_raw s buf i lba i nsec → b {
    ? ! ( __blk_range_ok lba nsec ) { ^ F } {}
    ^ == ( nurl_blk_write lba buf nsec ) nsec
}

// Everything written is on the medium when this returns true. A
// provider that cannot promise that must answer false rather than
// zero-with-a-shrug: `fsync` returning success is the one lie a
// write-ahead log cannot survive.
@ blk_flush → b { ^ == ( nurl_blk_flush ) 0 }
