// in_params_one_taken_over_before_a_returned_literal_of_both_runs_clean: `^ @ K2 { a b }` of two `in` parameters, where the body has taken `a` over on a path before the literal (`( string_free a )`)
// `a`, an inferred `sink`, is the function's own on every path: it moves into the literal as a declared `sink` does, and beside it the literal takes `b` over too (AGORA-995, review of github#2280). Lent, the result owned the one and borrowed the other, and `a` leaked (LeakSanitizer).
// main: runs clean.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal of parameters, some taken over, takes them all over
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 0 { ( string_free a ) ^ @ K2 { ( mk ) ( mk ) } } {}
    ^ @ K2 { a b }
}

@ main → i {
    : String x ( mk )
    : String y ( mk )
    : K2 r ( f x y 1 )
    ( nurl_println ( string_data . r a ) )
    : K2 s ( f ( mk ) ( mk ) 0 )
    ( nurl_println ( string_data . s a ) )
    ^ 0
}
