// element_grown_through_a_forwarder_to_a_lender_defined_below: agora #349 — `mk` (above main) hands back `( helper vs )`, `helper` (below main) lends `( vec_at vs 0 )`; the result grown past a view
// Closed: a lend a module-end note still owes is decided with the final summaries, at the walk (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element grown through a forwarder to a lender defined below
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk ( Vec String ) vs → String {
    ^ ( helper vs )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : s d ( string_data ( vec_at [String] vs 0 ) )
    ( string_push_str ( mk vs ) `0123456789012345678901234567890123456789012345678901234567890123456789` )
    ( puts d )
    ^ 0
}

@ helper ( Vec String ) vs → String {
    ^ ( vec_at [String] vs 0 )
}
