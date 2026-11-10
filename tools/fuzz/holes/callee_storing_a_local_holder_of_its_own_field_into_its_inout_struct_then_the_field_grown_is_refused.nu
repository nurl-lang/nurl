// callee_storing_a_local_holder_of_its_own_field_into_its_inout_struct_then_the_field_grown_is_refused: a callee points a local holder at its inout struct's field (`( f w . p s )`) and stores the holder into the struct (`= . p w w`), then the caller grows `. p s`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee points a local holder at its inout struct's field (`( f w . p s )`) and stores the holder into the struct (`= . p w w`), then the caller grows `. p s`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ f inout W w inout String s → v { = w @ W { ( string_data s ) } }

@ g inout W w String s → v { = w @ W { ( string_data s ) } }

@ h inout P p → v { : ~ W w @ W { `x` } ( f w . p s ) = . p w w }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
