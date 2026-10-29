// H720: agora #178 — an enum parameter's payload handed back through a `?` inside a `??` arm, the argument reassigned while the result is read (payload_through_a_cond_in_an_arm_then_reassigned).
// Closed: a `?` arm that hands out an enum payload binding of a parameter lends that parameter back in part, as a `??` arm does (mem_note_payload_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | G {
    S String
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick G g b c → String { ^ ?? g { S s → ? c s ( mk ) Nil → ( mk ) } }

@ main → i {
    : ~ G g @ G { S ( mk ) }
    : String t ( pick g T )
    = g @ G { Nil }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
