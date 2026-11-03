// option_captured_by_a_returned_closure_then_copied: agora #458 — a returned closure over a local option, copied (`: ( @ i ) d c`) and both called
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a returned closure over a local option, copied (`: ( @ i ) d c`) and both called
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ cap → ( @ i ) {
    : ?String x ( mk `a local value long enough for the heap` )
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    : ( @ i ) d c
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( d ) )
    ^ 0
}
