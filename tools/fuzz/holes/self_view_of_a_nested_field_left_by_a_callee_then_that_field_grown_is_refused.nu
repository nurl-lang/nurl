// self_view_of_a_nested_field_left_by_a_callee_then_that_field_grown_is_refused: a callee points its inout struct's view at a field of a field (`. . p q s`), then the caller grows `. . p q s`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee points its inout struct's view at a field of a field (`. . p q s`), then the caller grows `. . p q s`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }
: Q { String s }
: P2 { Q q W w }

@ h inout P2 p → v { = . p w @ W { ( string_data . . p q s ) } }

@ main → i {
    : ~ P2 p @ P2 { @ Q { ( string_from `the first heap string, long enough to be on the heap for sure` ) } @ W { `x` } }
    ( h p )
    ( string_push_str . . p q s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
