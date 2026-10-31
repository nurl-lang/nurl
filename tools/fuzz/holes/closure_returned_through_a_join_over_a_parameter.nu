// closure_returned_through_a_join_over_a_parameter: a closure returned through a join of closure literals (`^ ? c \ → v { … s … } \ → v { … }`), over a String parameter, outlived the caller's argument: only a literal written straight in the `^` was summarised.
// Closed: as h384 — the join's source expression names the arms' captures (agora #141).
// v0.79.1: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h386 | as h384, through a join of closure literals in the ^
$ `stdlib/core/string.nu`

@ mk String s → ( @ v ) { ^ ? > ( string_len s ) 3 \ → v { ( nurl_println ( string_data s ) ) } \ → v { ( nurl_println `short` ) } }

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( mk t )
    ( string_free t )
    ( g )
    ^ 0
}
