// closure_over_an_rc_handed_to_a_send_bound_is_refused: a closure over an Rc whose code hands back a `?( Rc i )`, the argument of a `[X: Send]` generic that runs it on a thread
// Guard for agora #788's fix: the bound no longer reads a closure's signature, and the closure's captures refuse it where the generic runs its parameter on a thread.
// main ad17e78c: refused, by the closure's signature ("does not satisfy the bound X: Send").
// map: §6.5 | A3 | rejected | - | agora #788 guard: a closure over an Rc given to a Send bound is refused by its captures, whatever its signature names
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ churn_local ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r ) ) = j + j 1 }
        = k + k 1
    }
}

@ run_n ( @ ?( Rc i ) i ) f i n → v { : ~ i k 0 ~ < k n { : ?( Rc i ) z ( f k ) = k + k 1 } }

@ go [X : Send] X x ( @ v X ) run → v {
    ?? ( thread_spawn \ → v { ( run x ) } ) { T t → { ( thread_join t ) } F _ → {} }
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r2 ) ) = j + j 1 }
        ^ @ ?( Rc i ) { T ( rc_clone [i] r2 ) }
    }
    ( go [( @ ?( Rc i ) i )] f \ ( @ ?( Rc i ) i ) g → v { ( run_n g 20000 ) } )
    ( churn_local r 20000 )
    ^ 0
}
