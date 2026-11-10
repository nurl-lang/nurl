// callee_growing_its_inout_vec_hands_back_a_holder_viewing_an_element: a callee views an element of its inout Vec into an inout holder, then pushes into the Vec until its buffer moves.
// Safe: the holder views the element String's own buffer, and growing the Vec moves its slots, not what each String holds. Refused at the caller on main 2c20c888 by the exclusive-call check, which read the callee's exit pair as an alias going in (agora #558); accepted since, and runs clean.
// Twin of the String form (agora #390), which stays refused: there the growth moves the very buffer the holder views.
// map: §2.10 | A2 | runs-clean | - | agora #558: a callee views an element of its inout Vec into an inout holder, then pushes into the Vec until its buffer moves (the element's own buffer stays)
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
