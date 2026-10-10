// OPEN in 0.72.0 — a program's own rcbox handle lets safe code release an address of its choosing as a block.
// Kept's drop hook (`Kept_drop`, the old handle convention) forgets its receiver and passes `. h ctl` to
// rcbox_release; nothing stops main from building @ Kept { ( string_data s ) } over a String's buffer,
// so at scope exit the hook releases that buffer as an rc block. mem_forget and rcbox_release are
// `unsafe`-only (§3.3d), but both are accepted in this safe hook.
// ASan: heap-use-after-free in nurl_rc_release, on the buffer nurl_vec_drop had released for `s`.
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

: KeptImpl { String text }
: Kept { s ctl }

@ Kept_drop sink Kept h → v { ( mem_forget h ) ( rcbox_release [KeptImpl] # i . h ctl ) }

@ main → i {
    : String s ( string_from `not a block` )
    : Kept k @ Kept { ( string_data s ) }
    ( nurl_println `ran` )
    ^ 0
}
