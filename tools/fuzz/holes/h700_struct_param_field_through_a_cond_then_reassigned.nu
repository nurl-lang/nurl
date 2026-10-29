// H700: agora #178 — a struct parameter's field handed back through a `?`, the argument reassigned while the result is read (struct_param_field_through_a_cond_then_reassigned).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part P p b c → String { ^ ? c . p s ( mk ) }

@ main → i {
    : ~ P p @ P { ( mk ) 1 }
    : String t ( part p T )
    = p @ P { ( mk ) 2 }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
