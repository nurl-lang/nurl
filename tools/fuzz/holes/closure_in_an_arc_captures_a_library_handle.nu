// closure_in_an_arc_captures_a_library_handle: a closure capturing a PNCounter, kept in an Arc and run by two threads at once: the closure type says nothing of its captures, so the Arc's Sync question passed, and both threads changed the one counter with no lock.
// Closed: a capture that may cross but is not Sync is a `$` atom of the closure's capture set, decided where the closure is kept in a handle several threads run it from (an Arc, a handle asserted `% Sync` — a server's handler): rejected there.
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h339 | a closure capturing a PNCounter kept in an Arc and run by two threads at once: a capture that is not Sync is rejected where the closure is kept in a handle several threads run it from
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v i ) f \ i k → v { ( pncounter_inc a k 1 ) }
    : ( Arc ( @ v i ) ) p ( arc_new [( @ v i )] f )
    : ( Arc ( @ v i ) ) p2 ( arc_clone [( @ v i )] p )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : ( @ v i ) g ( arc_get [( @ v i )] p2 )
        : ~ i k 0
        ~ < k 20000 { ( g k ) = k + k 1 }
    } )
    : ( @ v i ) h ( arc_get [( @ v i )] p )
    : ~ i k 0
    ~ < k 20000 { ( h + k 100000 ) = k + k 1 }
    ?? t { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
