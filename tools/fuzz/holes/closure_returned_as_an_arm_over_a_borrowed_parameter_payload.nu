// closure_returned_as_an_arm_over_a_borrowed_parameter_payload: agora #463 — `@ cap ?String o → ( @ i ) { ^ ?? o { T s → \ → i { … s … } F → … } }` called with a struct's field
// Closed: a closure returned as an arm value over a payload of a parameter the function only borrows copies the payload into its environment; the parameter stays the caller's (agora #463).
// main: ran clean (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `@ cap ?String o → ( @ i ) { ^ ?? o { T s → \ → i { … s … } F → … } }` called with a struct's field
$ `stdlib/core/string.nu`

: H { ? String o i n }

@ cap ? String o → ( @ i ) {
    ^ ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
}

@ main → i {
    : H h @ H { @ ?String { T ( string_from `a field option value long enough for the heap` ) } 3 }
    : ( @ i ) c ( cap . h o )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ( nurl_println_int . h n )
    ^ 0
}
