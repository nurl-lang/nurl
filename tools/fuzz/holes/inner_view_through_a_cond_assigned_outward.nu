// inner_view_through_a_cond_assigned_outward: agora #179 — a view of an inner block's struct field handed through a `?` to a binding of an outer block (inner_view_through_a_cond_assigned_outward).
// Closed: a `?` / `??` assigned to a binding of an outer block measures its arms against that binding's scope: a binding of an inner block moves out, a view or a field of one is copied (g_join_rdepth, mem_arm_copy_out; agora #179).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h742 | agora #179: a view of an inner block's struct field handed through a `?` to a binding of an outer block
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        = t ? T x ( mk )
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
