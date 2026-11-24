// rc_payload_view_across_a_closure_over_a_weak_of_a_fresh_rc_whose_clone_is_returned: a maker returns a closure over a Weak of its fresh Rc that upgrades it and replaces the payload, and the Rc itself beside it; a view through the Rc is held across the closure's call
// main 3cf624c: accepted, heap-use-after-free under ASan; refused since github#2206 (AGORA-945).
// map: §7.6 | A2 | rejected | - | AGORA-945: the closure holds a Weak of the maker's fresh Rc and upgrades it: the upgraded handle is a local of the closure body, an anonymous handle of the Rc type
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Pair { ( @ v ) set ( Rc ( Vec u ) ) h }

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    : ( Weak ( Vec u ) ) k ( rc_downgrade [( Vec u )] c )
    ^ @ Pair { \ → v { ?? ( weak_upgrade [( Vec u )] k ) { T r → { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } F → {} } } c }
}

@ main → i {
    : Pair p ( mk )
    : ( @ v ) s . p set
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] . p h ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
