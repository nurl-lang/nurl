// parameter_share_taken_by_a_sink_into_a_later_argument_then_replaced: `@ adds sink ( Rc … ) h ( Vec … ) xs` called as `( adds ( rc_clone h ) xs )`, then `( rc_set ( vec_at xs 0 ) … )`
// Closed: the helper puts its Rc parameter into a local by this spelling, and its drop / irealloc summary now leads from that local to the parameter, so the caller's view through another handle ends at the call (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: a share of the parameter taken by a sink parameter into a later argument, then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ adds sink ( Rc ( Vec u ) ) h ( Vec ( Rc ( Vec u ) ) ) xs → v { ( vec_push [( Rc ( Vec u ) )] xs h ) }

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] ) ( adds ( rc_clone [( Vec u )] h ) xs ) ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) ) }

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
