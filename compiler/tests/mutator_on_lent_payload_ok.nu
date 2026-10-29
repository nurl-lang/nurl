// mutator_on_lent_payload_ok.nu — mutators called on a value an accessor
// lends (agora #169) with no view of it held across the call: pushing
// through `rc_get` and a clone of the Rc, then reading the payload anew.
// It runs clean, and every clone sees one payload.

$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    : ~ i k 0
    ~ < k 40 {
        ( vec_push [i] ( rc_get [( Vec i )] r ) k )
        ( vec_push [i] ( rc_get [( Vec i )] r2 ) k )
        = k + k 1
    }
    ( nurl_println_int ( vec_len [i] ( rc_get [( Vec i )] r ) ) )
    ( nurl_println_int ( vec_at [i] ( rc_get [( Vec i )] r2 ) 79 ) )
    ^ 0
}
