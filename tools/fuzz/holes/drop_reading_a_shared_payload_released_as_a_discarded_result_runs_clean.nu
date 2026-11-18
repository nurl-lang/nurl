// drop_reading_a_shared_payload_released_as_a_discarded_result_runs_clean: drop that reads only, discarded
// Closed: a release with no call is swept as a call of the `% Drop` it runs only for what that impl's summary changes, where the value is released, and only of the Rc types it reaches (agora #766): the shape the fix must keep.
// main 5f3d33e: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #766: drop that reads only, discarded
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) ) } }

@ mk sink ( Rc ( Vec u ) ) x → H { ^ @ H { x } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( mk ( rc_clone [( Vec u )] r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
