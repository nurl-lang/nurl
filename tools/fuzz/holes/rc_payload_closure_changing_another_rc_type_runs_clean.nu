// map: §2.10 | A2 | runs-clean | - | AGORA-960 guard: the closure in the Rc payload replaces an Rc payload of another type than the one viewed
// AGORA-960 (closed): runs clean - what the closure changes is an ( Rc String ), the view is of an ( Rc ( Vec u ) )
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: H { ( @ v ) go }

@ runit ( Rc H ) r → v { : H h ( rc_get [H] r ) : ( @ v ) g . h go ( g ) }

@ main → i {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Rc String ) q ( rc_new [String] ( string_from `a string long enough for a heap buffer` ) )
    : ( Rc String ) q2 ( rc_clone [String] q )
    : ( Rc H ) hr ( rc_new [H] @ H { \ → v { ( rc_set [String] q2 ( string_from `another long heap string here` ) ) } } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( runit hr )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
