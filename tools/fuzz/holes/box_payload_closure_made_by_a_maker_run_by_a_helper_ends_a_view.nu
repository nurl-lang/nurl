// map: §2.10 | A2 | rejected | - | AGORA-960: a closure in a Box payload made by a maker, run by a helper through box_get
// AGORA-960 (closed): refused - as the Rc maker's: a builder handing back box_new of a holder literal (main 502c1b08: accepted, heap-use-after-free under ASan)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: H { ( @ v ) go }

@ runit ( Box H ) r → v { : H h ( box_get [H] r ) : ( @ v ) g . h go ( g ) }

@ mkh ( Rc ( Vec u ) ) d → ( Box H ) {
    : ( Rc ( Vec u ) ) e ( rc_clone [( Vec u )] d )
    ^ ( box_new [H] @ H { \ → v { ( rc_set [( Vec u )] e ( vec_new [u] ) ) } } )
}

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Box H ) hr ( mkh r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( runit hr )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
