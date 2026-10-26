// diag_sync_closure_in_arc.nu
// A closure kept in an Arc is run by every thread holding a copy, at
// once: what it captures must be Sync, not only Send. Its type says
// nothing of its captures, so the capture set decides where the closure
// is kept (h339).

$ `stdlib/std/arc.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : PNCounter hits ( pncounter_new )
    : ( @ v i ) count \ i k → v { ( pncounter_inc hits k 1 ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] count )
    ^ 0
}
