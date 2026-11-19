// parameter_pushed_into_an_element_view_local: a parameter pushed into `x0`, a `( vec_at xss 0 )` binding, then the payload replaced through `xss`
// Closed: a parameter that may share an Rc, put into a local by any spelling — a helper keeping it or a share of it into another argument or a field of an `inout` struct, a view local, a container reached through a call, a `??` payload of an option parameter — leads to the parameter in the function's drop summary (agora #793).
// main 977a74c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #793: a parameter pushed into x0, a ( vec_at xss 0 ) binding, then the payload replaced through xss
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ( Rc ( Vec u ) ) h → v {
    : ( Vec ( Vec ( Rc ( Vec u ) ) ) ) xss ( vec_new [( Vec ( Rc ( Vec u ) ) )] )
    ( vec_push [( Vec ( Rc ( Vec u ) ) )] xss ( vec_new [( Rc ( Vec u ) )] ) )
    : ( Vec ( Rc ( Vec u ) ) ) x0 ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 )
    ( vec_push [( Rc ( Vec u ) )] x0 h )
    ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 ) 0 ) ( vec_new [u] ) )
}

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
