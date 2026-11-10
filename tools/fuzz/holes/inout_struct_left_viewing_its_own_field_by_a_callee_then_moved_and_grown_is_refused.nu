// inout_struct_left_viewing_its_own_field_by_a_callee_then_moved_and_grown_is_refused: a callee leaves its inout struct viewing its own field, the caller moves the struct to another binding, grows that one's field and reads its view
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee leaves its inout struct viewing its own field, the caller moves the struct to another binding, grows that one's field and reads its view
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { ( f . p w . p s ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    {
        : P p2 p
        ( string_push_str . p2 s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
        ( nurl_println . . p2 w v )
    }
    ^ 0
}
