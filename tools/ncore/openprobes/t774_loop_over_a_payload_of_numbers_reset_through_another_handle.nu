// map: §2.5 | A2 | rejected | - | agora #774: `~ x pl` over an Rc payload of numbers taken through `r2`, `( wipe r )` in the body clearing and shrinking it
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec u ) pl ( rc_get [( Vec u )] r2 )
    : ~ i n 0
    ~ x pl {
        ( wipe r )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
