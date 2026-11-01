// parameter_copied_into_a_returned_join_literal_keeps_the_callers_temporary: agora #288 — a handle parameter (not `sink`) copied into a result literal in an arm of a returned `??`, the function called with a temporary: the temporary was never dropped.
// main: accepted; LeakSanitizer reported a leak (one H, its Rc and its Vec, per call).
// map: §7.6 | A2 | runs-clean | - | agora #288: a handle parameter (not `sink`) copied into a result literal in an arm of a returned `??`, the function called with a temporary: the temporary was never dropped (leak)
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec u ) buf }
: H { ( Rc Impl ) ctl }

@ mk → H {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 1 )
    ^ @ H { ( rc_new [Impl] @ Impl { b } ) }
}

@ step H h → !i i { ^ @ !i i { T 0 } }

@ wrap H h → !H i {
    : !i i r ( step h )
    ^ ?? r {
        T _ → @ !H i { T h }
        F e → @ !H i { F e }
    }
}

@ main → i {
    : ~ i k 0
    ~ < k 10 {
        ?? ( wrap ( mk ) ) { T x → {} F _ → {} }
        = k + k 1
    }
    ^ 0
}
