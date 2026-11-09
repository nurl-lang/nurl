// generic_hands_its_clearing_closure_parameter_its_parameters_element: agora #461 — `@ each0 [T] ( Vec T ) vv ( @ v T ) f → v { ( f ( vec_at [T] vv 0 ) ) }` given a clearing closure literal
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a generic hands its clearing closure parameter its parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ each0 [T] ( Vec T ) vv ( @ v T ) f → v {
    ( f ( vec_at [T] vv 0 ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] w 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( each0 [( Vec String )] w \ ( Vec String ) z → v { ( vec_clear [String] z ) } )
    ( nurl_println d )
    ^ 0
}
