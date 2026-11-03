// option_local_captured_by_a_returned_closure: agora #458 — `: ?String x ( mk … )  ^ \ → i { ?? x { … } }`
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: `: ?String x ( mk … )  ^ \ → i { ?? x { … } }`
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ cap → ( @ i ) {
    : ?String x ( mk `a local value long enough for the heap` )
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
