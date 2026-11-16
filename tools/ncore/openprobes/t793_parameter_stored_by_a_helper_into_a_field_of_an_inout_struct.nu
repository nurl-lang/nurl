// map: §2.10 | A2 | rejected | - | agora #793: a helper storing its Rc parameter into a field of an `inout` struct parameter (`= . w a h`), the local then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ put ( Rc ( Vec u ) ) h inout W w → v { = . w a h }

@ ch ( Rc ( Vec u ) ) h → v { : ~ W w @ W { ( rc_new [( Vec u )] ( vec_new [u] ) ) } ( put h w ) ( rc_set [( Vec u )] . w a ( vec_new [u] ) ) }

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
