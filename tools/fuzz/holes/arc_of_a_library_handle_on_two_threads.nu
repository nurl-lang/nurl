// arc_of_a_library_handle_on_two_threads: an `( Arc PNCounter )` shared by two threads: an Arc's payload must be Sync, and the derivation found nothing unsafe in a PNCounter's fields, but each `arc_get` copy is a share of one counter both threads changed with no lock.
// Closed: under a Sync question a share handle not asserted `% Sync` is not Sync (its copies are one state): the Arc's payload is rejected where it crosses.
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h338 | an ( Arc PNCounter ) shared by two threads: each arc_get copy is a share of one counter; under the Sync question a share handle not asserted % Sync is not Sync
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : ( Arc PNCounter ) p ( arc_new [PNCounter] ( pncounter_new ) )
    : ( Arc PNCounter ) p2 ( arc_clone [PNCounter] p )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : PNCounter g ( arc_get [PNCounter] p2 )
        : ~ i k 0
        ~ < k 20000 { ( pncounter_inc g k 1 ) = k + k 1 }
    } )
    : PNCounter h ( arc_get [PNCounter] p )
    : ~ i k 0
    ~ < k 20000 { ( pncounter_inc h + k 100000 1 ) = k + k 1 }
    ?? t { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
