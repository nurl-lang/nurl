// clone_of_a_share_handed_to_a_sink_helper_that_replaces_its_payload: `( ch ( rc_clone r ) )` with `ch` a sink helper replacing the payload, while a slice of it is taken through `r2`
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #733: a clone of a share, no binding, handed to a sink helper replacing its payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch sink ( Rc ( Vec u ) ) h → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch ( rc_clone [( Vec u )] r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
