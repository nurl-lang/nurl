// closure_in_a_returned_literal_that_also_stores_its_capture: agora #463 — `^ @ H { \ → i { … x … } x }` with `x` a String
// Closed: a capture the returned literal also stores after the closure is copied into the environment; the field takes the binding's value (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ @ H { \ → i { … x … } x }` with `x` a String
$ `stdlib/core/string.nu`

: H { ( @ i ) f String o }

@ cap → H {
    : String x ( string_from `a String local long enough for the heap` )
    ^ @ H { \ → i { ^ ( string_len x ) } x }
}

@ main → i {
    : H h ( cap )
    : ( @ i ) f . h f
    ( nurl_println_int ( f ) )
    ( nurl_println ( string_data . h o ) )
    ^ 0
}
