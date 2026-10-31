// rcbox_new_parks_value: rcbox_new is callable from safe code and parks its value behind a plain `i` nothing releases.
// Closed: the rcbox primitives are `unsafe`-only (bck_raw_call); a program's own handle over them has an `unsafe` drop hook and is sealed.
// ( rcbox_new [Kept] … ) moves the Kept (and its String) into an rc block and returns the block's address
// as an integer; an `i` owns nothing, so the block and the String inside are never released —
// mem_forget under another name. The rcbox primitives are `unsafe`-only (§3.3d).
// LSan: detected memory leaks — the 16-byte block, and the String's control block and buffer inside it.
// map: §3 | B | rejected | h159 | rcbox_new in safe code parks value behind plain i (leak)
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

: Kept { String text }

@ main → i {
    : i addr ( rcbox_new [Kept] @ Kept { ( string_from `kept` ) } )
    ( nurl_print_int addr ) ( nurl_println ` ran` )
    ^ 0
}
