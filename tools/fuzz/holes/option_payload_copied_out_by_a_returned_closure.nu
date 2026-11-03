// option_payload_copied_out_by_a_returned_closure: agora #458 — a returned closure over a local option that copies its payload into a sink, called twice
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a returned closure over a local option that copies its payload into a sink, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ cap → ( @ i ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ \ → i { ?? x { T s → { ^ ( eat ( string_from ( string_data s ) ) ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
