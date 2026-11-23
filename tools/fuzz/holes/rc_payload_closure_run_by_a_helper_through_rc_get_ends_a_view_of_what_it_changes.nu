// map: §2.10 | A2 | rejected | - | AGORA-960: a closure stored in an Rc payload, run by a helper through rc_get, replaces another Rc's payload a slice views
// AGORA-960 (closed): refused - an ( Rc H ) whose H has a closure field holds closures (__may_hold_clo_rc), so hr is a holder and runit runs what it holds (main 502c1b08: accepted, heap-use-after-free under ASan)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( @ v ) go }

@ runit ( Rc H ) r → v { : H h ( rc_get [H] r ) : ( @ v ) g . h go ( g ) }

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) d ( rc_clone [( Vec u )] r )
    : ( Rc H ) hr ( rc_new [H] @ H { \ → v { ( rc_set [( Vec u )] d ( vec_new [u] ) ) } } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( runit hr )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
