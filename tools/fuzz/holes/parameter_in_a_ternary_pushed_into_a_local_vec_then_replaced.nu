// parameter_in_a_ternary_pushed_into_a_local_vec_then_replaced: `( vec_push xs ? > k 0 h h )`, then `( rc_set ( vec_at xs 0 ) … )`
// Closed: the helper puts its Rc parameter into a local by this spelling, and its drop / irealloc summary now leads from that local to the parameter, so the caller's view through another handle ends at the call (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: the parameter pushed as a ternary's arm, then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ ch ( Rc ( Vec u ) ) h i k → v { : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] ) ( vec_push [( Rc ( Vec u ) )] xs ? > k 0 h h ) ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r 1 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
