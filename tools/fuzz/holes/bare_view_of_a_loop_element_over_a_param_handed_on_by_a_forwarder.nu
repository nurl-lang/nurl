// bare_view_of_a_loop_element_over_a_param_handed_on_by_a_forwarder: agora #471 — `@ fwd ( Vec String ) q → s { ^ ( first q ) }` over `first`, which hands back `( string_data x )` from inside `~ x p`; the caller clears its Vec, then reads the view
// Closed: the forwarder's result views what `first`'s walk answers for its argument, `^0`: reached through `q`'s elements only, it is the forwarder's answer too (`__src_indirect` of a bare return's sources; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a parameter's loop element handed on by a forwarder, read after the caller cleared its argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ fwd ( Vec String ) q → s {
    ^ ( first q )
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( fwd t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
