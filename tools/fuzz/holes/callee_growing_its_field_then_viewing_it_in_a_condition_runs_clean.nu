// callee_growing_its_field_then_viewing_it_in_a_condition_runs_clean: `? ( h p ) { read } { read }`, h growing `. p s` before pointing `. p w` at it (the call's own effects come before the view it leaves)
// Closed: the tie comes after the call's own effects, so a callee that grows the field and then views it leaves a good view (agora #584).
// main 4e090402: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: `? ( h p ) { read } { read }`, h growing `. p s` before pointing `. p w` at it (the call's own effects come before the view it leaves)
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → b { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) = . p w @ W { ( string_data . p s ) } ^ T }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ? ( h p ) { ( nurl_println . . p w v ) } { ( nurl_println . . p w v ) }
    ^ 0
}
