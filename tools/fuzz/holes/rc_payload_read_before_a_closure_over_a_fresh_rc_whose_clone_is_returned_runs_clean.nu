// rc_payload_read_before_a_closure_over_a_fresh_rc_whose_clone_is_returned_runs_clean: rc_payload_view_across_a_closure_over_a_fresh_rc_whose_clone_a_maker_returns_beside_it's shape with the view read before the closure's call, the payload read again after it
// main 4525fc8: accepted, clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-945: guard: the view is read before the closure runs; and a call handed a field that holds no closure (rc_get . p h) runs none of the holder's closures
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
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( s )
    ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] . p h ) ) )
    ^ 0
}
