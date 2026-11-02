// closure_pushing_into_its_parameter_beside_an_element_borrow_runs_clean: a closure that only pushes into its Vec parameter drops no element.
// Must keep compiling and running clean: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled, ran clean.
// map: §2.5 | A2 | runs-clean | - | agora #359 guard: a closure that only pushes into its Vec parameter drops no element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) add \ ( Vec String ) x → v { ( vec_push [String] x ( string_from `more` ) ) }
    : String s0 ( vec_at [String] inner 0 )
    ( add inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
