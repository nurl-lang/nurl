// share_handed_to_a_sink_helper_that_reads_it_runs_clean: a sink helper reading `( vec_len ( rc_get h ) )`, while a slice of the payload is taken through `r2` (a callee that only stores, keeps, reads or drops a share it takes changes no payload (the shape the fix must keep))
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #733: a sink helper reading a share's payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ count sink ( Rc ( Vec u ) ) h → i { ^ ( vec_len [u] ( rc_get [( Vec u )] h ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( nurl_println_int ( count r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
