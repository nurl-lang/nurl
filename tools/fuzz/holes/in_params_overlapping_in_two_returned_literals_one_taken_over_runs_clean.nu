// in_params_overlapping_in_two_returned_literals_one_taken_over_runs_clean: `@ K2 { a b }` and `@ K2 { b c }` returned on two paths, with `c` released on a third
// Taking `c` over makes `b` a sink through the second literal, and so `a` through the first: the take-all runs to a fixpoint (AGORA-995, review of github#2280).
// main: runs clean.
// map: CallT.sink | A1 | runs-clean | - | AGORA-995: overlapping returned literals of parameters all taken over
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b String c i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ? == k 2 { ^ @ K2 { b c } } {}
    ( string_free c )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ main → i {
    : K2 r ( f ( mk ) ( mk ) ( mk ) 1 )
    : K2 s ( f ( mk ) ( mk ) ( mk ) 2 )
    : K2 t ( f ( mk ) ( mk ) ( mk ) 0 )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data . s a ) )
    ( nurl_println ( string_data . t a ) )
    ^ 0
}
