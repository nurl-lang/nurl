// diag_borrow_elem_lend_grow_ends_another_elements_view.nu — growing
// element 0 through a value a call lends out of the Vec ends a view of
// element 1 too. Which element a borrow reaches is no part of the
// calculus: A2 reads an element borrow as reaching the Vec's elements
// (`Kind.inner`), and a change through one ends every borrow of that kind
// (`Eff.dropIn`), so the view of element 1 is not typed past the push.
// nurlc refuses it as A2 does (AGORA-374). A view of the Vec's own block
// stays (elem_lend_grow_keeps_other_views).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
    ^ 0
}
