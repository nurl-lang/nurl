// drop_field_getter_fall_off: agora #187 — the same call as the function's fall-off value (drop_field_getter_fall_off).
// Closed: A value that cannot be copied, handed back from a call that may lend it out of an argument this frame owns (a local, a `sink` parameter), is refused at module end on the callee's final summary — there is nothing to copy (__park_nc_local_lend / resolve_nc_local_lends; agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h819 | agora #187: the same call as the function's fall-off value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: W { D d }

@ getd W w → D { ^ . w d }

@ mk → D { ^ @ D { ( string_from `element string long enough for a heap buffer` ) } }

@ pick → D {
    : W w @ W { ( mk ) }
    ( getd w )
}

@ main → i {
    : D a ( pick )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
