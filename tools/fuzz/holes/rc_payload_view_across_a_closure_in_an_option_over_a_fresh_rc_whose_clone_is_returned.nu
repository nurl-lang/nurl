// rc_payload_view_across_a_closure_in_an_option_over_a_fresh_rc_whose_clone_is_returned: a maker returns an option of a closure replacing its fresh Rc's payload beside a clone of the Rc; a view through the clone is held across the closure's call in the option's arm
// main 3cf624c: accepted, heap-use-after-free under ASan; refused since github#2206 (AGORA-945).
// map: §7.6 | A2 | rejected | - | AGORA-945: the closure is returned in an option field
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ? ( @ v ) set ( Rc ( Vec u ) ) h }

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] c )
    ^ @ Pair { @ ?( @ v ) { T \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } } d }
}

@ main → i {
    : Pair p ( mk )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ?? . p set { T s → { ( s ) } F → {} }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
