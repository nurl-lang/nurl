// option_parameter_payload_stored_into_a_field_of_a_local_read_runs_clean: a `??` payload of an option parameter stored into `. w a` and only read
// Closed: only a change of the payload through the local is summarised (agora #793): the shape the fix must keep.
// main 977a74c: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #793: a ?? payload of an option parameter stored into . w a and only read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ ch ? ( Rc ( Vec u ) ) oh → v {
    : ~ W w @ W { ( rc_new [( Vec u )] ( vec_new [u] ) ) }
    ?? oh { T h → { = . w a h } F → {} }
    ( nurl_println_int ( vec_len [u] ( rc_get [( Vec u )] . w a ) ) )
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
