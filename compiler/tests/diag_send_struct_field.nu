// diag_send_struct_field.nu
// Send is a property of a type's whole GRAPH, not of its spelling.
// The Rc here is one struct field away from the capture — the old
// name-matching check ("is this capture spelled Rc?") waved it through,
// and the resulting program raced on the refcount exactly as if the Rc
// had been captured directly. The diagnostic must name `Rc` as the
// reason while naming `h` as the capture.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

: Holder { ( Rc i ) r }

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : Holder h @ Holder { shared }
    : ( @ v ) work \ → v { : Holder c h }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
