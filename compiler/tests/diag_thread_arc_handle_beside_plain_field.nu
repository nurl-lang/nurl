// diag_thread_arc_handle_beside_plain_field.nu — an Arc's payload is
// frozen but for what synchronises itself (docs/MEMORY.md §6.5; agora
// #639). A function handed the payload may send on its Channel field
// (thread_sync_handle_through_calls.nu); one that also grows the plain Vec
// beside it changes memory every clone's thread reads with no lock.

$ `stdlib/std/arc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log }

// Sends — and keeps a log.
@ note App a i k → v {
    : b sent ( chan_send [i] . a jobs k )
    ( vec_push [i] . a log k )
}

@ main → i {
    : ( Arc App ) held ( arc_new [App] @ App { ( chan_new [i] ) ( vec_new [i] ) } )
    ( note ( arc_get [App] held ) 5 )
    ^ 0
}
