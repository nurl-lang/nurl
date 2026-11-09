// generic_over_rows_hands_its_closure_a_row_of_its_parameter: agora #461 — a generic over `( Vec ( Vec T ) )` hands its closure `( @ v ( Vec T ) )` the parameter's element
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a generic over rows hands its closure a row of its parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ each0 [T] ( Vec ( Vec T ) ) vv ( @ v ( Vec T ) ) f → v {
    ( f ( vec_at [( Vec T )] vv 0 ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] w 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( each0 [String] w \ ( Vec String ) z → v { ( vec_clear [String] z ) } )
    ( nurl_println d )
    ^ 0
}
