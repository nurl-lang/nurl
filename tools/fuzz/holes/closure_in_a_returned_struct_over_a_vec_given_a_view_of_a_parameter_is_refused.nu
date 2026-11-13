// closure_in_a_returned_struct_over_a_vec_given_a_view_of_a_parameter_is_refused: a function hands back a struct holding a closure over a ( Vec s ) given a view of its parameter; the caller frees the String and runs the closure
// Closed: agora #467, an owner the closure is stored into adopts the copy of the Vec, and the views it holds.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #467: a closure in a returned struct over a Vec of views of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( @ v ) f i n }

@ mk String s → H {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ @ H { \ → v { ( nurl_println ( vec_at [s] h 0 ) ) } 1 }
}

@ main → i {
    : ~ H k @ H { \ → v {} 0 }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = k ( mk s )
    }
    : ( @ v ) g . k f
    ( g )
    ^ 0
}
