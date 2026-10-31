// binding_payload_enum_literal_to_a_borrower: agora #177 — an enum literal holding bindings' values handed to a borrowing callee (binding_payload_enum_literal_to_a_borrower).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: ran clean. main after github#1306: LeakSanitizer (the payload boxes).
// map: §7.6 | A2 | runs-clean | h693 | agora #177: an enum literal holding bindings' values handed to a borrowing callee
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

@ main → i {
    : String s ( mk )
    : ?String o @ ?String { T ( mk ) }
    ( nurl_println_int ( show @ E { S s } ) )
    ( nurl_println_int ( show @ E { Opt o } ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
