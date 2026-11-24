// in_params_lent_or_fresh_in_a_returned_literal_bound_by_the_caller_runs_clean: `f` hands back `@ K2 { a b }` on one path and `@ K2 { ( mk ) ( mk ) }` on another; the caller binds the result and reads its own arguments
// The lending path answers per call: taken for a lender throughout, the fresh result leaked (LSan; AGORA-995, review of github#2280).
// main: rejected.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal lending two parameters on one path and fresh on another answers per call
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ eat String s → v { ( nurl_println ( string_data s ) ) }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ^ @ K2 { ( mk ) ( mk ) }
}

@ g i k → i {
    : String y ( mk )
    : String x ( mk )
    : K2 r ( f x y k )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data y ) )
    ^ 0
}

@ main → i { ( g 1 ) ^ ( g 0 ) }
