// diag_send_closure_in_a_struct_pushed_into_a_vec.nu — a struct literal
// holding a closure over an Rc, pushed into a Vec the thread reads: the
// Vec now holds the closure, so its captures are asked for Send where the
// Vec crosses, as for the closure pushed bare (Agora #718). The capture set
// followed only an argument whose type is a closure.
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
    ?? ( thread_spawn \ → v { ( run_n . ( vec_at [H] hs 0 ) f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
