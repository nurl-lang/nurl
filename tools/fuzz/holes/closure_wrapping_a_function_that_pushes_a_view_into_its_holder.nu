// closure_wrapping_a_function_that_pushes_a_view_into_its_holder: a closure wrapping a named function that pushes the view, handed to a function that calls it.
// Closed: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #403: a closure wrapping a named function that pushes the view, handed to a function that calls it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ st ( Vec s ) h String s → v { ( vec_push [s] h ( string_data s ) ) }

@ hof ( @ v ( Vec s ) String ) f ( Vec s ) h String s → v { ( f h s ) }

@ main → i {
    : ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( hof \ ( Vec s ) h String s → v { ( st h s ) } hold s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
