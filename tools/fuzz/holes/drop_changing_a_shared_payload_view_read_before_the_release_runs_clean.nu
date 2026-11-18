// drop_changing_a_shared_payload_view_read_before_the_release_runs_clean: view read before the release
// Closed: a release with no call is swept as a call of the `% Drop` it runs only for what that impl's summary changes, where the value is released, and only of the Rc types it reaches (agora #766): the shape the fix must keep.
// main 5f3d33e: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #766: view read before the release
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`
: H { ( Rc ( Vec u ) ) a }
% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ? > ( slice_len [u] sl ) 0 { : H h @ H { r } ( nurl_println_int # i ( slice_at [u] sl 0 ) ) } {}
    ^ 0
}
