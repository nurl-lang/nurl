// fresh_rc_handed_to_a_sink_helper_that_replaces_its_payload_runs_clean: `( ch ( rc_new ( vec_new ) ) )` with `ch` replacing the payload, while a slice of another Rc's payload is taken through `r2`: an Rc made right there is no other handle (a callee that only stores, keeps, reads or drops a share it takes changes no payload (the shape the fix must keep))
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #733: a fresh Rc handed to a payload replacer, past a view of another Rc
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ ch sink ( Rc ( Vec u ) ) h → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch ( rc_new [( Vec u )] ( vec_new [u] ) ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
