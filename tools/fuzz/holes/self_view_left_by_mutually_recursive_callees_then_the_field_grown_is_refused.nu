// self_view_left_by_mutually_recursive_callees_then_the_field_grown_is_refused: two mutually recursive callees, one leaving the inout struct viewing its own field, then `. p s` grown
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: two mutually recursive callees, one leaving the inout struct viewing its own field, then `. p s` grown
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ ha inout P p i n → v {
    ? > n 0 { ( hb p - n 1 ) } { = . p w @ W { ( string_data . p s ) } }
}

@ hb inout P p i n → v { ( ha p n ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( hb p 3 )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
