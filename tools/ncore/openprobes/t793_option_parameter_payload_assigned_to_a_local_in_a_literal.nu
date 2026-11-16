// map: §2.10 | A2 | rejected | - | agora #793: a `??` payload of an option parameter assigned to a local in a literal (`= w @ W { h }`), then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ ch ? ( Rc ( Vec u ) ) oh → v {
    : ~ W w @ W { ( rc_new [( Vec u )] ( vec_new [u] ) ) }
    ?? oh { T h → { = w @ W { h } } F → {} }
    ( rc_set [( Vec u )] . w a ( vec_new [u] ) )
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
