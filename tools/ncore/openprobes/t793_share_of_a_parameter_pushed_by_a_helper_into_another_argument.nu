// map: §2.10 | A2 | rejected | - | agora #793: a helper pushing `( rc_clone h )` into another argument, the local it went into then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ wipe0 ( Vec ( Rc ( Vec u ) ) ) xs → v { ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) ) }

@ addto2 ( Rc ( Vec u ) ) h ( Vec ( Rc ( Vec u ) ) ) xs → v { ( vec_push [( Rc ( Vec u ) )] xs ( rc_clone [( Vec u )] h ) ) }

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] ) ( addto2 h xs ) ( wipe0 xs ) }

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
