// callee_pointing_a_field_of_its_inout_struct_at_a_by_value_sibling_then_the_sibling_grown_is_refused: as the call form, the sibling field handed by value (`( g . p w . p s )` with `String s`), then `. p s` grown
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: as the call form, the sibling field handed by value (`( g . p w . p s )` with `String s`), then `. p s` grown
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { ( g . p w . p s ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
