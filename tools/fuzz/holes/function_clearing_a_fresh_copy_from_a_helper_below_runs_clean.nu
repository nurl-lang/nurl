// function_clearing_a_fresh_copy_from_a_helper_below_runs_clean: agora #461 — `top` hands `clr` a fresh Vec made from its parameter by `mkfresh`, defined below main
// The shape the fix must keep: a callee not compiled yet no longer stands for every argument (agora #461).
// main 21a0fb5: refused (a false positive).
// map: §2.10 | A2 | runs-clean | - | agora #461: a function clearing a fresh copy from a helper defined below
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec String ) ) vv → v {
    ( clr ( mkfresh vv ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] w 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}

@ mkfresh ( Vec ( Vec String ) ) vv → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `fresh` ) )
    ^ out
}
