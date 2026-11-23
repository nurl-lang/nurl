// rc_payload_view_across_a_closure_over_a_fresh_rc_made_by_a_maker_defined_below: rc_payload_view_across_a_closure_over_a_fresh_rc_whose_clone_a_maker_returns_beside_it's shape with the maker defined below main
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: the maker is compiled after its caller: its answer is a placeholder until then
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) set ( Rc ( Vec u ) ) h }

@ main → i {
    : Pair p ( mk )
    : ( @ v ) s . p set
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } d }
}
