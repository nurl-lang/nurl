// rc_payload_bound_then_sliced_while_another_handle_pushes: the payload of an Rc bound, sliced, then grown through a clone of the Rc; the slice is read.
// Closed: a call that may move the payload's buffer through another handle on the same Rc value ends the views reached through the payload as well as the views of the Rc (bck_view_end_ind): a slice of a binding of the payload points into the buffer the call moves.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §6.5 | A1 | rejected | - | agora #169: a bound Rc payload's slice outlives a push through a clone of the Rc
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    : ( Vec i ) p ( rc_get [( Vec i )] r )
    : ( Slice i ) sl ( slice_from_vec [i] p )
    : ~ i k 0
    ~ < k 100 { ( vec_push [i] ( rc_get [( Vec i )] r2 ) k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
