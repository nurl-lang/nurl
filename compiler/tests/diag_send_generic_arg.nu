// diag_send_generic_arg.nu
// `( Arc ( Rc i ) )` — an atomic refcount wrapped around a non-atomic
// one. Every generic container in NURL lowers to a one-pointer handle
// (`: Arc [T] { s ctl }`), so walking the fields finds one `i8*` and
// learns nothing; the element type survives only in the monomorph's
// mangled name, `%Arc__Rc__i64`. This is the test that the walk reads
// it.
//
// It is also where Arc's payload faces the HARDER question: an Arc
// exists to be shared, so `T` must be Sync, not merely Send.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`

@ main → i {
    : ( Rc i ) inner ( rc_new [i] 0 )
    : ( Arc ( Rc i ) ) a ( arc_new [( Rc i )] inner )
    : ( @ v ) work \ → v { : ( Rc i ) g ( arc_get [( Rc i )] a ) }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
