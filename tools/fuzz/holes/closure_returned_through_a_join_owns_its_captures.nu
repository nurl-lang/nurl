// closure_returned_through_a_join_owns_its_captures: agora #463 — `^ ? == k 0 \ → i { … x … } \ → i { … y … }` over local options
// Closed: a closure literal written as an arm of a `?` the return hands back is returned right here, as `^ \ …` is: its environment owns its captures (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ ? == k 0 \ → i { … x … } \ → i { … y … }` over local options
$ `stdlib/core/string.nu`

@ cap i k → ( @ i ) {
    : ?String x @ ?String { T ( string_from `a local value long enough for the heap` ) }
    : ?String y @ ?String { T ( string_from `another local value long enough for the heap` ) }
    ^ ? == k 0 \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } \ → i { ?? y { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap 0 )
    : ( @ i ) d ( cap 1 )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( d ) )
    ^ 0
}
