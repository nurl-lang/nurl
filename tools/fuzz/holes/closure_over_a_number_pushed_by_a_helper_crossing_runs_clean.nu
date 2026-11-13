// closure_over_a_number_pushed_by_a_helper_crossing_runs_clean: a helper pushing a closure over a number into the caller's Vec, which a thread runs from
// Guard for agora #717's fix: a closure whose captures are Send crosses inside the Vec.
// main 2faf34c2: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #717 guard: a Send closure a helper stores into the caller's Vec crosses
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

@ add ( Vec ( @ i ) ) makers i theirs → v {
    ( vec_push [( @ i )] makers \ → i {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_new [i] theirs ) ) = j + j 1 }
        ^ 0
    } )
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Vec ( @ i ) ) makers ( vec_new [( @ i )] )
    ( add makers 5 )
    ?? ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 20000 { : ( @ i ) mk ( vec_at [( @ i )] makers 0 ) : i z ( mk ) = k + k 1 }
    } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
