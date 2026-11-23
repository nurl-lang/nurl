// rc_payload_view_across_a_closure_over_a_clone_of_a_parameter_made_by_a_maker_defined_below: a maker defined below main returns a struct of a closure over a clone of its Rc parameter and another clone; a view through the second is held across the closure's call
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: a holder-returning maker defined below its caller had no placeholder at all, so even a parameter's clone went unseen
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) set ( Rc ( Vec u ) ) h }

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : Pair p ( mk r )
    : ( @ v ) s . p set
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Rc ( Vec u ) ) c → Pair {
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    : ( Rc ( Vec u ) ) e ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → v { ( rc_set [( Vec u )] d ( vec_new [u] ) ) } e }
}
