// closure_only_reading_its_capture_assigned_in_a_loop_runs_clean: a read-only closure assigned below its run in a loop, a Slice of the captured Vec read after
// Guard for agora #686's fix: the loop replay ends views only for a literal that changes the capture.
// main 21774dd7: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #686 guard: a read-only closure assigned in a loop keeps the views of its capture
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
    : ~ ( @ v ) d c0
    : ~ i j 0
    ~ < j 2 {
        ( d )
        = d \ → v { ( nurl_println_int # i ( vec_len [u] xs ) ) }
        = j + j 1
    }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
