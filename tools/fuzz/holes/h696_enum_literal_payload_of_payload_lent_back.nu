// H696: agora #177 — an enum literal whose callee lends back its payload's payload (enum_literal_payload_of_payload_lent_back).
// Closed: an enum literal argument owning all it holds is dropped whole after the call, its boxes freed otherwise; one lent back in part, or that cannot be copied, goes with the result (gen_agg_lit, mem_arg_temps, mem_note_payload_part; agora #177).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free. main: LeakSanitizer.
$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | E {
    Str ? String
    Opt ? D
    NoVal
}

@ inner E e → String { ^ ?? e { Str o → ?? o { T s → s F → ( mk ) } Opt p → ( mk ) NoVal → ( mk ) } }

@ main → i {
    : String t ( inner @ E { Str @ ?String { T ( mk ) } } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
