// rc_twelve_structs_down_captured_by_a_thread: `: L1 { ( Rc i ) r }`, `: L2 { L1 a }` … `: L12 { L11 a }` — a value holding a share of an `Rc` twelve structs down is captured by a `thread_spawn` closure while the spawner keeps another, and both threads clone and drop shares of the one unsynchronised count.
// main: accepted — the Send/Sync walk followed a type ten levels down and answered "nothing found" below that; the same program three levels deep was refused (ASan: double-free).
// map: §6.5 | A3 | rejected | - | an `Rc` twelve struct fields down captured by a spawned closure: the derivation reads a type whole, with the set of types it has asked in place of a depth budget (agora #711)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: L1 { ( Rc i ) r }
: L2 { L1 a }
: L3 { L2 a }
: L4 { L3 a }
: L5 { L4 a }
: L6 { L5 a }
: L7 { L6 a }
: L8 { L7 a }
: L9 { L8 a }
: L10 { L9 a }
: L11 { L10 a }
: L12 { L11 a }

@ churn L12 h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] . . . . . . . . . . . . h a a a a a a a a a a a r ) ) = j + j 1 }
        = k + k 1
    }
    ^ 0
}

@ mk ( Rc i ) r → L12 {
    ^ @ L12 { @ L11 { @ L10 { @ L9 { @ L8 { @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { ( rc_clone [i] r ) } } } } } } } } } } } }
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : L12 h2 ( mk r )
    : L12 h3 ( mk r )
    ?? ( thread_spawn \ → v { : i z ( churn h3 20000 ) } ) {
        T t → { : i z ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 3
}
