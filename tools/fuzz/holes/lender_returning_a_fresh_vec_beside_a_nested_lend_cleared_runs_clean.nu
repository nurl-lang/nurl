// lender_returning_a_fresh_vec_beside_a_nested_lend_cleared_runs_clean: agora #461 — `: r ( pick ( vec_at p 0 ) q k )`, `pick` returning a fresh Vec; `( clr r )` clears only that
// The shape the fix must keep: a value that may not lend makes no edge (agora #461).
// main cd8c0a6: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #461: a lender returning a fresh Vec beside a nested lend, cleared
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick ( Vec String ) a ( Vec String ) b i k → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ^ out
}

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec String ) ) p ( Vec String ) q i k → v {
    : ( Vec String ) r ( pick ( vec_at [( Vec String )] p 0 ) q k )
    ( clr r )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] w 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : ( Vec String ) q0 ( vec_new [String] )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] w 0 ) 0 ) )
    ( top w q0 1 )
    ( nurl_println d )
    ^ 0
}
