// closure_over_an_rc_in_a_vec_handed_back_by_a_maker_crossing_is_refused: a maker filling a Vec with a struct-held closure over its Rc parameter and handing it back, the Vec crossing
// Closed: agora #718, a closure-holding argument passes its captures to the binding it is stored into.
// main 2faf34c2: accepted.
// map: §6.5 | A3 | rejected | - | agora #718: a closure over an Rc in a Vec a maker hands back is not Send where the Vec crosses
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

@ mkv ( Rc i ) q → ( Vec H ) {
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { \ → i {
            : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
            : ~ i j 0
            ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] q ) ) = j + j 1 }
            ^ 0
        } 1 } )
    ^ hs
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Vec H ) hs ( mkv ( rc_clone [i] r ) )
    ?? ( thread_spawn \ → v { ( run_n . ( vec_at [H] hs 0 ) f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
