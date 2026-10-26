// H355: `locked_get` copied a library handle out of a Locked — a share, the same state — and the caller changed it with no lock while the lock's holders changed it under the lock.
// Closed: locked_get checks its copy (mem_send_check, h349): a copy of a handle whose copies are one state is never handed out of the lock.
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Locked PNCounter ) l ( locked_new [PNCounter] ( pncounter_new ) )
    : PNCounter b ( locked_get [PNCounter] l )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { : PNCounter c ( locked_take [PNCounter] l ) ( pncounter_inc c k 1 ) ( locked_restore [PNCounter] l c ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
