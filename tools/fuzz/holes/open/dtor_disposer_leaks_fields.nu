// OPEN in 0.72.0 — a `% Drop` impl that hands its receiver to a `sink` disposer leaks the receiver's fields.
// Res's impl passes `r` to res_close, a `sink Res` function that only prints. A `sink` parameter whose
// type has a `% Drop` impl is not dropped by its callee (that would run the impl again), and nothing
// drops the value's fields in its place, so the String `name` is never released.
// LSan: detected memory leaks — the String (24-byte control block from string_from, and its buffer).
$ `stdlib/core/string.nu`

: Res { String name i id }

@ res_close sink Res r → v { ( nurl_println `close` ) }

% Drop Res { @ drop sink Res r → v { ( res_close r ) } }

@ main → i {
    : Res r @ Res { ( string_from `r` ) 1 }
    ( nurl_println `ran` )
    ^ 0
}
