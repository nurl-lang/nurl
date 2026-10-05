// diag_send_untraceable.nu — whether a closure may run on another thread is
// decided by following it back to where it was built. One that comes out of
// a call through a closure value cannot be followed, so detaching it is
// rejected, and the message says how to restructure: build it where it is
// handed over, or take it as a parameter so each caller's is checked.
$ `stdlib/std/async.nu`

@ run ( @ ( @ v ) ) make → v {
    : Fiber a ( spawn_joinable ( make ) )
    ( fiber_join a )
}

@ main → i {
    ^ 0
}
