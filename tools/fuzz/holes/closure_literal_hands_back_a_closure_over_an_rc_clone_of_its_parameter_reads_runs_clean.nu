// closure_literal_hands_back_a_closure_over_an_rc_clone_of_its_parameter_reads_runs_clean: the guard of closure_literal_hands_back_a_closure_over_an_rc_clone_of_its_parameter: the closure only reads the payload
// Closed (agora #838): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main cfbd6b0e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #838: a literal's call handing back a closure over an rc_clone of its parameter that only reads, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mkr ( Rc ( Vec u ) ) x → ( @ v ) { ^ \ → v { ( rc_set [( Vec u )] x ( vec_new [u] ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( @ ( @ v ) ( Rc ( Vec u ) ) ) g \ ( Rc ( Vec u ) ) p → ( @ v ) { : ( Rc ( Vec u ) ) q ( rc_clone [( Vec u )] p ) ^ \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] q ) ) ) } }
    : ( @ v ) d ( g r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
