// struct_payload_enum_literal_to_a_borrower: agora #177 — an enum literal with a boxed struct payload handed to a borrowing callee (struct_payload_enum_literal_to_a_borrower).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h691 | agora #177: an enum literal with a boxed struct payload handed to a borrowing callee
$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    V P
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ show E e → i { ^ ?? e { V p → ( string_len . p s ) NoVal → -1 } }

@ main → i {
    ( nurl_println_int ( show @ E { V @ P { ( mk ) 1 } } ) )
    ^ 0
}
