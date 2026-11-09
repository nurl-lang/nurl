// closure_in_a_function_clearing_a_fresh_locals_nested_element_runs_clean: agora #461 — inside `top`, a closure clears a nested lend of a fresh local, not of the parameter
// The shape the fix must keep: only the parameters the expression is rooted at get an edge (agora #461).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #461: a closure in a function clearing a fresh local's nested element
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    : ( Vec ( Vec ( Vec String ) ) ) loc ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] loc ( vec_new [( Vec String )] ) )
    ( vec_push [( Vec String )] ( vec_at [( Vec ( Vec String ) )] loc 0 ) ( vec_new [String] ) )
    : ( @ v ) g \ → v { ( clr ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] loc 0 ) 0 ) ) }
    ( g )
    ( nurl_println_int # i ( vec_len [( Vec ( Vec String ) )] vvv ) )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    ( vec_push [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
