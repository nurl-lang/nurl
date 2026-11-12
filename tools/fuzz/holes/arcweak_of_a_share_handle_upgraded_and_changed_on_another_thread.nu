// arcweak_of_a_share_handle_upgraded_and_changed_on_another_thread: an `( ArcWeak PNCounter )` is captured by a `thread_spawn` closure, which upgrades it to an `( Arc PNCounter )` and increments the counter while the spawner increments it through its own Arc. A `PNCounter` is Send but not Sync: `( Arc PNCounter )` itself may not cross.
// main: accepted — the walk asked whether the payload is Sync below an `Arc` and an `RwLocked` only; below an `ArcWeak` it asked for Send (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( ArcWeak PNCounter )` captured by a spawned closure and upgraded there: an ArcWeak crosses a thread only where the Arc it upgrades to may (agora #690)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : ( Arc PNCounter ) a ( arc_new [PNCounter] ( pncounter_new ) )
    : ( ArcWeak PNCounter ) w ( arc_downgrade [PNCounter] a )
    : ( @ v ) body \ → v {
        ?? ( arc_weak_upgrade [PNCounter] w ) {
            T up → {
                : ~ i k 0
                ~ < k 3000 { ( pncounter_inc ( arc_get [PNCounter] up ) k 1 ) = k + k 1 }
            }
            F → {}
        }
    }
    ?? ( thread_spawn body ) {
        T th → {
            : ~ i k 0
            ~ < k 3000 { ( pncounter_inc ( arc_get [PNCounter] a ) + k 5000 1 ) = k + k 1 }
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ 0
}
