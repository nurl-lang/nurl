// library_handle_put_in_a_locked_while_a_share_stays: a library handle put into a Locked (`( locked_new a )`) while the spawner kept a share of it: the thread that checked it out of the lock and the spawner, with no lock, changed one counter together.
// Closed: a value going into a Locked (locked_new, locked_set, locked_restore) is checked to carry every owner of such a handle (mem_send_check, h349).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | B | runs-clean | h353 | a PNCounter put into a Locked while the spawner kept a share: a value going into a Locked is checked and the crossing panics
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : ( Locked PNCounter ) l ( locked_new [PNCounter] a )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { : PNCounter c ( locked_take [PNCounter] l ) ( pncounter_inc c k 1 ) ( locked_restore [PNCounter] l c ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
