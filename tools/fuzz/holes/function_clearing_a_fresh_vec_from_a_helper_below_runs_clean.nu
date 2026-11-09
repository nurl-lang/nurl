// function_clearing_a_fresh_vec_from_a_helper_below_runs_clean: agora #461 — `top` clears `( first_of vv )`, `first_of` defined below main returning a fresh Vec
// The shape the fix must keep: a callee not compiled yet no longer stands for every argument (agora #461).
// main cd8c0a6: refused (a false positive).
// map: §2.10 | A2 | runs-clean | - | agora #461: a function clearing a fresh Vec from a helper defined below
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec String ) ) vv → v {
    ( clr ( fresh_of vv ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] w 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] w 0 ) 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}

@ fresh_of ( Vec ( Vec String ) ) vv → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `x` ) )
    ^ out
}
