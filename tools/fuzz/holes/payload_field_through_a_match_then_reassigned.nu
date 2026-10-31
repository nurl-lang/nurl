// payload_field_through_a_match_then_reassigned: agora #178 — the same, the argument a binding reassigned while the result is read (payload_field_through_a_match_then_reassigned).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h704 | agora #178: the same, the argument a binding reassigned while the result is read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ part G g → String { ^ ?? g { V p → . p s Nil → ( mk ) } }

@ main → i {
    : ~ G g @ G { V @ P { ( mk ) 1 } }
    : String t ( part g )
    = g @ G { Nil }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
