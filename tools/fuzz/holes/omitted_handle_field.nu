// omitted_handle_field: a struct literal that leaves an ( Rc i ) field out zero-initialises it: rc_get read the value at offset 24 of a null block.
// Closed: as h180 — a library handle's zero is not a handle, so the field must be given outside `unsafe`.
// ASan: SEGV in rc_get (main).
// map: §6.2 | B | rejected | h181 | struct literal omits Rc field: zero handle, rc_get reads null block
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: Holder { i n ( Rc i ) r }

@ main → i {
    : Holder h @ Holder { 5 }
    ( nurl_println_int ( rc_get [i] . h r ) )
    ^ 0
}
