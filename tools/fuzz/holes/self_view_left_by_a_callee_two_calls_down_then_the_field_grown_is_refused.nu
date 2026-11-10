// self_view_left_by_a_callee_two_calls_down_then_the_field_grown_is_refused: the self-view made two calls down (`h2` calls `h`), then the caller grows `. p s`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: the self-view made two calls down (`h2` calls `h`), then the caller grows `. p s`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ h2 inout P p → v { ( h p ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h2 p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
