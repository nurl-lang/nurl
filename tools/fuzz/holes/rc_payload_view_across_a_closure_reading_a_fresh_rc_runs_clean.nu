// rc_payload_view_across_a_closure_reading_a_fresh_rc_runs_clean: a maker's closure reads its fresh Rc's payload; a view through a clone returned beside it is held across the closure's call
// main 4525fc8: accepted, clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-945: guard: the closure only reads its Rc's payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ i ) get ( Rc ( Vec u ) ) h }

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → i { ^ ( vec_len [u] ( rc_get [( Vec u )] c ) ) } d }
}

@ main → i {
    : Pair p ( mk )
    : ( @ i ) s . p get
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( nurl_println_int ( s ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
