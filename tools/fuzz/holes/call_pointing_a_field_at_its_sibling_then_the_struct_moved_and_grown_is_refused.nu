// call_pointing_a_field_at_its_sibling_then_the_struct_moved_and_grown_is_refused: `( f . p w . p s )`, then `: P p2 p`, `. p2 s` grown and `. . p2 w v` read
// Closed: the self-view the call made moves with the struct, as a direct store's does (agora #571).
// main c948ff15: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #571: `( f . p w . p s )`, then `: P p2 p`, `. p2 s` grown and `. . p2 w v` read
$ `stdlib/core/string.nu`

: W { s v }

: P { W w String s }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( f . p w . p s )
    : P p2 p
    ( string_push_str . p2 s `and a long tail that makes the buffer move to a new place in memory for sure, really` )
    ( nurl_println . . p2 w v )
    ^ 0
}
