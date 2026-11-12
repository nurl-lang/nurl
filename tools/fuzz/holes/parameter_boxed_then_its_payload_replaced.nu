// parameter_boxed_then_its_payload_replaced: `: b ( box_new h ) ( rc_set ( box_get b ) … )` in a helper handed `r`, while a slice is taken through `r2`
// Closed: a local a parameter was put into — a literal, a container it was pushed into, the result of a call that keeps it, `( box_new h )` — holds the parameter's storage (g_pderiv, g_pd_put), and so does a closure literal's local copy of its own parameter: what a call changes through it is in the summary (agora #770).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #770: a parameter boxed, its payload replaced through the box
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ( Rc ( Vec u ) ) h → v { : ( Box ( Rc ( Vec u ) ) ) b ( box_new [( Rc ( Vec u ) )] h ) ( rc_set [( Vec u )] ( box_get [( Rc ( Vec u ) )] b ) ( vec_new [u] ) ) }

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
