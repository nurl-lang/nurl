// option_captured_by_a_closure_returned_from_a_closure: agora #458 — `^ \ → ( @ i ) { ^ \ → i { ?? x { … } } }` over a local option
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: `^ \ → ( @ i ) { ^ \ → i { ?? x { … } } }` over a local option
$ `stdlib/core/string.nu`

@ cap → ( @ ( @ i ) ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ \ → ( @ i ) { ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } }
}

@ main → i {
    : ( @ ( @ i ) ) c ( cap )
    : ( @ i ) d ( c )
    ( nurl_println_int ( d ) )
    ^ 0
}
