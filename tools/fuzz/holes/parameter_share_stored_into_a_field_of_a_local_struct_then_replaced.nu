// parameter_share_stored_into_a_field_of_a_local_struct_then_replaced: `= . w a ( rc_clone h )` into a local struct, then `( rc_set . w a … )`
// Closed: the helper puts its Rc parameter into a local by this spelling, and its drop / irealloc summary now leads from that local to the parameter, so the caller's view through another handle ends at the call (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: a share of the parameter stored into a local's field by a call, then replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ ch ( Rc ( Vec u ) ) h → v { : ~ W w @ W { ( rc_new [( Vec u )] ( vec_new [u] ) ) } = . w a ( rc_clone [( Vec u )] h ) ( rc_set [( Vec u )] . w a ( vec_new [u] ) ) }

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
