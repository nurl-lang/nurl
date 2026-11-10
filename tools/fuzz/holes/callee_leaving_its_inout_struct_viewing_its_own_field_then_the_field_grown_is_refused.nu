// callee_leaving_its_inout_struct_viewing_its_own_field_then_the_field_grown_is_refused: a callee stores into its inout struct's view field a view of the struct's own String field (`= . p w @ W { ( string_data . p s ) }`), then the caller grows `. p s` and reads `. . p w v`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee stores into its inout struct's view field a view of the struct's own String field (`= . p w @ W { ( string_data . p s ) }`), then the caller grows `. p s` and reads `. . p w v`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
