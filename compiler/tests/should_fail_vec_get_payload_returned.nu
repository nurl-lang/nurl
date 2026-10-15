// should_fail_vec_get_payload_returned.nu — h270.
//
// `getv` hands back the payload of a `vec_get` on its parameter's field
// (`^ x` in the arm): the caller's binding is a view of its argument, so
// emptying the argument's Vec before the view is read is rejected, as
// the same `vec_get` written in the caller already was.
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Tz { ( Vec f ) data }
: Tp { ( Vec Tz ) vals }

@ tz_empty → Tz { ^ @ Tz { ( vec_new [f] ) } }

@ getv Tp tp i id → Tz {
    ?? ( vec_get [Tz] . tp vals id ) { T x → { ^ x } F → { ^ ( tz_empty ) } }
}

@ cut Tp tp → v { : b _t ( vec_truncate [Tz] . tp vals 0 ) }

@ main → i {
    : Tp tp @ Tp { ( vec_new [Tz] ) }
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    ( vec_push [Tz] . tp vals @ Tz { d } )
    : Tz t ( getv tp 0 )
    ( cut tp )
    ( nurl_println_int ( vec_len [f] . t data ) )
    ^ 0
}
