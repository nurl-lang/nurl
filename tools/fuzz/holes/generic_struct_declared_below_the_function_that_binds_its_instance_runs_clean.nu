// generic_struct_declared_below_the_function_that_binds_its_instance_runs_clean: `: Wrap [T] { ( Rc T ) r }` is declared at the end of the file; `hold` above it binds two `( Wrap i )` over shares of one `Rc`, reads them through a generic function and lets them go — one thread, nothing wrong with it.
// main: accepted — and leaked: the bindings were of a type with no fields where `hold` was compiled, so nothing was released at its end (LeakSanitizer: 32 bytes).
// The control for generic_struct_declared_below_the_function_that_hands_its_instance_to_a_thread.
// map: §6.5 | A3 | runs-clean | - | guard: `( Wrap i )` bound above `: Wrap [T] { ( Rc T ) r }` on one thread: the instance has its fields where it is named, and its binding releases what it holds (agora #716)
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`

@ hold sink ( Rc i ) a sink ( Rc i ) b → i {
    : ( Wrap i ) h2 ( mk a )
    : ( Wrap i ) h3 ( mk b )
    ^ + ( churn h2 3 ) ( churn h3 3 )
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
    : i z ( hold ( rc_clone [i] r ) ( rc_clone [i] r ) )
    ^ - ( rc_strong [i] r ) 1
}

: Wrap [T] { ( Rc T ) r }

@ share [A] ( Wrap A ) w → ( Rc A ) { ^ ( rc_clone [A] . w r ) }
