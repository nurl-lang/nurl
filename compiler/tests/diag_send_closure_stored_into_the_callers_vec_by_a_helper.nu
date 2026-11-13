// diag_send_closure_stored_into_the_callers_vec_by_a_helper.nu — a helper
// pushes a closure over its Rc parameter into the caller's Vec, which a
// thread then runs: what a call stores into an argument (`storecs##F##K`)
// is held by the caller's binding of it, so the capture is asked for Send
// where the Vec crosses (Agora #717).
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

@ add ( Vec ( @ i ) ) makers ( Rc i ) theirs → v {
    ( vec_push [( @ i )] makers \ → i {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] theirs ) ) = j + j 1 }
        ^ 0
    } )
}

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
