// map: §2.10 | A2 | rejected | - | AGORA-960: the same, the Rc of the holder made by a maker
// AGORA-960 (closed): refused - mkh's result, an rc_new of a literal holding a closure, carries what that closure does (retcloeff from __last_call_hold_ms__) (main 502c1b08: accepted, heap-use-after-free under ASan)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( @ v ) go }

@ runit ( Rc H ) r → v { : H h ( rc_get [H] r ) : ( @ v ) g . h go ( g ) }

@ mkh ( Rc ( Vec u ) ) d → ( Rc H ) {
    : ( Rc ( Vec u ) ) e ( rc_clone [( Vec u )] d )
    ^ ( rc_new [H] @ H { \ → v { ( rc_set [( Vec u )] e ( vec_new [u] ) ) } } )
}

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Rc H ) hr ( mkh r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( runit hr )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
