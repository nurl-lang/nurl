// join_of_a_vec_get_lend_and_a_fresh_option_payload_returned: agora #335 — an immutable `?` join of a local Vec's `vec_get` and a callee's fresh option, its payload returned: copied on the owning path too, the fresh string freed by no one (formal's #1529 l1).
// Closed: a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag); a take through a `vec_get` slot is not made where the Vec is a capture of the closure being compiled (__vget_live, __pl_roots_capture); and an `=` at its binding's own depth replaces the value's lend pairs (mem_note_assign_lend; agora #335).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #335: a join of a vec_get lend and a fresh option, its payload returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a made string long enough for the heap` ) }
}

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ?String o ? == k 1 ( vec_get [String] vs 0 ) ( make )
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String a ( pick 0 )
    ( nurl_println ( string_data a ) )
    ^ 0
}
