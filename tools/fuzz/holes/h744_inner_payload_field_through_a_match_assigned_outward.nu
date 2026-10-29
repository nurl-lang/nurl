// H744: agora #179 — a field of an inner block's enum payload handed through a `??` to a binding of an outer block (inner_payload_field_through_a_match_assigned_outward).
// Closed: a `?` / `??` assigned to a binding of an outer block measures its arms against that binding's scope: a binding of an inner block moves out, a view or a field of one is copied (g_join_rdepth, mem_arm_copy_out; agora #179).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : G g @ G { V @ P { ( mk ) 1 } }
        = t ?? g { V p → . p s Nil → ( mk ) }
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
