// H333: two copies of one library handle on two threads — a binding read out of a struct's field (`: PNCounter mine . h c`) kept by the spawner while `h` went to the thread — changed one state with no lock (the shape agora #66 was found with).
// Closed: the field read is a borrow of `h.c` (h331's rule), and the thread's closure takes `h` along: reading `mine` after the spawn is rejected. (A copy the spawner keeps by other means is still open: tools/fuzz/holes/open/.)
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter mine . h c
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc . h c k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc mine + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value mine ) 256
}
