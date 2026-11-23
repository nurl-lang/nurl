// rc_payload_view_across_a_closure_over_a_fresh_rc_whose_clone_an_inout_vec_keeps: a maker pushes a clone of its fresh Rc into an inout Vec and returns a closure replacing the payload; a view through the Vec's element is held across the closure's call
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: the clone leaves in a Vec the caller hands in, through vec_push
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mk inout ( Vec ( Rc ( Vec u ) ) ) keep → ( @ v ) {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ( vec_push [( Rc ( Vec u ) )] keep ( rc_clone [( Vec u )] c ) )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ main → i {
    : ~ ( Vec ( Rc ( Vec u ) ) ) ks ( vec_new [( Rc ( Vec u ) )] )
    : ( @ v ) s ( mk ks )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] ks 0 ) ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
