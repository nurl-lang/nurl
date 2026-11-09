// closure_local_of_a_mixed_lender_cleared_beside_an_argument_it_only_reads_runs_clean: agora #461 — in a closure, `: r ( either3 ( vec_at w 0 ) q z )`, `either3` handing back `a` or `b` and only reading `c`, then `( vec_clear r )`; a view inside `z` kept
// The shape the fix must keep: the closure local is read out of the arguments that lend, not one the lender only reads (agora #461).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #461: a closure local of a mixed lender cleared beside an argument it only reads
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ either3 ( Vec String ) a ( Vec String ) b ( Vec String ) c → ( Vec String ) {
    ^ ? > # i ( vec_len [String] c ) 5 a b
}

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) q ( vec_new [String] )
    : ( Vec String ) z ( vec_new [String] )
    ( vec_push [String] z ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] z 0 ) )
    ( run \ → v { : ( Vec String ) r ( either3 ( vec_at [( Vec String )] w 0 ) q z ) ( vec_clear [String] r ) } )
    ( nurl_println d )
    ^ 0
}
