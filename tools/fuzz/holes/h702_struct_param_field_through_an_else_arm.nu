// H702: agora #178 — the same through the else arm (struct_param_field_through_an_else_arm).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part P p b c → String { ^ ? c ( mk ) . p s }

@ main → i {
    : String t ( part @ P { ( mk ) 1 } F )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
