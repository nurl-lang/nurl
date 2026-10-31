// view_pushed_through_field_viewer_outlives_its_source: agora #292 — the same through a field viewer: `: ( Vec ( Slice u ) ) w . o kids`, the push through `w` in a block, then a read of `( vec_at … . o kids 0 )` after it (view_pushed_through_field_viewer_outlives_its_source).
// Closed: the vpass row keeps the view in `o`, what `w` flattens to.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: PushArg | A1 | rejected | - | agora #292: a view pushed through a field viewer, read after its source ended
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec ( Slice u ) ) kids i n }

@ main → i {
    : S o @ S { ( vec_new [( Slice u )] ) 1 }
    : ( Vec ( Slice u ) ) w . o kids
    {
        : ( Vec u ) loc ( vec_new [u] )
        ( vec_push_word_u8 loc 42 1 F )
        ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] . o kids 0 ) 0 ) )
    ^ 0
}
