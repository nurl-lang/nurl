// closure_returned_from_an_arm_over_a_payload: agora #463 — `^ ?? oo { T inner → \ → i { ?? inner { … } } F → … }`
// Closed: a closure literal returned as an arm value copies in the payload cursor it captures (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ ?? oo { T inner → \ → i { ?? inner { … } } F → … }`
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : ?? String oo @ ?? String { T @ ?String { T ( string_from `an inner option value long enough for the heap` ) } }
    ^ ?? oo { T inner → \ → i { ?? inner { T s → { ^ ( string_len s ) } F → { ^ 1 } } } F → \ → i { ^ 0 } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
