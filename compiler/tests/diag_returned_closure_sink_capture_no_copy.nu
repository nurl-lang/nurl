// diag_returned_closure_sink_capture_no_copy.nu — the body of a closure
// returned right here hands its capture, a Vec of `% Drop` values (no
// Clone), to a `sink` parameter. The closure may run again, and nothing
// can give the callee a copy: the next call would hand over what this one
// released (agora #463).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { String name }

% Drop Res {
    @ drop Res r → v { ( nurl_println `dropped` ) }
}

@ eat sink ( Vec Res ) v → i { ^ ( vec_len [Res] v ) }

@ cap → ( @ i ) {
    : ( Vec Res ) v ( vec_new [Res] )
    ( vec_push [Res] v @ Res { ( string_from `a resource name long enough for the heap` ) } )
    ^ \ → i { ^ ( eat v ) }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
