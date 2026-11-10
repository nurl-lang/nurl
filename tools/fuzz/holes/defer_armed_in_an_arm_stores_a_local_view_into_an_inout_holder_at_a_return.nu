// defer_armed_in_an_arm_stores_a_local_view_into_an_inout_holder_at_a_return: the arm form at a `^` (PO b10c).
// Closed: as the loop form (agora #407).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #407: the arm form at a `^` (PO b10c)
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    ? > k 0 { ; { = w @ W { ( string_data b ) } } } {}
    ^ k
}

@ main → i {
    : ~ W w @ W { `start` }
    : i _r ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
