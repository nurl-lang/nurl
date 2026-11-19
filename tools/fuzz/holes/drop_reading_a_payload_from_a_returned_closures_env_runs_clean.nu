// drop_reading_a_payload_from_a_returned_closures_env_runs_clean: the env's value's `drop` only reads the payload
// Closed: only the impls of values the returned closure took over, whose summary changes the payload, are swept at its release (agora #919): the shape the fix must keep.
// main 5916ad5: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #919: the env's value's drop only reads the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) ) } }

@ mkf sink H h → ( @ i ) { ^ \ → i { ^ # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    { : ( @ i ) f ( mkf @ H { r } ) ( nurl_println_int ( f ) ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
