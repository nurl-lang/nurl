// payload_field_through_a_cond_in_a_match_arm: agora #178 — a payload's field handed back through a `?` inside a `??` arm (payload_field_through_a_cond_in_a_match_arm).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h705 | agora #178: a payload's field handed back through a `?` inside a `??` arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ pick G g b c → String { ^ ?? g { V p → ? c . p s ( mk ) Nil → ( mk ) } }

@ main → i {
    : String t ( pick @ G { V @ P { ( mk ) 1 } } T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
