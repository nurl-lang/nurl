// An RwLocked lets several threads read its value at once, so the value
// faces the Sync question where the RwLocked crosses, as an Arc's payload
// does: a PNCounter, whose copies are one state changed in place with no
// lock, is not Sync (agora #121, h357).
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rwlock.nu`

@ main → i {
    : ( RwLocked PNCounter ) l ( rw_new [PNCounter] ( pncounter_new ) )
    : ( @ v ) body \ → v { ( rw_update [PNCounter] l \ inout PNCounter c → v { ( pncounter_inc c 1 1 ) } ) }
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
    ^ 0
}
