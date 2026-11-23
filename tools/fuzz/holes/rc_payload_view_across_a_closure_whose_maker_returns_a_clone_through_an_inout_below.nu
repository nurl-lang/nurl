// rc_payload_view_across_a_closure_whose_maker_returns_a_clone_through_an_inout_below: a maker hands a clone of its fresh Rc out through an inout parameter and returns a closure replacing its payload, defined below main
// main 4525fc8: accepted, heap-use-after-free under ASan.
// map: §7.6 | A2 | rejected | - | AGORA-945: the clone leaves through an inout parameter; the maker returns a closure and is defined below
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    : ~ ( Rc ( Vec u ) ) out ( rc_new [( Vec u )] w )
    : ( @ v ) s ( mk out )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] out ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk inout ( Rc ( Vec u ) ) o → ( @ v ) {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    = o ( rc_clone [( Vec u )] c )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}
