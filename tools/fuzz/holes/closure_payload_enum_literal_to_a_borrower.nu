// closure_payload_enum_literal_to_a_borrower: agora #177 — an enum literal with a closure payload handed to a borrowing callee (closure_payload_enum_literal_to_a_borrower).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free. main: LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h692 | agora #177: an enum literal with a closure payload handed to a borrowing callee
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
    : i v 41
    ( nurl_println_int ( show @ E { Cb \ → i { ^ + v 1 } } ) )
    ^ 0
}
