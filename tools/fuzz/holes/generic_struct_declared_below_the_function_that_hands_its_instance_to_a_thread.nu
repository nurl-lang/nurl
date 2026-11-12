// generic_struct_declared_below_the_function_that_hands_its_instance_to_a_thread: `: Wrap [T] { ( Rc T ) r }` is declared at the end of the file, below every function that names `( Wrap i )`; `race` binds two of them over shares of one `Rc` and hands one to a `thread_spawn` closure, and both threads clone and drop shares of the one unsynchronised count.
// main: accepted — a template was learned by the same walk that makes the instances, so `( Wrap i )` above it named a type with no fields; the generic function below the template made the instance too late for `race`, whose capture was asked about a struct holding nothing (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Wrap i )` named above `: Wrap [T] { ( Rc T ) r }` and captured by a spawned closure: every generic struct template is collected before an instance is made (agora #716)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ race sink ( Rc i ) a sink ( Rc i ) b → v {
    : ( Wrap i ) h2 ( mk a )
    : ( Wrap i ) h3 ( mk b )
    ?? ( thread_spawn \ → v { ( churn h3 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
}

@ mk sink ( Rc i ) r → ( Wrap i ) { ^ @ ( Wrap i ) { r } }

@ churn ( Wrap i ) h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ( vec_push [( Rc i )] cs ( share [i] h ) )
            = j + j 1
        }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    ( race ( rc_clone [i] r ) ( rc_clone [i] r ) )
    ^ 0
}

: Wrap [T] { ( Rc T ) r }

@ share [A] ( Wrap A ) w → ( Rc A ) { ^ ( rc_clone [A] . w r ) }
