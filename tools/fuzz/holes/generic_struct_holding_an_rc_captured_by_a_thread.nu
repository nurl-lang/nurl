// generic_struct_holding_an_rc_captured_by_a_thread: a generic struct `: Wrap [T] { ( Rc T ) r }` holds a share of an `Rc`; one `( Wrap i )` is captured by a `thread_spawn` closure while the spawner keeps another, and both threads clone and drop shares of the one unsynchronised count.
// main: accepted — the Send walk looked a generic instance's fields up under the generic's bare name, where an instance registers them under its own (`Wrap__i64`), so it saw a struct with no fields (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Wrap i )` of `: Wrap [T] { ( Rc T ) r }` captured by a spawned closure: a generic struct is walked through the fields its instance has (agora #675)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Wrap [T] { ( Rc T ) r }

@ churn ( Wrap i ) h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ( vec_push [( Rc i )] cs ( rc_clone [i] . h r ) )
            = j + j 1
        }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Wrap i ) h2 @ ( Wrap i ) { ( rc_clone [i] r ) }
    : ( Wrap i ) h3 @ ( Wrap i ) { ( rc_clone [i] r ) }
    ?? ( thread_spawn \ → v { ( churn h3 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 3
}
