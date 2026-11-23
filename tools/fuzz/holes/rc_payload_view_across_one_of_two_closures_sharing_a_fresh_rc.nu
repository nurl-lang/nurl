// rc_payload_view_across_one_of_two_closures_sharing_a_fresh_rc: two closures over one fresh Rc - one hands back a clone of it, the other replaces its payload; a view through the clone is held across the second
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: two closures over one fresh Rc, one handing back a clone, the other replacing the payload; the view through the clone ends at the second
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Two { ( @ ( Rc ( Vec u ) ) ) get ( @ v ) set }

@ mk → Two {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ^ @ Two { \ → ( Rc ( Vec u ) ) { ^ ( rc_clone [( Vec u )] c ) } \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } }
}

@ main → i {
    : Two t ( mk )
    : ( @ ( Rc ( Vec u ) ) ) g . t get
    : ( @ v ) s . t set
    : ( Rc ( Vec u ) ) r ( g )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
