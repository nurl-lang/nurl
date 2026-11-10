// callee_growing_its_field_then_viewing_it_read_by_the_caller_runs_clean: a callee grows `. p s` and then points `. p w` at it, the caller reads the view (the call's own growth comes before the view it leaves)
// Closed: the argument is tied to the fields of itself the callee's answer names, after the call's own effects, and nothing else (agora #584).
// main a346fcba: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: a callee grows `. p s` and then points `. p w` at it, the caller reads the view (the call's own growth comes before the view it leaves)
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v {
    ( string_push_str . p s `grow first, then view` )
    = . p w @ W { ( string_data . p s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( nurl_println . . p w v )
    ^ 0
}
