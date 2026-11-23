// rc_payload_view_across_a_closure_growing_a_fresh_rc_payload_whose_clone_is_returned: a maker returns a closure that grows its fresh Rc's payload, and a clone of that Rc beside it; a view through the clone is held across the closure's call
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: the closure grows the payload (vec_push through rc_get) instead of replacing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) grow ( Rc ( Vec u ) ) h }

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → v { : ~ i k 0 ~ < k 64 { ( vec_push [u] ( rc_get [( Vec u )] c ) # u k ) = k + k 1 } } d }
}

@ main → i {
    : Pair p ( mk )
    : ( @ v ) s . p grow
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
