// dtor_disposer_leaks_fields: a `% Drop` impl that hands its receiver to a `sink` disposer leaks the receiver's fields.
// Closed: a disposer's parameter is released by its drop glue — the impl's fields, not the impl again (mem_emit_gated_drop's selector).
// Res's impl passes `r` to res_close, a `sink Res` function that only prints. A `sink` parameter whose
// type has a `% Drop` impl is not dropped by its callee (that would run the impl again), and nothing
// drops the value's fields in its place, so the String `name` is never released.
// LSan: detected memory leaks — the String (24-byte control block from string_from, and its buffer).
// map: §7.6 | A2 | runs-clean | h147 | Drop impl hands receiver to sink disposer; fields leak
$ `stdlib/core/string.nu`

: Res { String name i id }

@ res_close sink Res r → v { ( nurl_println `close` ) }

% Drop Res { @ drop sink Res r → v { ( res_close r ) } }

@ main → i {
    : Res r @ Res { ( string_from `r` ) 1 }
    ( nurl_println `ran` )
    ^ 0
}
