// H740: agora #179 — an inner block's String handed through a `?` to a binding of an outer block (inner_local_through_a_cond_assigned_outward).
// Closed: a `?` / `??` assigned to a binding of an outer block measures its arms against that binding's scope: a binding of an inner block moves out, a view or a field of one is copied (g_join_rdepth, mem_arm_copy_out; agora #179).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : String x ( mk )
        = t ? T x ( mk )
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
