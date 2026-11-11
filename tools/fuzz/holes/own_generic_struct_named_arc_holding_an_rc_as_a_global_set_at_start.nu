// own_generic_struct_named_arc_holding_an_rc_as_a_global_set_at_start: a program that imports no std/arc declares a generic struct of its own named `Arc`, holding an `Rc`, and keeps one as a global set at start. Two threads clone the `Rc` out of it. What a global set at start may hold is the standard library's handles that synchronise themselves; the name alone promises nothing.
// main: accepted — the rule matched the spelling `( Arc … )`; two threads clone and drop one Rc, whose count is not atomic (ASan: double-free). The type is now asked for what it is: an instance of the library's generic struct of that name (`__ty_std_named`).
// map: §6.5 | A3 | rejected | - | a program's own generic struct named Arc holding an Rc as a global set at start: the rule asks for the library's type, not the name (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Arc [T] { ( Rc T ) r }

@ make → ( Arc i ) { ^ @ ( Arc i ) { ( rc_new [i] 5 ) } }

: ( Arc i ) g_one ( make )

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
