// diag_thread_share_handle_captured_kept.nu
// A library handle whose copies are one state (a PNCounter: a counted
// block changed in place, with no lock) moves into a thread's closure
// as a Vec does: the spawner may not change its own copy afterwards.
// Only a share handle asserted `% Sync` (a Channel, a Locked, an Atomic,
// a TcpListener…) or an Arc stays the spawner's too (h336).

$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v ) body \ → v { ( pncounter_inc a 1 1 ) }
    ?? ( thread_spawn body ) {
        T t → {
            ( pncounter_inc a 2 1 )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ 0
}
