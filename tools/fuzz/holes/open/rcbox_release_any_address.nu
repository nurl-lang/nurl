// OPEN in 0.72.0 — rcbox_release is callable from safe code and releases whatever `i` it is handed.
// main releases the block rcbox_new returned twice: the second call reads the count of a freed block.
// Any integer — an address that was never a block — is released the same way. The rcbox primitives
// are `unsafe`-only (§3.3d).
// ASan: heap-use-after-free in nurl_rc_release (runtime_core.c), on the block the first call freed.
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

: Kept { String text }

@ main → i {
    : i addr ( rcbox_new [Kept] @ Kept { ( string_from `kept` ) } )
    ( rcbox_release [Kept] addr )
    ( rcbox_release [Kept] addr )
    ( nurl_println `ran` )
    ^ 0
}
