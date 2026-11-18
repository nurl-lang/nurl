// reading_literal_through_a_pick_declared_below_its_caller_runs_clean: the guard of growing_literal_through_a_pick_declared_below_its_caller_run_beside_a_view: the literal only reads
// Closed (agora #813): the closure only reads what it captured; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a reading literal through a pick declared below, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( pick \ → v { ( nurl_println_int # i ( vec_len [u] xs ) ) } )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ pick ( @ v ) f → ( @ v ) { ^ f }
