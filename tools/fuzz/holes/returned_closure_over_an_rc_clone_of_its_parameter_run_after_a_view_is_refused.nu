// returned_closure_over_an_rc_clone_of_its_parameter_run_after_a_view_is_refused: a maker clones its Rc parameter (`: c ( rc_clone h )`) and hands back a closure replacing the clone's payload; a slice taken through another handle after the maker call is read after the closure runs
// Closed: agora #845, an rc_clone of a parameter is one Rc value with it: what a closure handed back does to the clone, it does to the parameter (`__rc_share_note`, `retcloeff`).
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #845: a maker's closure over an rc_clone of its parameter replaces the payload beside a view taken after the call
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] h )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( @ v ) f ( mk r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
