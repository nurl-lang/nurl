// diag_borrow_elem_lend_grow_after_a_closure_swaps.nu — a closure that
// runs between the view and the push swaps the Vec it captured (AGORA-374).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    : ( @ v ) f \ → v { ( vec_swap [String] vs 0 1 ) }
    ( f )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
