// view_pushed_through_a_field_viewer_outlives_its_source: agora #292 — the same push through a field viewer `: ( Vec ( Slice u ) ) w . o kids`; `. o kids` read after the block.
// Closed: a value kept in a container reached through a borrow — a copy of the owner's handle, a field viewer, an element — lands in the owner(s) the borrow's bytes are read out of, which hold the view too (__bck_store_owners, kc19's kept branch; agora #292).
// main: heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through a field viewer, read through the struct
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec ( Slice u ) ) kids i n }

@ main → i {
    : S o @ S { ( vec_new [( Slice u )] ) 1 }
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        : ( Vec ( Slice u ) ) w . o kids
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] . o kids 0 ) 0 ) )
    ^ 0
}
