// borrow_keep_beside_closure_arg.nu — a value handed to a callee that keeps
// it is gone, also when a closure literal is another argument of the call.
//
// `( attach srv m \ → v {} )` keeps `m` (attach pushes it into the server's
// Vec), so freeing `m` afterwards releases it a second time. The keep was
// stashed for the statement before the closure argument was compiled, and
// the closure body — its own function — drained that stash into its own
// statement list: the enclosing function never learned `m` had gone into
// an owner, and the double free compiled clean (mcp_server_set_task_store
// had exactly this shape).

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Srv { ( Vec Mutex ) ms }

@ attach Srv s Mutex m ( @ v ) hook → v {
    ( vec_push [Mutex] . s ms m )
    ( hook )
}

@ main → i {
    : Srv s @ Srv { ( vec_new [Mutex] ) }
    : Mutex m ( mutex_new )
    ( attach s m \ → v {} )
    ( mutex_free m )
    ^ 0
}
