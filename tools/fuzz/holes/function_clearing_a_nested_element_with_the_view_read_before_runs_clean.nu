// function_clearing_a_nested_element_with_the_view_read_before_runs_clean: agora #461 — `a_g19_task`'s `top`, the view read only before `( top w )`
// The shape the fix must keep: a view read before the call (agora #461).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #461: a function clearing a nested element, the view read before
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    ( clr ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] vvv 0 ) 0 ) )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    : ( Vec ( Vec String ) ) m ( vec_at [( Vec ( Vec String ) )] w 0 )
    ( vec_push [( Vec String )] m ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] m 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( nurl_println d )
    ( top w )
    ( nurl_println_int # i ( vec_len [( Vec ( Vec String ) )] w ) )
    ^ 0
}
