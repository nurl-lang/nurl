// closure_binding_given_a_clearing_binding_by_a_callee_defined_below: a callee defined below the caller gives its closure binding a clearing closure binding through an inout parameter, then the binding is called with a Vec whose element is still read.
// Closed: a closure binding handed to a function's inout closure parameter may come back as whatever the callee gives that parameter — its node gains the parameter's (agora #433).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #433: a callee defined below the caller gives its closure binding a clearing closure binding through an inout parameter, then the binding is called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) clr \ ( Vec String ) z → v { ( vec_clear [String] z ) }
    : ~ ( @ v ( Vec String ) ) g \ ( Vec String ) y → v {}
    ( setf g clr )
    : String e ( vec_at [String] v 0 )
    ( g v )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}

@ setf inout ( @ v ( Vec String ) ) f ( @ v ( Vec String ) ) src → v {
    = f src
}
