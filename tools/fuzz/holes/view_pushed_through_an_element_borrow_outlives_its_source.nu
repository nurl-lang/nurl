// view_pushed_through_an_element_borrow_outlives_its_source: agora #292 — the same push through an element borrow `( vec_at vs 0 )` of a Vec of Vecs; read through `vs` after the block.
// Closed: a value kept in a container reached through a borrow — a copy of the owner's handle, a field viewer, an element — lands in the owner(s) the borrow's bytes are read out of, which hold the view too (__bck_store_owners, kc19's kept branch; agora #292).
// main: heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through an element borrow, read through the outer Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec ( Slice u ) ) ) vs ( vec_new [( Vec ( Slice u ) )] )
    ( vec_push [( Vec ( Slice u ) )] vs ( vec_new [( Slice u )] ) )
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        : ( Vec ( Slice u ) ) w ( vec_at [( Vec ( Slice u ) )] vs 0 )
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] ( vec_at [( Vec ( Slice u ) )] vs 0 ) 0 ) 0 ) )
    ^ 0
}
