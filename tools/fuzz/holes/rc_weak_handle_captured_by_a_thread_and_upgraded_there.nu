// rc_weak_handle_captured_by_a_thread_and_upgraded_there: a `( Weak i )` of an `Rc` is captured by a `thread_spawn` closure, which upgrades it — a clone of the `Rc` on the same unsynchronised count — while the spawner upgrades another `Weak` of the same `Rc`.
// main: accepted — the walk refused an `Rc` by name and knew nothing of its `Weak` (ASan: heap-use-after-free).
// map: §6.5 | A3 | rejected | - | `( Weak i )` captured by a spawned closure and upgraded there: an Rc's Weak shares the Rc's unsynchronised count and is no more Send than it (found beside agora #690)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ churn ( Weak i ) w i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ?? ( weak_upgrade [i] w ) {
                T x → { ( vec_push [( Rc i )] cs x ) }
                F → {}
            }
            = j + j 1
        }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Weak i ) w2 ( rc_downgrade [i] r )
    : ( Weak i ) w3 ( rc_downgrade [i] r )
    ?? ( thread_spawn \ → v { ( churn w3 20000 ) } ) {
        T t → { ( churn w2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 1
}
