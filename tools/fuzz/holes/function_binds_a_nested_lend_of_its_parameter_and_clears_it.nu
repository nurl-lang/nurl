// function_binds_a_nested_lend_of_its_parameter_and_clears_it: agora #461 — inside `top`, `: r ( vec_at ( vec_at vvv 0 ) 0 )`, then `( clr r )`
// Closed: a local bound to a lend no name carries is read out of what its source expression names, under that condition (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function binds a nested lend of its parameter and clears it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    : ( Vec String ) r ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] vvv 0 ) 0 )
    ( clr r )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    : ( Vec ( Vec String ) ) m ( vec_at [( Vec ( Vec String ) )] w 0 )
    ( vec_push [( Vec String )] m ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] m 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
