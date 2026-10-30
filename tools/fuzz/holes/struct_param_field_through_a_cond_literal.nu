// struct_param_field_through_a_cond_literal: agora #178 — a struct parameter's field handed back through a `?`, the argument a literal (struct_param_field_through_a_cond_literal).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h701 | agora #178: a struct parameter's field handed back through a `?`, the argument a literal
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part P p b c → String { ^ ? c . p s ( mk ) }

@ main → i {
    : String t ( part @ P { ( mk ) 1 } T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
