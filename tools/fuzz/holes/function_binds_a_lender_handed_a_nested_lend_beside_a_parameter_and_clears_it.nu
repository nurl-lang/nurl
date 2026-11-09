// function_binds_a_lender_handed_a_nested_lend_beside_a_parameter_and_clears_it: agora #461 — in `top`, `: r ( either ( vec_at p 0 ) q k )`, then `( clr r )`
// Closed: a local bound to a lender handed a nested lend beside a named one is read out of both (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function binds a lender handed a nested lend beside a parameter and clears it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ either ( Vec String ) a ( Vec String ) b i k → ( Vec String ) {
    ^ ? > k 0 a b
}

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec String ) ) p ( Vec String ) q i k → v {
    : ( Vec String ) r ( either ( vec_at [( Vec String )] p 0 ) q k )
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
