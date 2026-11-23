// rc_payload_read_before_a_closure_over_a_parameter_clone_runs_clean: a maker returns a closure over a clone of its Rc parameter and another clone; the view through the second is read before the closure's call
// main 4525fc8: refused: 's' borrows from 'p', ended where `( rc_get . p h )` replayed the holder's closures.
// map: §7.6 | A2 | runs-clean | - | AGORA-945: guard: the parameter twin, refused on main because rc_get of a holder's Rc field replayed the holder's closures
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) set ( Rc ( Vec u ) ) h }

@ mk ( Rc ( Vec u ) ) c0 → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] c0 )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } d }
}

@ main → i {
    : ~ ( Vec u ) w0 ( vec_new [u] )
    ( vec_push [u] w0 # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w0 )
    : Pair p ( mk r )
    : ( @ v ) s . p set
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( s )
    ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] . p h ) ) )
    ^ 0
}
