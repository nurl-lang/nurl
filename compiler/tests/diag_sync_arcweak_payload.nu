// An ArcWeak upgrades to an Arc on the same payload, so it crosses a thread
// only where that Arc may: its payload must be Sync as well as Send. A
// PNCounter, whose copies are one state changed in place with no lock, is
// not (agora #690).
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Arc PNCounter ) a ( arc_new [PNCounter] ( pncounter_new ) )
    : ( ArcWeak PNCounter ) w ( arc_downgrade [PNCounter] a )
    : ( @ v ) body \ → v {
        ?? ( arc_weak_upgrade [PNCounter] w ) {
            T up → { ( pncounter_inc ( arc_get [PNCounter] up ) 1 1 ) }
            F → {}
        }
    }
    ?? ( thread_spawn body ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
