// braceless_arm_repoints_a_vec_get_option_then_payload_returned: agora #335 (formal's #1610 regression 2, the String twin) — a `: ~ ?String` binding of a local Vec's vec_get, given a fresh None in a brace-less match arm, then its payload returned. Main copies the payload and runs clean; #1494's first head took the arm's `=` as straight-line and handed the element out uncopied: a heap-use-after-free.
// Closed: gen_match counts every arm body as a block level, braced or not, so mem_note_assign_lend keeps the lend for an `=` that may not run.
// main: accepted and clean (the payload is copied).
// map: §7.6 | A2 | runs-clean | - | agora #335: a brace-less arm's re-point keeps the payload's copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    ?? k { 1 → = o @ ?String { F } _ → {} }
    ?? o { T s → ^ s F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String b ( pick 0 )
    ( nurl_println ( string_data b ) )
    ^ 0
}
