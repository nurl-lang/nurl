// function_hands_its_parameters_element_to_a_clearing_closure_parameter: the same through the function's closure parameter, given a clearing literal by its caller.
// Closed: as above, through the closure parameter's node (agora #443, #421).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #443: the same through the function's closure parameter, given a clearing literal by its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ my_each ( Vec ( Vec String ) ) vv ( @ v ( Vec String ) ) f → v { ( f ( vec_at [( Vec String )] vv 0 ) ) }

@ main → i {
    : ( Vec ( Vec String ) ) outer ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] outer ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] outer 0 ) ( string_from `another element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] outer 0 ) 0 )
    ( my_each outer \ ( Vec String ) x → v { ( vec_clear [String] x ) } )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
