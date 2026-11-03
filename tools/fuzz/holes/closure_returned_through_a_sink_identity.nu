// closure_returned_through_a_sink_identity: agora #463 — `@ idc sink ( @ i ) f → ( @ i ) { ^ f }  ^ ( idc \ → i { … x … } )`
// Closed: an argument a callee hands back as it is (`^ p` of a `sink` parameter, g_fn_ret_param) is that closure: the result holds the copies of the handles it holds (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `@ idc sink ( @ i ) f → ( @ i ) { ^ f }  ^ ( idc \ → i { … x … } )`
$ `stdlib/core/string.nu`

@ idc sink ( @ i ) f → ( @ i ) { ^ f }

@ cap → ( @ i ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ ( idc \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } )
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
