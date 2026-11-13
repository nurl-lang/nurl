// struct_of_a_closure_handed_beside_another_handle_on_the_rc_it_changes_is_refused: a struct holding a closure that replaces an Rc's payload, handed to a function beside another handle on that Rc; the function views the payload through the handle, hands the struct to a helper that runs its closure, and reads the view
// Closed: agora #736, a holder argument's closures join the exclusive-call routes, reported where the callee (here through a helper) runs what that parameter holds — resolve_hold_routes.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a struct of a closure that replaces an Rc's payload handed beside another handle on it, run through a helper
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ viewrun C c ( Rc ( Vec u ) ) rb → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    ( viewrun c r2 )
    ^ 0
}
