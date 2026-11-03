// closure_returned_through_a_generic_identity: agora #463 — `@ idc [A] sink A f → A { ^ f }  ^ ( idc [( @ i )] \ → i { … x … } )`
// Closed: a generic identity over a `sink` parameter hands back the closure it was given, with the copies of the handles it holds (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `@ idc [A] sink A f → A { ^ f }  ^ ( idc [( @ i )] \ → i { … x … } )`
$ `stdlib/core/string.nu`

@ idc [A] sink A f → A { ^ f }

@ cap → ( @ i ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ ( idc [( @ i )] \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } )
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
