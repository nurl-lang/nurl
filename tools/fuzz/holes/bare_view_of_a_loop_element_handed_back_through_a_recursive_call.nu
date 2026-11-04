// bare_view_of_a_loop_element_handed_back_through_a_recursive_call: agora #471 — `pick2 a b k` hands back `( string_data x )` from inside `~ x a`, or `( pick2 b a 0 )`; the caller clears its second argument, then reads the view
// Closed: functions whose walks ask each other's answers settle them together (__bck_walk_deferred): the recursive call's `^0` is the caller's `^1` (agora #471, #422).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element handed back through a recursive call with the parameters swapped
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick2 ( Vec String ) a ( Vec String ) b i k → s {
    ? == k 0 { ~ x a { ^ ( string_data x ) } } {}
    ? == k 1 { ^ ( pick2 b a 0 ) } {}
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string of t, kept` ) )
    : ( Vec String ) u ( vec_new [String] )
    ( vec_push [String] u ( string_from `a string of u, cleared before the view is read` ) )
    : s v ( pick2 t u 1 )
    ( vec_clear [String] u )
    ( nurl_println v )
    ^ 0
}
