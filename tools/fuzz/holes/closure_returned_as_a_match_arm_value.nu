// closure_returned_as_a_match_arm_value: agora #463 — `^ ?? k { T n → \ → i { … x … } F → \ → i { ^ 0 } }`
// Closed: a closure literal written as an arm value of a `??` the return hands back is returned right here (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ ?? k { T n → \ → i { … x … } F → \ → i { ^ 0 } }`
$ `stdlib/core/string.nu`

@ cap ? i k → ( @ i ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ ?? k { T n → \ → i { ?? x { T s → { ^ + n ( string_len s ) } F → { ^ 0 } } } F → \ → i { ^ 0 } }
}

@ main → i {
    : ( @ i ) c ( cap @ ?i { T 2 } )
    ( nurl_println_int ( c ) )
    ^ 0
}
