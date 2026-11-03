// none_or_some_option_captured_by_a_returned_closure: agora #458 — a local option, None on one run and Some on the other, captured by a returned closure
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a local option, None on one run and Some on the other, captured by a returned closure
$ `stdlib/core/string.nu`

@ cap i k → ( @ i ) {
    : ?String x ? == k 0 @ ?String { F } @ ?String { T ( string_from `a local value long enough for the heap` ) }
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) a ( cap 0 )
    : ( @ i ) b ( cap 1 )
    ( nurl_println_int ( a ) )
    ( nurl_println_int ( b ) )
    ^ 0
}
