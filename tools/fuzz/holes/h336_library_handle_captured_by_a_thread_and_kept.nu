// H336: two copies of one library handle on two threads — a thread's closure captured a PNCounter (a handle whose copies are one state, changed in place with no lock) and the spawner kept changing its own copy.
// Closed: a detached closure moves every capture whose copy is not a share made to be reached from two threads at once (a share handle asserted `% Sync`, or an Arc): the PNCounter goes with the thread, and the spawner's use after the spawn is rejected.
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value a ) 256
}
