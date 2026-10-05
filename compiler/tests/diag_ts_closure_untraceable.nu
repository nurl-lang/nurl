// diag_ts_closure_untraceable.nu — a closure stored into a thread-shared
// handle's state must be one whose captures the compiler can follow: a
// capture leading back to the handle would close a cycle of counts that
// nothing frees (docs/MEMORY.md §7.7). A closure that comes out of a call
// through a closure value cannot be followed, so the store is rejected and
// the message names the handle and how to restructure it.
$ `stdlib/dist/job.nu`

@ register JobNode node ( @ ( @ ( Vec u ) ( Vec u ) ) ) make → v {
    ( job_register node 1 ( make ) )
}

@ main → i {
    ^ 0
}
