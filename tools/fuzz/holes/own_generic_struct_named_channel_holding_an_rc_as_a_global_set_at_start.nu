// own_generic_struct_named_channel_holding_an_rc_as_a_global_set_at_start: as its `Arc` twin, with the name `Channel`: a program that imports no std/channel declares a generic struct of its own named `Channel`, holding an `Rc`, as a global set at start that two threads clone the `Rc` out of.
// main: accepted — the rule matched the spelling `( Channel … )` (ASan: double-free).
// map: §6.5 | A3 | rejected | - | a program's own generic struct named Channel holding an Rc as a global set at start: the rule asks for the library's type, not the name (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Channel [T] { ( Rc T ) r }

@ make → ( Channel i ) { ^ @ ( Channel i ) { ( rc_new [i] 5 ) } }

: ( Channel i ) g_one ( make )

@ churn i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] . g_one r ) ) = j + j 1 }
        = k + k 1
    }
    ^ ( rc_strong [i] . g_one r )
}

@ main → i {
    ?? ( thread_spawn \ → v { ( churn 20000 ) } ) {
        T t → { ( churn 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] . g_one r ) 1
}
