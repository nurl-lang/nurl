// callee_growing_its_inout_vec_hands_back_a_holder_viewing_an_element: a callee views an element of its inout Vec into an inout holder, then pushes into the Vec until its buffer moves.
// Twin of the String form (agora #390); the caller's call is refused too (an argument the callee may move, beside one that will view it).
// main 2c20c888: rejected at the caller.
// map: §2.10 | A2 | rejected | - | agora #390: a callee views an element of its inout Vec into an inout holder, then pushes into the Vec until its buffer moves
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w inout ( Vec String ) vs → v {
    = w @ W { ( string_data ( vec_at [String] vs 0 ) ) }
    : ~ i k 0
    ~ < k 64 { ( vec_push [String] vs ( string_from `another element to make the vec buffer move, long enough` ) ) = k + k 1 }
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the first element, a heap string long enough for the heap` ) )
    ( f w vs )
    ( nurl_println . w v )
    ^ 0
}
