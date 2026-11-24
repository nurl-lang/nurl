// in_params_of_a_returned_literal_given_to_a_later_callee_that_only_reads_runs_clean: `^ @ K2 { a b }` of two `in` parameters, where the body hands `a` to a callee compiled after it that only reads it; the caller reads its argument after the call
// The parked implication is settled with the callee's verdict at module end: a callee that only reads takes nothing over, so the literal lends both (AGORA-995, review of github#2280). Before it the parameters were taken over at the function's end.
// main: rejected.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal's parameter handed to a later callee that only reads stays lent
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ( eat a )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ g i k → i {
    : String y ( mk )
    : K2 r ( f ( mk ) y k )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data y ) )
    ^ 0
}

@ eat String s → v { ( nurl_println ( string_data s ) ) }

@ main → i { ( g 1 ) ^ ( g 0 ) }
