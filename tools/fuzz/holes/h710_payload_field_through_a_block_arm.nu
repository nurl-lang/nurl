// H710: agora #178 — a payload's field handed back as a `??` block arm's tail (`V p → { . p s }`) (payload_field_through_a_block_arm).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ part G g → String { ^ ?? g { V p → { . p s } Nil → ( mk ) } }

@ main → i {
    : String t ( part @ G { V @ P { ( mk ) 1 } } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
