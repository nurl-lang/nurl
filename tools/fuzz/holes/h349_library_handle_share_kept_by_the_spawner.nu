// H349: a share of a library handle made before the handle moved to a thread (`: PNCounter b ( PNCounter_share a )`, then a thread's closure took `a`) stayed with the spawner, and both threads changed one counter in place with no lock: the checker does not connect the share to the owner that moved.
// Closed: a crossing to another thread (thread_spawn, spawn, chan_send, a Locked's value going in or coming out, a pool's) checks at run time that every handle whose copies are one state it carries has no other owner (`mem_send_check`), and panics naming the handle otherwise (memory-safe).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
