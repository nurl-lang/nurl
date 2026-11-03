// closure_binding_given_a_reader_through_an_inout_parameter_runs_clean: a callee gives the caller's closure binding a reading literal through an inout parameter, then the binding is called with a Vec whose element is still read.
// Must keep compiling and running clean beside agora #433's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #433: a callee gives the caller's closure binding a reading literal through an inout parameter, then the binding is called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ setf inout ( @ v ( Vec String ) ) f ( @ v ( Vec String ) ) src → v {
    = f src
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ~ ( @ v ( Vec String ) ) g \ ( Vec String ) y → v {}
    ( setf g \ ( Vec String ) z → v { ( nurl_println_int ( vec_len [String] z ) ) } )
    : String e ( vec_at [String] v 0 )
    ( g v )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
