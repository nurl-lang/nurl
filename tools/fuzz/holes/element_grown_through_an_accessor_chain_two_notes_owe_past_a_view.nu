// element_grown_through_an_accessor_chain_two_notes_owe_past_a_view: agora #349 — an accessor chain `a1 → a2 → a3`, `a3` defined below main and lending `vs[0]`, grown inline
// Closed: a lend a module-end note still owes is decided with the final summaries, at the walk (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element grown through an accessor chain two notes owe, past a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ a1 ( Vec String ) vs → String {
    ^ ( a2 vs )
}

@ a2 ( Vec String ) vs → String {
    ^ ( a3 vs )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : s d ( string_data ( vec_at [String] vs 0 ) )
    ( string_push_str ( a1 vs ) `0123456789012345678901234567890123456789012345678901234567890123456789` )
    ( puts d )
    ^ 0
}

@ a3 ( Vec String ) vs → String {
    ^ ( vec_at [String] vs 0 )
}
