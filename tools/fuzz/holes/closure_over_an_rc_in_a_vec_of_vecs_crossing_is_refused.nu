// closure_over_an_rc_in_a_vec_of_vecs_crossing_is_refused: the struct-held closure Vec pushed into a Vec of Vecs a thread runs from
// Closed: agora #718, a closure-holding argument passes its captures to the binding it is stored into.
// main 2faf34c2: accepted.
// map: §6.5 | A3 | rejected | - | agora #718: a closure over an Rc two containers deep is not Send where the outer Vec crosses
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
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { \ → i {
            : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
            : ~ i j 0
            ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r2 ) ) = j + j 1 }
            ^ 0
        } 1 } )
    : ( Vec ( Vec H ) ) vv ( vec_new [( Vec H )] )
    ( vec_push [( Vec H )] vv hs )
    ?? ( thread_spawn \ → v { ( run_n . ( vec_at [H] ( vec_at [( Vec H )] vv 0 ) 0 ) f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
