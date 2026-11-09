// callee_growing_its_inout_string_hands_back_a_holder_viewing_the_old_buffer: a callee views its inout String into an inout holder, then grows the String (string_push_str); the holder goes back viewing the moved-out buffer (PO h07).
// Closed: at a way out, an inout holder whose view a buffer move inside the function ended is refused, as one viewing a released local is (agora #390).
// main 2c20c888: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #390: a callee views its inout String into an inout holder, then grows the String (string_push_str); the holder goes back viewing the moved-out buffer (PO h07)
$ `stdlib/core/string.nu`

: W { s v }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
    ( string_push_str s `and a long tail that makes the buffer move to a new place in memory for sure` )
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    ( f w s )
    ( nurl_println . w v )
    ^ 0
}
