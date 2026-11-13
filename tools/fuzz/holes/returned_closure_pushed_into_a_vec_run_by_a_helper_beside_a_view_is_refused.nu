// returned_closure_pushed_into_a_vec_run_by_a_helper_beside_a_view_is_refused: a closure a maker hands back, replacing its Rc parameter's payload, pushed into a Vec, the Vec run by a helper; a slice taken through another handle after the push is read after
// Closed: agora #838, a call handing back a closure whose effects its maker's answer gives is a member doing those, which a holder carries.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a maker's closure pushed into a Vec and run by a helper replaces an Rc's payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ runall ( Vec ( @ v ) ) fs → v { ?? ( vec_get [( @ v )] fs 0 ) { T g → { ( g ) } F → {} } }

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    ^ \ → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs ( mk r ) )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runall fs )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
