// inout_parameter_selected_by_a_join_handed_to_a_sink: `( eat ? == c 1 p p )` and `( eat ? == c 1 p ( mkv 3 ) )` on the path that selects p, with p an `inout` parameter, called as `( f w 1 )`.
// Closed (agora #567): the join's sink-copy rule copied p for the callee while the function's summary still said it consumes p, so the caller dropped nothing and the original leaked. A join whose selectable bindings are all whole `inout` parameters hands them over as `( eat p )` does (arg_join_io), as #1679's rule does for a block's tail. (The path that selects the fresh value, `( g w 0 )`, is a separate open leak: agora #776.)
// main (before this PR): LeakSanitizer reported the caller's Vec and its String on each call.
// map: §7.6 | A2 | runs-clean | - | a join selecting an inout parameter for a sink copied it while the caller dropped nothing — leak
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } )
    ^ v
}

@ f inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 p p ) }

@ g inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 p ( mkv 3 ) ) }

@ main → i {
    : ~ ( Vec S ) w ( mkv 1 )
    : i x ( f w 1 )
    : ~ ( Vec S ) w2 ( mkv 1 )
    : i y ( g w2 1 )
    ? != + x y 2 { ^ 1 } {}
    ^ 0
}
