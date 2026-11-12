// rc_as_a_later_type_argument_after_a_mutex_captured_by_a_thread: `: Two [A B] { A first B second }` — a `( Two Mutex ( Rc i ) )` holding a share of an `Rc` is captured by a `thread_spawn` closure while the spawner keeps another share, and both threads clone and drop shares of the one unsynchronised count.
// main: accepted — it read a generic's arguments off the mangled name as one chain and stopped at a first argument marked Send, so the `Rc` behind it was never asked about (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Two Mutex ( Rc i ) )` captured by a spawned closure: every type argument of a generic is asked, whatever stands before it (agora #683)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: Two [A B] { A first B second }

@ churn ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ( vec_push [( Rc i )] cs ( rc_clone [i] r ) )
            = j + j 1
        }
        = k + k 1
    }
}

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Two Mutex ( Rc i ) ) h @ ( Two Mutex ( Rc i ) ) { ( mutex_new ) ( rc_clone [i] mine ) }
    ?? ( thread_spawn \ → v { ( churn . h second 20000 ) } ) {
        T t → {
            ( churn mine 20000 )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - ( rc_strong [i] mine ) 2
}
