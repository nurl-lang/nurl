// in_param_lent_or_fresh_in_a_returned_literal_bound_by_the_caller_runs_clean: `f` hands back `@ K1 { a 0 }` on one path and `@ K1 { ( mk ) 0 }` on another, and the caller binds the result
// The lending path answers per call, as `^ p` beside `^ ( mk )` does: taken for a lender throughout, the fresh result leaked (LSan; AGORA-995, review of github#2280).
// main: runs clean.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: a returned literal lending its parameter on one path and fresh on another answers per call
$ `stdlib/core/string.nu`

: K1 { String a i n }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a i k → K1 {
    ? == k 1 { ^ @ K1 { a 0 } } {}
    ^ @ K1 { ( mk ) 0 }
}

@ g i k → i {
    : String x ( mk )
    : K1 r ( f x k )
    ( nurl_println ( string_data . r a ) )
    ^ 0
}

@ main → i { ( g 1 ) ^ ( g 0 ) }
