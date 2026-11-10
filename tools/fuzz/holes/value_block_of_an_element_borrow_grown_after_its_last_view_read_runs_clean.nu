// value_block_of_an_element_borrow_grown_after_its_last_view_read_runs_clean: agora #499 guard — `( vec_reserve [u] { e0 } 4096 )` after the slice of `e0` was last read.
// Guard: the growth ends the slice after its last read.
// main: runs clean.
// map: §2.10 | A1 | runs-clean | - | agora #499 guard: a value block argument grown after the last read of a view into it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] vv inner )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( vec_reserve [u] { e0 } 4096 )
    ^ 0
}
