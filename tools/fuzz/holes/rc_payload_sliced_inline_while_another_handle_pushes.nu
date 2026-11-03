// rc_payload_sliced_inline_while_another_handle_pushes: the payload of an Rc sliced inline (slice_from_vec of rc_get), then grown through a clone of the Rc; the slice is read.
// Guard: a part of an argument read inline is reached through the argument's element; a push through another handle on the same Rc value ends what is reached that way too (bck_view_end_ind).
// main 4f15689: rejected.
// map: §6.5 | A1 | rejected | - | agora #169: an inline slice of an Rc payload outlives a push through a clone of the Rc
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Rc ( Vec i ) ) r ( rc_new [( Vec i )] v )
    : ( Rc ( Vec i ) ) r2 ( rc_clone [( Vec i )] r )
    : ( Slice i ) sl ( slice_from_vec [i] ( rc_get [( Vec i )] r ) )
    : ~ i k 0
    ~ < k 100 { ( vec_push [i] ( rc_get [( Vec i )] r2 ) k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
