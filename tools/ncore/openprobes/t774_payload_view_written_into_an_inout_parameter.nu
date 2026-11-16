// map: §2.7 | A2 | rejected | - | agora #774: `= out ( slice_from_vec ( rc_get ( vec_at hs 0 ) ) )` into an `inout` parameter, the caller's view kept past a payload reset through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ view_into ( Vec ( Rc ( Vec u ) ) ) hs inout ( Slice u ) out → v { = out ( slice_from_vec [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Vec u ) e ( vec_new [u] )
    : ~ ( Slice u ) out ( slice_from_vec [u] e )
    ( view_into hs out )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] out 0 ) )
    ^ 0
}
