// view_of_a_binding_moved_into_a_struct_past_another_field_grown_runs_clean: `@ X { xs ( vec_new ) }`, then `. xx w` grown
// Kept: a view of a value moved into a struct's field stays valid while that field is unchanged — reading it, or changing another field (agora #799).
// main 0aeaa321: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: another field of the struct grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v ( Vec u ) w }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : X xx @ X { xs ( vec_new [u] ) }
    ( vec_reserve [u] . xx w 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
