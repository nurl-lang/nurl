// generic_struct_holding_an_rc_behind_a_locked_in_an_arc_cloned_by_a_thread: a `( Wrap i )` of `: Wrap [T] { ( Rc T ) r }` sits behind a `Locked` in an `Arc`; a thread holding a clone of the Arc clones the `Rc` out under the lock while the spawner clones and drops its own share outside it. The lock guards the struct, not the count the `Rc` points at.
// main: accepted — a `Locked`'s value must be Send, and the walk found no fields under the generic's bare name (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Arc ( Locked ( Wrap i ) ) )` of `: Wrap [T] { ( Rc T ) r }` captured by a spawned closure, which clones the Rc out under the lock: a generic struct is walked through the fields its instance has (agora #675)
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Wrap [T] { ( Rc T ) r }

@ churn ( Arc ( Locked ( Wrap i ) ) ) a i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ( locked_update [( Wrap i )] ( arc_get [( Locked ( Wrap i ) )] a ) \ inout ( Wrap i ) w → v { ( vec_push [( Rc i )] cs ( rc_clone [i] . w r ) ) } )
            = j + j 1
        }
        = k + k 1
    }
}

@ own ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r ) ) = j + j 1 }
        = k + k 1
    }
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Arc ( Locked ( Wrap i ) ) ) a ( arc_new [( Locked ( Wrap i ) )] ( locked_new [( Wrap i )] @ ( Wrap i ) { ( rc_clone [i] r ) } ) )
    : ( Arc ( Locked ( Wrap i ) ) ) theirs ( arc_clone [( Locked ( Wrap i ) )] a )
    ?? ( thread_spawn \ → v { ( churn theirs 20000 ) } ) {
        T t → { ( own r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 2
}
