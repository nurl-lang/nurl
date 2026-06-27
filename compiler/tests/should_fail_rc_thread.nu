// should_fail_rc_thread.nu
// Sending an Rc (non-atomic refcount) across a thread boundary is a data race
// on its control-block count. The compiler must reject a thread_spawn closure
// that captures an Rc, pointing at the thread-safe Arc. Here `work` captures
// `shared` (an Rc) and is detached onto a worker thread → compile error.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : ( @ v ) work \ → v {
        : i x ( rc_get [i] shared )  // captures the Rc handle
        ( rc_set [i] shared + x 1 )
    }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
