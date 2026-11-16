// map: §2.10 | A2 | rejected | - | agora #793: a `??` payload of an option parameter pushed into a local Vec, then replaced through it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ ch ? ( Rc ( Vec u ) ) oh → v {
    : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] )
    ?? oh { T h → ( vec_push [( Rc ( Vec u ) )] xs h ) F → {} }
    ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ?( Rc ( Vec u ) ) o @ ?( Rc ( Vec u ) ) { T r }
    ( ch o )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
