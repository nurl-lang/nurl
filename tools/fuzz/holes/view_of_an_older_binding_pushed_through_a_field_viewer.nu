// view_of_an_older_binding_pushed_through_a_field_viewer: agora #292 — a view of a binding OLDER than the struct pushed through a field viewer (the shape the fix must keep).
// Closed: a value kept in a container reached through a borrow — a copy of the owner's handle, a field viewer, an element — lands in the owner(s) the borrow's bytes are read out of, which hold the view too (__bck_store_owners, kc19's kept branch; agora #292).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #292: a view of an older binding pushed through a field viewer
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec ( Slice u ) ) kids i n }

@ main → i {
    : ( Vec u ) loc ( vec_new [u] )
    ( vec_push_word_u8 loc 42 1 F )
    : S o @ S { ( vec_new [( Slice u )] ) 1 }
    {
        : ( Vec ( Slice u ) ) w . o kids
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] . o kids 0 ) 0 ) )
    ^ 0
}
