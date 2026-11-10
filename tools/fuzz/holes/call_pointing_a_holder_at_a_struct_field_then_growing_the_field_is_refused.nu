// call_pointing_a_holder_at_a_struct_field_then_growing_the_field_is_refused: `( f w . p s )`, an inout callee pointing holder w at field s of p, then `. p s` grown and `. w v` read
// Closed: the field source names its path, not a stale g_member_path (agora #571).
// main c948ff15: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #571: `( f w . p s )`, an inout callee pointing holder w at field s of p, then `. p s` grown and `. w v` read
$ `stdlib/core/string.nu`

: W { s v }

: P { W w String s }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : ~ W w @ W { `x` }
    ( f w . p s )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . w v )
    ^ 0
}
