// closure_returned_from_a_statement_arm_over_a_borrowed_parameter_payload: agora #463 — `?? o { T s → { ^ \ → i { … s … } } F → … }` with `o` a borrowed parameter
// Closed: a closure returned from inside an arm over a payload of a borrowed parameter copies the payload in (it took it over, and its caller released the field again) (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `?? o { T s → { ^ \ → i { … s … } } F → … }` with `o` a borrowed parameter
$ `stdlib/core/string.nu`

: H { ? String o i n }

@ cap ? String o → ( @ i ) {
    ?? o { T s → { ^ \ → i { ^ ( string_len s ) } } F → {} }
    ^ \ → i { ^ 0 }
}

@ main → i {
    : H h @ H { @ ?String { T ( string_from `a field option value long enough for the heap` ) } 3 }
    : ( @ i ) c ( cap . h o )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ( nurl_println_int . h n )
    ^ 0
}
