// returned_closure_over_a_struct_given_a_view_of_a_parameter_outlives_it_is_refused: the same with a captured P { s w String o } whose view field is filled from the parameter
// Closed: agora #467, a struct's view field is part of its own storage.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #467: a returned closure over a struct holding a view of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { s w String o }

@ mk String s → ( @ v ) {
    : P h @ P { ( string_data s ) ( string_from `owned` ) }
    ^ \ → v { ( nurl_println . h w ) }
}

@ main → i {
    : ~ ( @ v ) f \ → v {}
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = f ( mk s )
    }
    ( f )
    ^ 0
}
