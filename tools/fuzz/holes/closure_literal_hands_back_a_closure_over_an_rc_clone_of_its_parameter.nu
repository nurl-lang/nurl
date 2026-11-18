// closure_literal_hands_back_a_closure_over_an_rc_clone_of_its_parameter: a literal taking an Rc, handing back a closure over an `rc_clone` of it that replaces the payload, run beside a view of the payload
// Closed (agora #838): the effect on the share `q` is the literal's parameter's (`__rcof`), so `lr#` names it %0 and the call maps it onto the argument r.
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (0), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal's call handing back a closure over an rc_clone of its parameter that replaces the payload, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mkr ( Rc ( Vec u ) ) x → ( @ v ) { ^ \ → v { ( rc_set [( Vec u )] x ( vec_new [u] ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( @ ( @ v ) ( Rc ( Vec u ) ) ) g \ ( Rc ( Vec u ) ) p → ( @ v ) { : ( Rc ( Vec u ) ) q ( rc_clone [( Vec u )] p ) ^ \ → v { ( rc_set [( Vec u )] q ( vec_new [u] ) ) } }
    : ( @ v ) d ( g r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
