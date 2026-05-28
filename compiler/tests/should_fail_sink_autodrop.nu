// should_fail_sink_autodrop.nu — `sink` does not currently support
// arguments the compiler auto-drops (an owned string
// from an allocating call, an owned slice, a Drop-trait value, a
// struct with owned fields). Transferring the auto-drop obligation
// to the callee is deferred; until then passing such a value to a
// `sink` parameter is rejected at the call site rather than risking
// a double free. Expect COMPILE FAIL.

@ consume sink s text → v {}

@ main → i {
    // `msg` owns a freshly allocated string — auto-dropped at scope
    // exit. It cannot yet be handed to a `sink` parameter.
    : s msg ( nurl_str_cat `hello, ` `world` )
    ( consume msg )
    ^ 0
}
