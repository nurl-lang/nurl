// call_pointing_a_holder_at_a_field_repointed_before_the_field_grows_runs_clean: `( f w . p s )`, w read, then w given a literal before `. p s` grows (the shape the fix must keep)
// Closed: the holder's dependency on `. p s` ends when w is given a new value (agora #571).
// main c948ff15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #571: `( f w . p s )`, w read, then w given a literal before `. p s` grows (the shape the fix must keep)
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
    ( nurl_println . w v )
    = w @ W { `y` }
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really` )
    ( nurl_println . w v )
    ^ 0
}
