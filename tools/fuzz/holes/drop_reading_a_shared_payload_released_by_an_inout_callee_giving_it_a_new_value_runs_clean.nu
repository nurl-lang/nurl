// drop_reading_a_shared_payload_released_by_an_inout_callee_giving_it_a_new_value_runs_clean: `( reset h )`, `reset` giving its `inout` H parameter a new value: the old value, the caller's, is released in the callee, running a `drop` that only reads the payload a slice through `r2` views
// Closed: a parameter given a new value releases its old one, a call of each `% Drop` impl it runs: a drop edge in the function's summary, so the caller's view through another handle ends at the call (agora #766).
// main 5f3d33e: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #766: an inout callee giving its parameter a new value runs the old value's drop
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) ) } }

@ reset inout H h → v { = h @ H { ( rc_new [( Vec u )] ( vec_new [u] ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ H h @ H { ( rc_clone [( Vec u )] r ) }
    ( reset h )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
