// H694: agora #177 — an enum literal that cannot be copied, handed back by its callee (enum_literal_handed_back_whole).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    Opt ? String
    S String
    Cb ( @ i )
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ show E e → i { ^ ?? e { Opt o → ?? o { T s → ( string_len s ) F → 0 } S s → ( string_len s ) Cb f → ( f ) NoVal → -1 } }

@ pass E e → E { ^ e }

@ main → i {
    : E r ( pass @ E { Opt @ ?String { T ( mk ) } } )
    ( nurl_println_int ( show r ) )
    ^ 0
}
