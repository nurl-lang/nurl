// view_pushed_through_a_field_viewer_of_an_element_read_through_the_element: agora #292 — as …_read_through_the_vec, read through `. e kids`, `e` made before the block.
// Closed: a value kept in a container reached through a borrow — a copy of the owner's handle, a field viewer, an element — lands in the owner(s) the borrow's bytes are read out of, which hold the view too (__bck_store_owners, kc19's kept branch; agora #292).
// main: heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through a field viewer of an element, read through the element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec ( Slice u ) ) kids i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( vec_new [( Slice u )] ) 1 } )
    : S e ( vec_at [S] vs 0 )
    : ( Vec ( Slice u ) ) b2 . e kids
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        : ( Vec ( Slice u ) ) w . e kids
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] . e kids 0 ) 0 ) )
    ^ 0
}
