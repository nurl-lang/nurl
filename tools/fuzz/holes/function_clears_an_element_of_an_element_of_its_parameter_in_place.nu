// function_clears_an_element_of_an_element_of_its_parameter_in_place: agora #461 — `top` writes `( vec_clear ( vec_at ( vec_at vvv 0 ) 0 ) )` itself
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function clears an element of an element of its parameter in place
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    ( vec_clear [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] vvv 0 ) 0 ) )
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
