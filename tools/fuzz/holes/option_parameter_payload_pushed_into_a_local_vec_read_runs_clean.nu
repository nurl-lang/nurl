// option_parameter_payload_pushed_into_a_local_vec_read_runs_clean: a `??` payload of an option parameter pushed into a local Vec and only read
// Closed: only a change of the payload through the local is summarised (agora #793): the shape the fix must keep.
// main 977a74c: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #793: a ?? payload of an option parameter pushed into a local Vec and only read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ ch ? ( Rc ( Vec u ) ) oh → v {
    : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] )
    ?? oh { T h → ( vec_push [( Rc ( Vec u ) )] xs h ) F → {} }
    ( nurl_println_int ( vec_len [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ) ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ?( Rc ( Vec u ) ) o @ ?( Rc ( Vec u ) ) { T r }
    ( ch o )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
