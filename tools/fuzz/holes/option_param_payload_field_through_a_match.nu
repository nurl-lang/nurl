// option_param_payload_field_through_a_match: agora #178 — a field of an option parameter's payload handed back through a `??` arm, the argument a literal (option_param_payload_field_through_a_match).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h707 | agora #178: a field of an option parameter's payload handed back through a `??` arm, the argument a literal
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part ? P o → String { ^ ?? o { T p → . p s F → ( mk ) } }

@ main → i {
    : String t ( part @ ?P { T @ P { ( mk ) 1 } } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
