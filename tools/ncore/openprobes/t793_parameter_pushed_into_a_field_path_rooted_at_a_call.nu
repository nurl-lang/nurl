// map: §2.10 | A2 | rejected | - | agora #793: a parameter pushed into `. ( box_get bx ) hs`, a container field path rooted at a call, then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: P { ( Vec ( Rc ( Vec u ) ) ) hs }

@ ch ( Rc ( Vec u ) ) h → v {
    : ( Box P ) bx ( box_new [P] @ P { ( vec_new [( Rc ( Vec u ) )] ) } )
    ( vec_push [( Rc ( Vec u ) )] . ( box_get [P] bx ) hs h )
    ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] . ( box_get [P] bx ) hs 0 ) ( vec_new [u] ) )
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
