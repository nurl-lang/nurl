// in_params_one_taken_over_after_a_returned_literal_of_both_runs_clean: `^ @ K2 { a b }` of two `in` parameters, where the body takes `a` over on a path after the literal
// At the function's end every parameter of such a literal is taken over (an inferred `sink`, kept) once one of them is: the result owns them all, as the module-end sink constants then say (AGORA-995, review of github#2280).
// main: runs clean.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal of parameters, one taken over after it, takes them all over
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ( string_free a )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ main → i {
    : K2 r ( f ( mk ) ( mk ) 1 )
    ( nurl_println ( string_data . r a ) )
    : K2 s ( f ( mk ) ( mk ) 0 )
    ( nurl_println ( string_data . s a ) )
    ^ 0
}
