// view_pushed_through_identity_copy_outlives_its_source: agora #292 — a slice of a block-local Vec pushed into `vs` through `: … w ( id vs )`, then read out of `vs` after the block: the dependency went to `w`, a borrow, not to `vs` (view_pushed_through_identity_copy_outlives_its_source).
// Closed: a value kept through a borrow is kept in the owners that borrow flattens to (the vpass row): `vs` holds the view of `loc`, and ends with it.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through an identity copy of a vector, read after its source ended
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ id ( Vec ( Slice u ) ) x → ( Vec ( Slice u ) ) { ^ x }

@ main → i {
    : ( Vec ( Slice u ) ) vs ( vec_new [( Slice u )] )
    : ( Vec ( Slice u ) ) w ( id vs )
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] vs 0 ) 0 ) )
    ^ 0
}
