// view_pushed_through_element_copy_field_viewer_outlives_its_source: agora #292 — `: S e ( vec_at [S] vs 0 )`, `: … w . e kids` and `: … b2 . e kids`, a view of a block-local pushed through `w`, then read through `b2` after the block (view_pushed_through_element_copy_field_viewer_outlives_its_source).
// Closed: the vpass row keeps the view in `vs`, what `w` flattens to; `vs` ending with `loc` ends `b2`.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through a field viewer of an element copy, read through another
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
: S { ( Vec ( Slice u ) ) kids i n }
@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( vec_new [( Slice u )] ) 1 } )
    : S e ( vec_at [S] vs 0 )
    : ( Vec ( Slice u ) ) w . e kids
    : ( Vec ( Slice u ) ) b2 . e kids
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] b2 0 ) 0 ) )
    ^ 0
}
