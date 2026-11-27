// diag_borrow_elem_lend_grow_after_a_swap_in_a_loop.nu — the view of
// element 1 is taken, then the Vec swapped, at the end of a round; the
// next round grows element 0, the one it views (AGORA-374).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    : ~ i q 0
    : ~ s d1 ( string_data ( vec_at [String] vs 1 ) )
    ~ < q 3 {
        ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
        ( nurl_println d1 )
        = d1 ( string_data ( vec_at [String] vs 1 ) )
        ( vec_swap [String] vs 0 1 )
        = q + q 1
    }
    ^ 0
}
