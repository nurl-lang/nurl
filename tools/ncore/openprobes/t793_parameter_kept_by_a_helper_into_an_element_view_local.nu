// map: §2.10 | A2 | rejected | - | agora #793: a helper keeping its parameter into `x0`, a `( vec_at xss 0 )` binding, then replaced through the owner
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ addto2 ( Rc ( Vec u ) ) h ( Vec ( Rc ( Vec u ) ) ) xs → v { ( vec_push [( Rc ( Vec u ) )] xs h ) }

@ ch ( Rc ( Vec u ) ) h → v {
    : ( Vec ( Vec ( Rc ( Vec u ) ) ) ) xss ( vec_new [( Vec ( Rc ( Vec u ) ) )] )
    ( vec_push [( Vec ( Rc ( Vec u ) ) )] xss ( vec_new [( Rc ( Vec u ) )] ) )
    : ( Vec ( Rc ( Vec u ) ) ) x0 ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 )
    ( addto2 h x0 )
    ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 ) 0 ) ( vec_new [u] ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
