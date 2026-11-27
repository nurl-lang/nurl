// diag_borrow_elem_lend_grow_after_a_swap.nu — a view of element 1, by its
// index literal, then a swap: element 0 is the one it views now, and
// growing it frees what the view points into. A call that may reorder the
// Vec ends every view's "that element alone" fact (AGORA-374).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ( vec_swap [String] vs 0 1 )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
