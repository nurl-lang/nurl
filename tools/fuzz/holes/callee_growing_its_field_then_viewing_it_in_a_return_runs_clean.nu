// callee_growing_its_field_then_viewing_it_in_a_return_runs_clean: `^ ( h p )` in a wrapper, h growing `. p s` before pointing `. p w` at it, the view read by the wrapper's caller
// Closed: the tie comes after the call's own effects, so a callee that grows the field and then views it leaves a good view (agora #584).
// main 4e090402: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: `^ ( h p )` in a wrapper, h growing `. p s` before pointing `. p w` at it, the view read by the wrapper's caller
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → i { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) = . p w @ W { ( string_data . p s ) } ^ 1 }

@ k inout P p → i { ^ ( h p ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : i z ( k p )
    ( nurl_println . . p w v )
    ^ z
}
