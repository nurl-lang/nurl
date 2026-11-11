// diag_sync_handle_beside_plain_field.nu — what a handle that synchronises
// itself does not excuse (docs/MEMORY.md §6.5; agora #639). A function a
// thread-shared closure hands its captured struct to may send on the
// struct's Channel — the Channel's own change, under its own lock
// (thread_sync_handle_through_calls.nu) — but the plain Vec beside it is
// still one buffer every thread would grow at once.

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
    : App app @ App { ( chan_new [i] ) ( vec_new [i] ) }
    : ( @ v i ) work \ i k → v { ( note app k ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
