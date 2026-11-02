// closure_handed_to_a_function_pushes_a_view_of_a_live_string_runs_clean: the view-pushing closure handed on while the String outlives the holder's reads.
// Must keep compiling and running clean: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled, ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #403 guard: the view-pushing closure handed on while the String outlives the holder's reads
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ hof ( @ v ( Vec s ) String ) f ( Vec s ) h String s → v { ( f h s ) }

@ main → i {
    : ( Vec s ) hold ( vec_new [s] )
    : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    ( hof \ ( Vec s ) h String s → v { ( vec_push [s] h ( string_data s ) ) } hold s )
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
