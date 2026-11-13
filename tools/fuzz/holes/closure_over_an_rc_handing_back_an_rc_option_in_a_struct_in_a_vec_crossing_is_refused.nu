// closure_over_an_rc_handing_back_an_rc_option_in_a_struct_in_a_vec_crossing_is_refused: a struct literal holding a closure over an Rc whose code hands back a `?( Rc i )`, pushed into a Vec a thread runs it from
// Guard for agora #788's fix: the walk no longer reads a closure's signature, and the captures the Vec carries refuse it.
// main ad17e78c: refused, by the closure's signature ("captures 'hs' … reaches an 'Rc'").
// map: §6.5 | A3 | rejected | - | agora #788 guard: a closure over an Rc in a struct in a Vec is refused by its captures, whatever its signature names
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

: H { ( @ ?( Rc i ) i ) f i n }

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { \ i k → ?( Rc i ) {
            : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
            : ~ i j 0
            ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r2 ) ) = j + j 1 }
            ^ @ ?( Rc i ) { T ( rc_clone [i] r2 ) }
        } 1 } )
    ?? ( thread_spawn \ → v { ( run_n . ( vec_at [H] hs 0 ) f 20000 ) } ) {
        T t → { ( churn_local r 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
