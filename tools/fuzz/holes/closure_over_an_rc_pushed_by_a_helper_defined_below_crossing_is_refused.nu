// closure_over_an_rc_pushed_by_a_helper_defined_below_crossing_is_refused: the same with the helper declared after its caller
// Closed: agora #717, what a call stores into an argument (`storecs##F##K`) is held by the caller's binding of it.
// main 2faf34c2: accepted (ASan: heap-use-after-free).
// map: §6.5 | A3 | rejected | - | agora #717: a helper declared below its caller that stores a closure over an Rc into the caller's Vec
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

@ run_n ( @ i ) f i n → v { : ~ i k 0 ~ < k n { : i z ( f ) = k + k 1 } }

: H { ( @ i ) f i n }

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Vec ( @ i ) ) makers ( vec_new [( @ i )] )
    ( add makers ( rc_clone [i] r ) )
    ?? ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 20000 { : ( @ i ) mk ( vec_at [( @ i )] makers 0 ) : i z ( mk ) = k + k 1 }
    } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}

@ add ( Vec ( @ i ) ) makers ( Rc i ) theirs → v {
    ( vec_push [( @ i )] makers \ → i {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] theirs ) ) = j + j 1 }
        ^ 0
    } )
}
