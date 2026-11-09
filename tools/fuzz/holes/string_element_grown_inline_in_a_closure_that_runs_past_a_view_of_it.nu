// string_element_grown_inline_in_a_closure_that_runs_past_a_view_of_it: agora #349 — `string_push_str ( vec_at vs 0 ) …` inside a closure that runs while a view of that String is kept
// Closed: the closure's effect is marked lent on the captures its source expression names, and replays where the closure runs (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #349: a String element grown inline in a closure that runs past a view of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : String e0 ( vec_at [String] vs 0 )
    : s d ( string_data e0 )
    : ( @ v ) g \ → v { ( string_push_str ( vec_at [String] vs 0 ) `0123456789012345678901234567890123456789012345678901234567890123456789` ) }
    ( g )
    ( puts d )
    ^ 0
}
