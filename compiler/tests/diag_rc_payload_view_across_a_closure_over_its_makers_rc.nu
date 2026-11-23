// diag_rc_payload_view_across_a_closure_over_its_makers_rc.nu — a maker
// captures its own fresh Rc in a closure that replaces the payload, and
// returns a clone of that Rc beside the closure. The caller's view of the
// payload through the clone ends where the closure runs: the closure holds
// a handle no binding of the caller names, which may be the same Rc value
// (AGORA-945, proposal D3). The message names the closure's handle.
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
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
