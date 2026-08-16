// borrow_strict_ret_alias_forward.nu — the returned-handle summary at a
// call to a callee defined BELOW it (docs/MEMORY.md §2.2 / §6.4).
//
// `pick` hands its argument back, so `a` and `b` name one allocation
// and freeing both is a double free. The summary is a MAYBE (the
// callee could equally have returned something fresh), so like every
// conditional double-free it is reported under --strict-borrowck only
// (§6.2) — borrow_strict_ret_alias.nu pins the defined-above form.
// Here `pick` is defined after the call, which used to mean no
// diagnostic in either mode: definition order decided whether the
// double free was visible at all.
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
