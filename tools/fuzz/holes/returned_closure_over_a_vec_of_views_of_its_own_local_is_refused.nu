// returned_closure_over_a_vec_of_views_of_its_own_local_is_refused: a function hands back a closure over a ( Vec s ) holding a view of its own local String, released on the way out
// Closed: agora #467, the closure's copy of the Vec holds a view of the local: the return check refuses it.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #467: a returned closure over a Vec of views of a local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk2 → ( @ v ) {
    : String loc ( string_from `a heap string long enough to be on the heap for sure` )
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data loc ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
}

@ main → i {
    : ( @ v ) f ( mk2 )
    ( f )
    ^ 0
}
