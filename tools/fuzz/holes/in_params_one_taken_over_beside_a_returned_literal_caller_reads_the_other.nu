// in_params_one_taken_over_beside_a_returned_literal_caller_reads_the_other: the caller of `f`, which takes both parameters of its returned `@ K2 { a b }` over, reads its second argument after the call
// Guard: the argument was moved into the call, as main says too.
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a literal's parameters all taken over: the caller's argument is moved
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ mk → String { ^ ( string_from `a fresh value long enough for the heap buffer` ) }

@ f String a String b i k → K2 {
    ? == k 1 { ^ @ K2 { a b } } {}
    ( string_free a )
    ^ @ K2 { ( mk ) ( mk ) }
}

@ main → i {
    : String y ( mk )
    : K2 r ( f ( mk ) y 1 )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data y ) )
    ^ 0
}
