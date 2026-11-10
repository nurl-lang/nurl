// call_pointing_a_field_at_another_structs_field_then_growing_its_own_runs_clean: `( f . p w . q s )`, then `. p s` grown and `. . p w v` read: w views q's field, not p's (the shape the fix must keep)
// Closed: only the field the callee was handed is a source (agora #571).
// main c948ff15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #571: `( f . p w . q s )`, then `. p s` grown and `. . p w v` read: w views q's field, not p's (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }

: P { W w String s }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : ~ P q @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( f . p w . q s )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really` )
    ( nurl_println . . p w v )
    ^ 0
}
