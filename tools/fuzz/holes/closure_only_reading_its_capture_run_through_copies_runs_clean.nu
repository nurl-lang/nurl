// closure_only_reading_its_capture_run_through_copies_runs_clean: a closure only reading its captured Vec, run through an alias, a Slice of the Vec read after
// Guard for agora #686's fix: a closure that changes nothing it captured keeps the views, through any copy.
// main 21774dd7: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #686 guard: a read-only closure run through an alias keeps the views of its capture
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( nurl_println_int # i ( vec_len [u] xs ) ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d c
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
