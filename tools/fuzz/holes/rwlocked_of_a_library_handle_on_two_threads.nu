// rwlocked_of_a_library_handle_on_two_threads: an RwLocked over a library handle whose copies are one state (`( RwLocked PNCounter )`) crossed to a thread while the spawner kept a share of the counter: a writer under the lock and the spawner with no lock changed it together — and several readers may reach an RwLocked's value at once.
// Closed: an RwLocked's value faces the Sync question where the RwLocked crosses, as an Arc's payload does; a handle whose copies are one state is not Sync.
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h357 | an RwLocked over a PNCounter crossed to a thread: an RwLocked's value faces the Sync question, as an Arc's payload does
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rwlock.nu`

@ main → i {
    : PNCounter b ( pncounter_new )
    : ( RwLocked PNCounter ) l ( rw_new [PNCounter] ( PNCounter_share b ) )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( rw_update [PNCounter] l \ inout PNCounter c → v { ( pncounter_inc c k 1 ) } ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
