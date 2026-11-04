// closure_returned_as_an_arm_over_an_inout_parameter_payload: agora #463 — `@ cap inout ?String o → ( @ i ) { ^ ?? o { T s → \ → i { … s … } … } }`
// Closed: the same over a payload of an `inout` parameter: copied in, and the caller still releases its option (agora #463).
// main: ran clean (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `@ cap inout ?String o → ( @ i ) { ^ ?? o { T s → \ → i { … s … } … } }`
$ `stdlib/core/string.nu`

@ cap inout ? String o → ( @ i ) {
    ^ ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
}

@ main → i {
    : ~ ? String x @ ?String { T ( string_from `a caller option value long enough for the heap` ) }
    : ( @ i ) c ( cap x )
    ( nurl_println_int ( c ) )
    ?? x { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
