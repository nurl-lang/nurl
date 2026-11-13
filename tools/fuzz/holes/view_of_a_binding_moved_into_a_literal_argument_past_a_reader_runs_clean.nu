// view_of_a_binding_moved_into_a_literal_argument_past_a_reader_runs_clean: `( w @ X { xs } )` with w only reading
// Kept: a view of a value moved into a struct's field stays valid while that field is unchanged — reading it, or changing another field (agora #799).
// main 0aeaa321: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: a literal argument handed to a reader
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ w X x → v {
    ( nurl_println_int # i ( vec_len [u] . x v ) )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( w @ X { xs } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
