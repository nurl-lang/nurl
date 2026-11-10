// self_view_left_in_a_struct_field_argument_then_its_field_grown_is_refused: the self-viewing callee is handed a field of an outer struct (`( h . o p )`), then `. . o p s` grown and `. . . o p w v` read
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: the self-viewing callee is handed a field of an outer struct (`( h . o p )`), then `. . o p s` grown and `. . . o p w v` read
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }
: O { i n P p }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ main → i {
    : ~ O o @ O { 1 @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) } }
    ( h . o p )
    ( string_push_str . . o p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . . o p w v )
    ^ 0
}
