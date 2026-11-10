// self_view_left_by_a_callee_read_after_another_field_grown_runs_clean: a callee leaves its inout struct viewing `. p s`, the caller grows `. p t` and reads the view
// Closed: the argument is tied to the fields of itself the callee's answer names, after the call's own effects, and nothing else (agora #584).
// main a346fcba: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: a callee leaves its inout struct viewing `. p s`, the caller grows `. p t` and reads the view
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p t `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
