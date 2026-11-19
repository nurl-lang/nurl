// option_parameter_payload_stored_into_a_field_of_a_local: a `??` payload of an option parameter stored into `. w a`, then the payload replaced through it
// Closed: a parameter that may share an Rc, put into a local by any spelling — a helper keeping it or a share of it into another argument or a field of an `inout` struct, a view local, a container reached through a call, a `??` payload of an option parameter — leads to the parameter in the function's drop summary (agora #793).
// main 977a74c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #793: a ?? payload of an option parameter stored into . w a, then the payload replaced through it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ ch ? ( Rc ( Vec u ) ) oh → v {
    : ~ W w @ W { ( rc_new [( Vec u )] ( vec_new [u] ) ) }
    ?? oh { T h → { = . w a h } F → {} }
    ( rc_set [( Vec u )] . w a ( vec_new [u] ) )
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
