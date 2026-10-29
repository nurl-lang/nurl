// H587: agora #169 — a mutator called on a value an accessor lends (view_of_rc_payload_then_pushed_through_a_clone).
// Closed: the call changes what the accessor lends from (agora #169).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    : ( Slice i ) sl ( slice_from_vec [i] ( rc_get [( Vec i )] r ) )
    : ~ i k 0
    ~ < k 64 {
        ( vec_push [i] ( rc_get [( Vec i )] r2 ) k )
        = k + k 1
    }
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
