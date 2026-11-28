// diag_borrow_elem_lend_grow_of_struct_elements.nu — the elements are
// structs, not Strings or Vecs: formal A2 lends an element at its index only
// out of a Vec of Vecs (RhsT.atIdx), so growing element 0's field ends the
// view of element 1's field (AGORA-1037).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tag { String name i n }

@ main → i {
    : ( Vec Tag ) vs ( vec_new [Tag] )
    ( vec_push [Tag] vs @ Tag { ( string_from `short` ) 1 } )
    ( vec_push [Tag] vs @ Tag { ( string_from `second element string long enough for the heap` ) 2 } )
    : s d1 ( string_data . ( vec_at [Tag] vs 1 ) name )
    ( string_push_str . ( vec_at [Tag] vs 0 ) name `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
