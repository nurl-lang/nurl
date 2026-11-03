// option_captured_by_a_closure_returned_in_a_struct: agora #458 — `^ @ Holder { \ → i { ?? x { … } } }` over a local option
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: `^ @ Holder { \ → i { ?? x { … } } }` over a local option
$ `stdlib/core/string.nu`

: Holder { ( @ i ) f }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ cap → Holder {
    : ?String x ( mk `a local value long enough for the heap` )
    ^ @ Holder { \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } }
}

@ main → i {
    : Holder h ( cap )
    : ( @ i ) f . h f
    ( nurl_println_int ( f ) )
    ^ 0
}
