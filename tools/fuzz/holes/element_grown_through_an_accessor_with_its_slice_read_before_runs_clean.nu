// element_grown_through_an_accessor_with_its_slice_read_before_runs_clean: agora #349 — `( vec_reserve ( row0 vv ) n )` after the slice was read for the last time
// The shape the fix must keep: a view read before the change (agora #349).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #349: an element grown through an accessor, its slice read before
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ row0 ( Vec ( Vec u ) ) vv → ( Vec u ) {
    ^ ( vec_at [( Vec u )] vv 0 )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( vec_reserve [u] ( row0 vv ) 4096 )
    ^ 0
}
