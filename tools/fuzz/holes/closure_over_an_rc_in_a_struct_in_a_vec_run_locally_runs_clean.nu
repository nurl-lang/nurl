// closure_over_an_rc_in_a_struct_in_a_vec_run_locally_runs_clean: a struct-held closure over an Rc in a Vec, run on the thread that built it
// Guard for agora #718's fix: no thread crossing, no Send question.
// main 2faf34c2: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #718 guard: a closure over an Rc in a Vec run where it was built stays accepted
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
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { \ → i { ^ ( rc_get [i] r ) } 1 } )
    ( run_n . ( vec_at [H] hs 0 ) f 3 )
    ^ 0
}
