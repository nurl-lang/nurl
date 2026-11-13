// closure_over_an_rc_handing_back_an_rc_option_captured_by_a_thread_is_refused: a closure over an Rc whose code hands back a `?( Rc i )`, captured by a thread's closure that runs it
// Guard for agora #788's fix: the walk no longer reads a closure's signature, and the closure's captures refuse it.
// main ad17e78c: refused, by the closure's signature ("captures 'f' … reaches an 'Rc'").
// map: §6.5 | A3 | rejected | - | agora #788 guard: a closure over an Rc is refused by its captures, whatever its signature names
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

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r2 ) ) = j + j 1 }
        ^ @ ?( Rc i ) { T ( rc_clone [i] r2 ) }
    }
    ?? ( thread_spawn \ → v { ( run_n f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
