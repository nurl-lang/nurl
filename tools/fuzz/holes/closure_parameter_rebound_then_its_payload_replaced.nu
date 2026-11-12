// closure_parameter_rebound_then_its_payload_replaced: a closure `\ ( Rc ( Vec u ) ) x → v { : t x ( rc_set t … ) }` called with `r`, while a slice of the payload is taken through `r2`
// Closed: a local a parameter was put into — a literal, a container it was pushed into, the result of a call that keeps it, `( box_new h )` — holds the parameter's storage (g_pderiv, g_pd_put), and so does a closure literal's local copy of its own parameter: what a call changes through it is in the summary (agora #770).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #770: a closure parameter rebound, then its payload replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ( Rc ( Vec u ) ) ) f \ ( Rc ( Vec u ) ) x → v { : ( Rc ( Vec u ) ) t x ( rc_set [( Vec u )] t ( vec_new [u] ) ) }
    ( f r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
