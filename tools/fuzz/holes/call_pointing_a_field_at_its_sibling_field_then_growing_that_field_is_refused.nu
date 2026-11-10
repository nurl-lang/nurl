// call_pointing_a_field_at_its_sibling_field_then_growing_that_field_is_refused: `( f . p w . p s )`, an inout callee pointing field w at sibling field s, then `. p s` grown and `. . p w v` read
// Closed: a field argument is the source of a callee's exit pair (`bK.H`) by the path it read, so the holder depends on `. p s` (agora #571).
// main c948ff15: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #571: `( f . p w . p s )`, an inout callee pointing field w at sibling field s, then `. p s` grown and `. . p w v` read
$ `stdlib/core/string.nu`

: W { s v }

: P { W w String s }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( f . p w . p s )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
