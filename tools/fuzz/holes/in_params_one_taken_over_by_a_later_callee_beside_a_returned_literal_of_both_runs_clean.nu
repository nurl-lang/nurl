// in_params_one_taken_over_by_a_later_callee_beside_a_returned_literal_of_both_runs_clean: `^ @ K2 { a b }` of two `in` parameters, where the body hands `a` to a callee compiled after it that takes it over
// A parked implication (the callee is not compiled yet) is settled with the callee's verdict: each member of the literal is a `sink` if another is, and the module-end fixed point takes both over once `eat` takes `a` (AGORA-995, review of github#2280).
// main: runs clean.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal of parameters, one taken over by a later callee, takes them all over
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ( eat a )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ eat String s → v { ( string_free s ) }

@ main → i {
    : K2 r ( f ( mk ) ( mk ) 1 )
    ( nurl_println ( string_data . r a ) )
    ^ 0
}
