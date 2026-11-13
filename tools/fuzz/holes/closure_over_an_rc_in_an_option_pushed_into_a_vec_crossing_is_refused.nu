// closure_over_an_rc_in_an_option_pushed_into_a_vec_crossing_is_refused: an optional closure over an Rc pushed into a Vec a thread runs it from
// Closed: agora #718, a closure-holding argument passes its captures to the binding it is stored into.
// main 2faf34c2: accepted.
// map: §6.5 | A3 | rejected | - | agora #718: a closure over an Rc in an option in a Vec is not Send where the Vec crosses
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
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( Vec ? ( @ i ) ) fs ( vec_new [? ( @ i )] )
    ( vec_push [? ( @ i )] fs @ ?( @ i ) { T \ → i {
            : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
            : ~ i j 0
            ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r2 ) ) = j + j 1 }
            ^ 0
        } } )
    ?? ( thread_spawn \ → v { ?? ( vec_at [? ( @ i )] fs 0 ) { T g → { ( run_n g 20000 ) } F → {} } } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
