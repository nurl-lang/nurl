// struct_of_a_closure_handed_to_a_function_below_beside_another_handle_is_refused: the same, the function defined below its caller and running the struct's closure itself
// Closed: agora #736, the callee's summary of what it runs of its parameters is asked once every function has compiled.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a struct of a closure handed beside another handle on the Rc it changes, to a function defined below
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    ( viewrun c r2 )
    ^ 0
}

@ viewrun C c ( Rc ( Vec u ) ) rb → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    : ( @ v ) g . c go
    ( g )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}
