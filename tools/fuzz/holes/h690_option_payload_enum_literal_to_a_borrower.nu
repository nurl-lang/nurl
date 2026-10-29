// H690: agora #177 — an enum literal with an option payload handed to a callee that borrows it (option_payload_enum_literal_to_a_borrower).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: ran clean. main after github#1306: LeakSanitizer (the payload box and its String).
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ show E e → i { ^ ?? e { Opt o → ?? o { T s → ( string_len s ) F → 0 } S s → ( string_len s ) NoVal → -1 } }

@ main → i {
    ( nurl_println_int ( show @ E { Opt @ ?String { T ( mk ) } } ) )
    ^ 0
}
