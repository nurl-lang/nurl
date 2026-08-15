// diag_send_fiber_spawn.nu
// A fiber is not a thread, but the runtime is M:N — a fiber runs on
// whichever worker pthread picks it up, so a captured Rc is the same
// undefined behaviour, and stays undefined whether or not a given run
// happens to schedule the fiber elsewhere. `spawn` is a thread
// boundary and must be checked like one.

$ `stdlib/std/async.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : ( @ v ) work \ → v { : i x ( rc_get [i] shared ) }
    ( runtime_init 4 )
    : Fiber f ( spawn work )
    ^ 0
}
