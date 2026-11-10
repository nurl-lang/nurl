// self_view_left_by_a_callee_read_while_the_field_lives_runs_clean: a callee leaves its inout struct viewing its own field, read before anything grows it (the shape the fix must keep)
// Closed: the argument is tied to the fields of itself the callee's answer names, after the call's own effects, and nothing else (agora #584).
// main a346fcba: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: a callee leaves its inout struct viewing its own field, read before anything grows it (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { ( f . p w . p s ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( nurl_println . . p w v )
    ^ 0
}
