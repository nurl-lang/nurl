// function_hands_its_parameters_element_to_a_clearing_callee: a function hands `( vec_at vv 0 )` of its parameter to a callee that clears it; its caller's borrow of that element's element is read afterwards.
// Closed: what a callee drops or changes of a value lent out of a parameter, the function does to that parameter: drop and mutation edges from the lend source (agora #443).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #443: a function hands `( vec_at vv 0 )` of its parameter to a callee that clears it; its caller's borrow of that element's element is read afterwards
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clr ( Vec String ) x → v { ( vec_clear [String] x ) }

@ my_each ( Vec ( Vec String ) ) vv → v { ( clr ( vec_at [( Vec String )] vv 0 ) ) }

@ main → i {
    : ( Vec ( Vec String ) ) outer ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] outer ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] outer 0 ) ( string_from `another element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] outer 0 ) 0 )
    ( my_each outer )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
