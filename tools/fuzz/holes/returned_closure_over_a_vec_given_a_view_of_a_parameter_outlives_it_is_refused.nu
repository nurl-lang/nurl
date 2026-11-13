// returned_closure_over_a_vec_given_a_view_of_a_parameter_outlives_it_is_refused: a function hands back a closure over a local ( Vec s ) it pushed a view of its String parameter into; the caller frees the String and runs the closure
// Closed: agora #467, the returned closure holds a copy of the Vec, and the views it holds: the caller's binding depends on the argument.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #467: a returned closure over a Vec given a view of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk String s → ( @ v ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
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
