// closure_binding_given_a_clearing_closure_through_an_inout_parameter: a callee gives the caller's closure binding a clearing literal through an inout parameter, then the binding is called with a Vec whose element is still read.
// Closed: a closure binding handed to a function's inout closure parameter may come back as whatever the callee gives that parameter — its node gains the parameter's (agora #433).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #433: a callee gives the caller's closure binding a clearing literal through an inout parameter, then the binding is called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ setf inout ( @ v ( Vec String ) ) f ( @ v ( Vec String ) ) src → v {
    = f src
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ~ ( @ v ( Vec String ) ) g \ ( Vec String ) y → v {}
    ( setf g \ ( Vec String ) z → v { ( vec_clear [String] z ) } )
    : String e ( vec_at [String] v 0 )
    ( g v )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
