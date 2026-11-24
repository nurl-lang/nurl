// in_params_of_overlapping_returned_literals_taken_over_through_a_later_callee_caller_reads_the_first: `@ K2 { a b }` and `@ K2 { b c }` returned on two paths, `c` handed to a callee compiled later that takes it over; the caller reads its first argument after the call
// Guard: each member of a literal is a `sink` if another is, parked behind the callee's verdict; the module-end fixed point takes `c`, `b` and then `a` over (AGORA-995, review of github#2280).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: overlapping returned literals taken over through a later callee: the caller's first argument is moved
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b String c i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ? == k 2 { ^ @ K2 { b c } } {}
    ( eat c )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ g i k → i {
    : String x ( mk )
    : K2 r ( f x ( mk ) ( mk ) k )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}

@ eat String s → v { ( string_free s ) }

@ main → i { ( g 1 ) ( g 2 ) ^ ( g 0 ) }
