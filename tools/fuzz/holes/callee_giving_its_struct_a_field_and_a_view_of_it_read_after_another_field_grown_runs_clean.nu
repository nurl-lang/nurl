// callee_giving_its_struct_a_field_and_a_view_of_it_read_after_another_field_grown_runs_clean: an init-style callee gives the struct a String field and a view of it, the caller reads it, grows another field and reads it again
// Closed: the argument is tied to the fields of itself the callee's answer names, after the call's own effects, and nothing else (agora #584).
// main a346fcba: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: an init-style callee gives the struct a String field and a view of it, the caller reads it, grows another field and reads it again
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { W w String s String t }

@ init inout P p String text → v {
    = . p s text
    = . p w @ W { ( string_data . p s ) }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( init p ( string_from `the first heap string, long enough to be on the heap for sure` ) )
    ( nurl_println . . p w v )
    ( nurl_println ( string_data . p t ) )
    ( string_push_str . p t `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
