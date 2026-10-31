// enum_literal_to_a_borrower_in_a_loop: agora #177 — an enum literal with an option payload handed to a borrower in a loop (enum_literal_to_a_borrower_in_a_loop).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: ran clean. main after github#1306: LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h695 | agora #177: an enum literal with an option payload handed to a borrower in a loop
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
    : ~ i n 0
    : ~ i acc 0
    ~ < n 50 {
        = acc + acc ( show @ E { Opt @ ?String { T ( mk ) } } )
        = n + n 1
    }
    ( nurl_println_int acc )
    ^ 0
}
