// rc_payload_view_across_a_closure_that_runs_the_one_over_a_fresh_rc: the first probe's closure, run by a second closure literal the caller calls
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: the closure that replaces the payload is run by another closure
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) set ( Rc ( Vec u ) ) h }
@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } d }
}
@ main → i {
    : Pair p ( mk )
    : ( @ v ) s . p set
    : ( @ v ) t \ → v { ( s ) }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( t )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
