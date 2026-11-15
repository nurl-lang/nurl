// map: §2.5 | A2 | rejected | - | agora #774: `~ x pl` over `. ( rc_get r2 ) data`, a payload struct's field of numbers, `( wipe r )` in the body clearing and shrinking it
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: D { ( Vec u ) data }

@ wipe ( Rc D ) r → v { ( vec_clear [u] . ( rc_get [D] r ) data ) ( vec_shrink_to_fit [u] . ( rc_get [D] r ) data ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc D ) r ( rc_new [D] @ D { v0 } )
    : ( Rc D ) r2 ( rc_clone [D] r )
    : ( Vec u ) pl . ( rc_get [D] r2 ) data
    : ~ i n 0
    ~ x pl {
        ( wipe r )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
