// closure_stored_by_a_sink_parameter_into_a_returned_literal_runs_clean: agora #463 — `@ wrap sink ( @ i ) f → H { ^ @ H { f } }  ^ ( wrap \ → i { … x … } )`
// Closed: guard: a callee that stores its `sink` closure into a literal it returns adopts it (the literal owns a copy), so the result holds no copy of a handle of the caller's local (agora #463).
// main: ran clean (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `@ wrap sink ( @ i ) f → H { ^ @ H { f } }  ^ ( wrap \ → i { … x … } )`
$ `stdlib/core/string.nu`

: H { ( @ i ) f }

@ wrap sink ( @ i ) f → H { ^ @ H { f } }

@ cap → H {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( wrap \ → i { ^ ( string_len x ) } )
}

@ main → i {
    : H h ( cap )
    : ( @ i ) f . h f
    ( nurl_println_int ( f ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
