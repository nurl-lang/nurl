// view_handed_back_out_of_a_vec_of_shares_past_rc_set_through_another_handle: a callee's view of `( rc_get ( vec_at hs 0 ) )` kept past `( rc_set r … )` in the caller
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage (agora #726).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a view handed back out of a Vec of shares, past rc_set through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ grow ( Rc ( Vec String ) ) h → v { : ~ i k 0 ~ < k 200 { ( string_push_str ( vec_at [String] ( rc_get [( Vec String )] h ) 0 ) `more and more text to move the buffer ` ) = k + k 1 } }

@ view0 ( Vec ( Rc ( Vec u ) ) ) hs → ( Slice u ) { ^ ( slice_from_vec [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Slice u ) sl ( view0 hs )
    ( rc_set [( Vec u )] r ( vec_new [u] ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
