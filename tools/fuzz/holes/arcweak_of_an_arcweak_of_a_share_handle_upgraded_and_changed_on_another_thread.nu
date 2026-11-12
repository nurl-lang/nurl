// arcweak_of_an_arcweak_of_a_share_handle_upgraded_and_changed_on_another_thread: an `( ArcWeak ( ArcWeak PNCounter ) )` is captured by a `thread_spawn` closure, which upgrades the outer weak handle, then the inner one, and increments the counter while the spawner increments it through its own Arc. A `PNCounter` is Send but not Sync: `( Arc PNCounter )` itself may not cross, however many weak handles stand in front of it.
// main: accepted — below an `ArcWeak` the walk asked for Send, at every depth (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( ArcWeak ( ArcWeak PNCounter ) )` captured by a spawned closure and upgraded twice there: each ArcWeak on the way is its Arc, and the payload at the end is held to Sync (agora #690)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/option.nu`
$ `stdlib/dist/crdt.nu`

@ bump ( Arc PNCounter ) a i lane i n → v {
    : ~ i k 0
    ~ < k n {
        ( pncounter_inc ( arc_get [PNCounter] a ) + * lane 100000 k 1 )
        = k + k 1
    }
}

@ main → i {
    : ( Arc PNCounter ) a ( arc_new [PNCounter] ( pncounter_new ) )
    : ( Arc ( ArcWeak PNCounter ) ) holder ( arc_new [( ArcWeak PNCounter )] ( arc_downgrade [PNCounter] a ) )
    : ( ArcWeak ( ArcWeak PNCounter ) ) ww ( arc_downgrade [( ArcWeak PNCounter )] holder )
    ?? ( thread_spawn \ → v {
        ?? ( arc_weak_upgrade [( ArcWeak PNCounter )] ww ) {
            T outer → {
                ?? ( arc_weak_upgrade [PNCounter] ( arc_get [( ArcWeak PNCounter )] outer ) ) {
                    T inner → { ( bump inner 1 3000 ) }
                    F → {}
                }
            }
            F → {}
        }
    } ) {
        T t → {
            ( bump a 2 3000 )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ 0
}
