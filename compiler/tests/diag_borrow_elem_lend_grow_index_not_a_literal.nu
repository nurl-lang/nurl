// diag_borrow_elem_lend_grow_index_not_a_literal.nu — the view's element
// is named by a binding, not a number literal: which element it is, is not
// known, so growing element 0 ends it (AGORA-374).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : i z 1
    : s d1 ( string_data ( vec_at [String] vs z ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
