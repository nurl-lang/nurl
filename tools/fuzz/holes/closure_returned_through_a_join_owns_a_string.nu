// closure_returned_through_a_join_owns_a_string: agora #463 — `^ ? == k 0 \ → i { … x … } \ → i { … y … }` over local Strings
// Closed: a closure literal written as an arm of a `?` the return hands back moves its String captures into its environment (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ ? == k 0 \ → i { … x … } \ → i { … y … }` over local Strings
$ `stdlib/core/string.nu`

@ cap i k → ( @ i ) {
    : String x ( string_from `a local value long enough for the heap` )
    : String y ( string_from `another local value long enough for the heap` )
    ^ ? == k 0 \ → i { ^ ( string_len x ) } \ → i { ^ ( string_len y ) }
}

@ main → i {
    : ( @ i ) c ( cap 0 )
    : ( @ i ) d ( cap 1 )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( d ) )
    ^ 0
}
