// borrow_ret_alias_forward.nu — the returned-handle summary at a
// call to a callee defined BELOW it (docs/MEMORY.md §2.2 / §6.4).
//
// `pick` hands its argument back, so `a` and `b` name one allocation
// and freeing both is a double free. Under the ownership rules the call
// result is a borrow of what the callee may hand back, so releasing it
// is an error by default, whether `pick` is defined above or below the
// call. Definition order used to decide whether the double free was
// visible at all.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ( pick a )
    ( vec_free [i] b )
    ( vec_free [i] a )
    ^ 0
}

@ pick ( Vec i ) v → ( Vec i ) {
    ^ v
}
