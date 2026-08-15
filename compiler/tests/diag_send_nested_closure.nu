// diag_send_nested_closure.nu
// The detached closure captures no Rc — it captures another CLOSURE
// that does. A closure lowers to a fn/env pair whose env contents are
// invisible in the type, so no amount of type walking finds the Rc
// here; the answer is the verdict already recorded for the inner
// closure when it was built, propagated outward at the capture.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : ( @ v ) inner \ → v { : i x ( rc_get [i] shared ) }
    : ( @ v ) work \ → v { ( inner ) }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
