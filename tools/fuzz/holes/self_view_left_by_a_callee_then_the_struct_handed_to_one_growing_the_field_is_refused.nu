// self_view_left_by_a_callee_then_the_struct_handed_to_one_growing_the_field_is_refused: a callee leaves its inout struct viewing its own field, then the caller hands the struct to another callee that grows `. p s`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee leaves its inout struct viewing its own field, then the caller hands the struct to another callee that grows `. p s`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ grow inout P p → v { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( grow p )
    ( nurl_println . . p w v )
    ^ 0
}
