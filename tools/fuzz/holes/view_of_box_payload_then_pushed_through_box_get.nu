// view_of_box_payload_then_pushed_through_box_get: agora #169 — a mutator called on a value an accessor lends (view_of_box_payload_then_pushed_through_box_get).
// Closed: the call changes what the accessor lends from (agora #169).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h589 | agora #169: view_of_box_payload_then_pushed_through_box_get
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Box ( Vec i ) ) b ( box_new [( Vec i )] v )
    : ( Slice i ) sl ( slice_from_vec [i] ( box_get [( Vec i )] b ) )
    : ~ i k 0
    ~ < k 64 {
        ( vec_push [i] ( box_get [( Vec i )] b ) k )
        = k + k 1
    }
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
