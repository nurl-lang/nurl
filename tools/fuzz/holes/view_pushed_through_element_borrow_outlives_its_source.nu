// view_pushed_through_element_borrow_outlives_its_source: agora #292 — `vs` a Vec of Vecs, `: ( Vec ( Slice u ) ) w ( vec_at … vs 0 )`, a view of a block-local pushed through `w`, then read through `vs` after the block (view_pushed_through_element_borrow_outlives_its_source).
// Closed: the vpass row keeps the view in `vs`, what the element borrow flattens to.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through an element borrow, read after its source ended
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec ( Slice u ) ) ) vs ( vec_new [( Vec ( Slice u ) )] )
    ( vec_push [( Vec ( Slice u ) )] vs ( vec_new [( Slice u )] ) )
    : ( Vec ( Slice u ) ) w ( vec_at [( Vec ( Slice u ) )] vs 0 )
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] ( vec_at [( Vec ( Slice u ) )] vs 0 ) 0 ) 0 ) )
    ^ 0
}
