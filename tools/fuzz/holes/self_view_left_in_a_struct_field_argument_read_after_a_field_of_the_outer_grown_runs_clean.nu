// self_view_left_in_a_struct_field_argument_read_after_a_field_of_the_outer_grown_runs_clean: `( h . o p )`, then a field of `o` beside `p` grown and the view read
// Closed: the argument is tied to the fields of itself the callee's answer names, after the call's own effects, and nothing else (agora #584).
// main a346fcba: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: `( h . o p )`, then a field of `o` beside `p` grown and the view read
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }
: O { String u P p }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ main → i {
    : ~ O o @ O { ( string_from `the first heap string, long enough to be on the heap for sure` ) @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) } }
    ( h . o p )
    ( string_push_str . o u `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . . o p w v )
    ^ 0
}
