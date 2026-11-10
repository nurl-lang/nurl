// callee_pointing_a_field_of_its_inout_struct_at_a_sibling_through_a_call_then_the_sibling_grown_is_refused: a callee hands two fields of its inout struct to a callee that points the first at the second (`( f . p w . p s )`), then the caller grows `. p s` and reads `. . p w v`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee hands two fields of its inout struct to a callee that points the first at the second (`( f . p w . p s )`), then the caller grows `. p s` and reads `. . p w v`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: V { s v i n }
: Q { V vv s x ( Vec s ) vs W w }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { ( f . p w . p s ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
