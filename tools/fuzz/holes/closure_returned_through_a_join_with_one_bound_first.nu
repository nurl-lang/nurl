// closure_returned_through_a_join_with_one_bound_first: agora #463 — `: ( @ i ) b \ → i { … y … }  ^ ? == k 0 \ → i { … x … } b`
// Closed: a join of closures handed back is checked by what its arms hold: a closure bound first holds a copy of the handle of `y`, which the function releases (h310) (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `: ( @ i ) b \ → i { … y … }  ^ ? == k 0 \ → i { … x … } b`
$ `stdlib/core/string.nu`

@ cap i k → ( @ i ) {
    : String x ( string_from `a local value long enough for the heap` )
    : String y ( string_from `another local value long enough for the heap` )
    : ( @ i ) b \ → i { ^ ( string_len y ) }
    ^ ? == k 0 \ → i { ^ ( string_len x ) } b
}

@ main → i {
    : ( @ i ) c ( cap 0 )
    : ( @ i ) d ( cap 1 )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( d ) )
    ^ 0
}
