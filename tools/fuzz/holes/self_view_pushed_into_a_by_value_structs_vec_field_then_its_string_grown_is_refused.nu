// self_view_pushed_into_a_by_value_structs_vec_field_then_its_string_grown_is_refused: a callee pushes into the Vec field of its by-value struct a view of the struct's String field (the Vec is the caller's), then the caller grows the String
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee pushes into the Vec field of its by-value struct a view of the struct's String field (the Vec is the caller's), then the caller grows the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { W w String s String t }
: Q { ( Vec W ) ws String s }

@ h Q q → v { ( vec_push [W] . q ws @ W { ( string_data . q s ) } ) }

@ main → i {
    : ~ Q q @ Q { ( vec_new [W] ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h q )
    ( string_push_str . q s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . ( vec_at [W] . q ws 0 ) v )
    ^ 0
}
