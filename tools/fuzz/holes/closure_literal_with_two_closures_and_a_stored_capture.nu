// closure_literal_with_two_closures_and_a_stored_capture: agora #463 — `^ @ H { \ → i { ^ … x … } \ → i { … x … } x }`
// Closed: a `^` inside the first closure's body no longer hides the returned literal from the second: both copy the capture the literal stores (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ @ H { \ → i { ^ … x … } \ → i { … x … } x }`
$ `stdlib/core/string.nu`

: H2 { ( @ i ) f ( @ i ) g String o }

@ cap → H2 {
    : String x ( string_from `a String local long enough for the heap` )
    ^ @ H2 { \ → i { ^ ( string_len x ) } \ → i { ^ + 1 ( string_len x ) } x }
}

@ main → i {
    : H2 h ( cap )
    : ( @ i ) f . h f
    : ( @ i ) g . h g
    ( nurl_println_int ( f ) )
    ( nurl_println_int ( g ) )
    ( nurl_println ( string_data . h o ) )
    ^ 0
}
