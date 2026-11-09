// string_element_grown_through_an_accessor_of_your_own_past_a_view_of_it: agora #349 — `( string_push_str ( first_str vs ) … )`, `first_str` handing back `( vec_at vs 0 )`, with a view of that String kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a String element grown through an accessor of your own past a view of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ first_str ( Vec String ) vs → String {
    ^ ( vec_at [String] vs 0 )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : s d ( string_data ( vec_at [String] vs 0 ) )
    ( string_push_str ( first_str vs ) `0123456789012345678901234567890123456789012345678901234567890123456789` )
    ( puts d )
    ^ 0
}
