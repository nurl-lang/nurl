// local_reading_literal_through_pick_run_beside_a_view_runs_clean: the guard of local_growing_literal_through_pick_run_beside_a_view: the literal only reads
// Closed (agora #813): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main e35ded15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a local reading literal through pick, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick ( @ v ) f → ( @ v ) { ^ f }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( pick \ → v { ( nurl_println_int # i ( vec_len [u] xs ) ) } )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
