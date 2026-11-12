// vec_of_optional_rcs_captured_by_a_thread: a `( Vec ?( Rc i ) )` holding a share of an `Rc` is captured by a `thread_spawn` closure while the spawner keeps another such Vec; both threads clone and drop shares of the one unsynchronised count.
// main: accepted — the walk read a generic's type argument with a peel that knows named types only, so the option `?( Rc i )` was skipped (`( Vec ( Rc i ) )` and a bare `?( Rc i )` were refused) (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Vec ?( Rc i ) )` captured by a spawned closure: every type argument of a generic instance is walked as the type it is — option, result, slice (agora #683)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ churn ( Vec ? ( Rc i ) ) h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ?? ( vec_at [? ( Rc i )] h 0 ) {
                T x → { ( vec_push [( Rc i )] cs ( rc_clone [i] x ) ) }
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
    : ( Vec ? ( Rc i ) ) h2 ( vec_new [? ( Rc i )] )
    ( vec_push [? ( Rc i )] h2 @ ?( Rc i ) { T ( rc_clone [i] r ) } )
    : ( Vec ? ( Rc i ) ) h3 ( vec_new [? ( Rc i )] )
    ( vec_push [? ( Rc i )] h3 @ ?( Rc i ) { T ( rc_clone [i] r ) } )
    ?? ( thread_spawn \ → v { ( churn h3 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 3
}
