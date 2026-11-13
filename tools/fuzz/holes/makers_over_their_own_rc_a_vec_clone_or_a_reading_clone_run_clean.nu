// makers_over_their_own_rc_a_vec_clone_or_a_reading_clone_run_clean: makers handing back closures over an Rc they made, a vec_clone of their Vec parameter, or an rc_clone they only read, run beside views of the caller's Rc payload and Vec
// Guard for agora #845: an rc_clone of a parameter is one Rc value with it, and nothing else a maker builds is.
// main 923fa94a: accepted; clean under ASan and strict LSan.
// map: §2.2 | A2 | runs-clean | - | agora #845: makers over their own Rc, a vec_clone or a reading rc_clone, beside views
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ mkown → ( @ v ) {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ mkvc ( Vec u ) h → ( @ v ) {
    : ~ ( Vec u ) c ( vec_clone [u] h )
    ^ \ → v { ( vec_reserve [u] c 4096 ) }
}

@ mkread ( Rc ( Vec u ) ) h → ( @ v ) {
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] h )
    ^ \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] c ) ) ) }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs # u 5 )
    : ( @ v ) f1 ( mkown )
    : ( @ v ) f2 ( mkvc xs )
    : ( Rc ( Vec u ) ) ra ( rc_clone [( Vec u )] r )
    : ( @ v ) f3 ( mkread ra )
    : C c @ C { ( mkread r ) 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( Slice u ) sx ( slice_from_vec [u] xs )
    ( f1 )
    ( f2 )
    ( f3 )
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ?? ( slice_get [u] sx 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
