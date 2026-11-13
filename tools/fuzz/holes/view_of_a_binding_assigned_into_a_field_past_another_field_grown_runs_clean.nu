// view_of_a_binding_assigned_into_a_field_past_another_field_grown_runs_clean: `= . xx v xs`, then `. xx w` grown
// Kept: a view of a value moved into a struct's field stays valid while that field is unchanged — reading it, or changing another field (agora #799).
// main 0aeaa321: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: another field grown after a field assignment
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v ( Vec u ) w }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ~ X xx @ X { ( vec_new [u] ) ( vec_new [u] ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    = . xx v xs
    ( vec_reserve [u] . xx w 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
