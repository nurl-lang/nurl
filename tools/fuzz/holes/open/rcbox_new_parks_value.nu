// OPEN in 0.72.0 — rcbox_new is callable from safe code and parks its value behind a plain `i` nothing releases.
// ( rcbox_new [Kept] … ) moves the Kept (and its String) into an rc block and returns the block's address
// as an integer; an `i` owns nothing, so the block and the String inside are never released —
// mem_forget under another name. The rcbox primitives are `unsafe`-only (§3.3d).
// LSan: detected memory leaks — the 16-byte block, and the String's control block and buffer inside it.
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

: Kept { String text }

@ main → i {
    : i addr ( rcbox_new [Kept] @ Kept { ( string_from `kept` ) } )
    ( nurl_print_int addr ) ( nurl_println ` ran` )
    ^ 0
}
