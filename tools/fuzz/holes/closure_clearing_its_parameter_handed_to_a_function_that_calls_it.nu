// closure_clearing_its_parameter_handed_to_a_function_that_calls_it: a clearing closure handed to a function that calls it on the caller's Vec.
// Closed: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #359: a clearing closure handed to a function that calls it on the caller's Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ apply ( Vec String ) v ( @ v ( Vec String ) ) f → v { ( f v ) }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] inner 0 )
    ( apply inner \ ( Vec String ) x → v { ( vec_clear [String] x ) } )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
