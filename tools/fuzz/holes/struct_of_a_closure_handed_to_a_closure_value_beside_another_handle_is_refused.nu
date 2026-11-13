// struct_of_a_closure_handed_to_a_closure_value_beside_another_handle_is_refused: a struct holding a closure that replaces an Rc's payload, handed beside another handle on that Rc to a closure value that views through the handle and runs the struct's closure
// Closed: agora #736, a closure value called may be any: its holder routes are always reported.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a struct of a closure handed beside another handle on the Rc it changes, to a closure value
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( @ v C ( Rc ( Vec u ) ) ) vr \ C c ( Rc ( Vec u ) ) rb → v {
        : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
        : ( @ v ) g . c go
        ( g )
        ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    }
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    ( vr c r2 )
    ^ 0
}
