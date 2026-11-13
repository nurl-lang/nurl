// view_of_a_binding_moved_into_a_struct_read_after_runs_clean: the view read after the move, nothing changed
// Kept: a view of a value moved into a struct's field stays valid while that field is unchanged — reading it, or changing another field (agora #799).
// main 0aeaa321: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: a view read after its binding moved into a struct
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v i n }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : X xx @ X { xs 1 }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( nurl_println_int . xx n )
    ^ 0
}
