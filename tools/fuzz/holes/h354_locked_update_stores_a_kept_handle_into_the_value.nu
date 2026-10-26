// H354: a closure run under a Locked's lock assigned a handle the spawner kept into the Locked's value (`locked_update l \ inout PNCounter x → v { = x b }`): the lock's holders and the spawner then changed one counter, the spawner with no lock. (The assignment also stored `b` as is, two owners counted as one — h346.)
// Closed: the value is checked again before the lock is let go (locked_with, locked_update, locked_apply, locked_await; mem_send_check, h349), and `b` is copied in (h346).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter b ( pncounter_new )
    : ( Locked PNCounter ) l ( locked_new [PNCounter] ( pncounter_new ) )
    ( locked_update [PNCounter] l \ inout PNCounter x → v { = x b } )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { : PNCounter c ( locked_take [PNCounter] l ) ( pncounter_inc c k 1 ) ( locked_restore [PNCounter] l c ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
