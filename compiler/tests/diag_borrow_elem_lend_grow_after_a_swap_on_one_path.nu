// diag_borrow_elem_lend_grow_after_a_swap_on_one_path.nu — as
// diag_borrow_elem_lend_grow_after_a_swap, the swap on one path of an
// `?`: past the join the view may view element 0 (AGORA-374).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ? > ( vec_len [String] vs ) 1 { ( vec_swap [String] vs 0 1 ) } {}
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
