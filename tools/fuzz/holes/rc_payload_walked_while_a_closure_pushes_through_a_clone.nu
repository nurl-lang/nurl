// rc_payload_walked_while_a_closure_pushes_through_a_clone: agora #169 — a mutator called on a value an accessor lends (rc_payload_walked_while_a_closure_pushes_through_a_clone).
// Closed: the call changes what the accessor lends from (agora #169).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h585 | agora #169: rc_payload_walked_while_a_closure_pushes_through_a_clone
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 16 {
        ( vec_push [i] v k )
        = k + k 1
    }
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    ( vec_each [i] ( rc_get [( Vec i )] r ) \ i x → v { ( vec_push [i] ( rc_get [( Vec i )] r2 ) x ) } )
    ^ 0
}
