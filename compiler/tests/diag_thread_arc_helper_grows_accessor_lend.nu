// diag_thread_arc_helper_grows_accessor_lend.nu — an Arc's payload is
// frozen through every handle read out of it (docs/MEMORY.md §6.5; agora
// #646). A function handed the payload pushes to what an accessor lends
// out of it: the accessor's result views the payload's own Vec, which
// every clone's thread reads with no lock.

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) log i n }

@ log_of App a → ( Vec i ) { ^ . a log }

// Keeps a log — through the accessor.
@ note App a i k → v { ( vec_push [i] ( log_of a ) k ) }

@ main → i {
    : ( Arc App ) held ( arc_new [App] @ App { ( vec_new [i] ) 1 } )
    ( note ( arc_get [App] held ) 5 )
    ^ 0
}
