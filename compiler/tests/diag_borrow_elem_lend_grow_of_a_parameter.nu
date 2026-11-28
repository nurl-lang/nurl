// diag_borrow_elem_lend_grow_of_a_parameter.nu — the Vec is a parameter,
// not a local owner: formal A2 lends an element at its index only out of an
// owner (RhsT.atIdx), so growing element 0 ends the view of element 1, as it
// does for any other element (AGORA-1037).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow_one ( Vec String ) vs → v {
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    ( grow_one vs )
    ^ 0
}
