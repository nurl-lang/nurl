// literal_of_a_parameter_pushed_by_a_helper_into_another_argument: a helper pushing `@ W { h }` of its Rc parameter into another argument, then the payload replaced through it
// Closed: a parameter that may share an Rc, put into a local by any spelling — a helper keeping it or a share of it into another argument or a field of an `inout` struct, a view local, a container reached through a call, a `??` payload of an option parameter — leads to the parameter in the function's drop summary (agora #793).
// main 977a74c: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #793: a helper pushing @ W { h } of its Rc parameter into another argument, then the payload replaced through it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: W { ( Rc ( Vec u ) ) a }

@ setw W w → v { ( rc_set [( Vec u )] . w a ( vec_new [u] ) ) }

@ addto2 ( Rc ( Vec u ) ) h ( Vec W ) ws → v { ( vec_push [W] ws @ W { h } ) }

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec W ) ws ( vec_new [W] ) ( addto2 h ws ) ( setw ( vec_at [W] ws 0 ) ) }

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
