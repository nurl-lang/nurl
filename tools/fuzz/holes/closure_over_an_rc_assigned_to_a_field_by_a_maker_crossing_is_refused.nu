// closure_over_an_rc_assigned_to_a_field_by_a_maker_crossing_is_refused: a maker assigning a closure over its Rc parameter to a field after building the struct, the struct then run on a thread
// Closed: agora #718, a field assignment adds the stored closure's captures to the binding.
// main 2faf34c2: accepted (ASan: attempting double-free).
// map: §6.5 | A3 | rejected | - | agora #718: a closure over an Rc assigned to a field after building is not Send where the struct crosses
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

@ build sink ( Rc i ) q → H {
    : ~ H h @ H { \ → i { ^ 1 } 1 }
    = . h f \ → i {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] q ) ) = j + j 1 }
        ^ 0
    }
    ^ h
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Rc i ) r2 ( rc_clone [i] r )
    : H h ( build r2 )
    ?? ( thread_spawn \ → v { ( run_n . h f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
