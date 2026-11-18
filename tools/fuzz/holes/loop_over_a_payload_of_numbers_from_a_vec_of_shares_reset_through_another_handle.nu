// map: §2.5 | A2 | rejected | - | AGORA-774: `~ x pl` over the payload of `( vec_at hs 0 )`, a Vec of shares, `( wipe r )` in the body clearing and shrinking it
// AGORA-774 (closed with AGORA-580): refused - the loop's cursor over a container lent out of an element is a view of those elements (main 5faa22f8: accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Vec u ) pl ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) )
    : ~ i n 0
    ~ x pl {
        ( wipe r )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
