// dtor_skipped_when_handed_to_disposer: a value whose type has a `% Drop` impl, handed to a `sink` function, is released by neither.
// Closed: a disposer's parameter is released by its drop glue — the impl's fields, not the impl again (mem_emit_gated_drop's selector).
// `b` goes straight to res_close (the `sink Res` function the impl itself calls): the impl never runs
// for `b` (no "DROP IMPL b-direct" in the output) and res_close does not drop it either. `a` takes the
// dtor_disposer_leaks_fields path: its impl runs and hands it to res_close, which leaks its fields too.
// (Without the `% Drop` impl, res_close drops its parameter and the same calls run clean.)
// LSan: detected memory leaks — two Strings (2 x 24-byte control blocks from string_from, 2 buffers).
// map: §7.6 | A2 | runs-clean | h150 | Drop-typed value passed to sink fn released by neither
$ `stdlib/core/string.nu`

: Res { String name }

@ res_close sink Res r → v { ( nurl_println ( nurl_str_cat `close ` ( string_data . r name ) ) ) }

% Drop Res { @ drop sink Res r → v {
        ( nurl_println ( nurl_str_cat `DROP IMPL ` ( string_data . r name ) ) )
        ( res_close r )
    } }

@ main → i {
    : Res a @ Res { ( string_from `a-scope-exit` ) }
    : Res b @ Res { ( string_from `b-direct` ) }
    ( res_close b )
    ( nurl_println `ran` )
    ^ 0
}
