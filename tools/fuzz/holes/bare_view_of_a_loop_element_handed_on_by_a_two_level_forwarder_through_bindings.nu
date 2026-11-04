// bare_view_of_a_loop_element_handed_on_by_a_two_level_forwarder_through_bindings: agora #471 — `fwd2` binds `( fwd r )`, `fwd` hands back `( first q )`; the caller clears its Vec, then reads the view
// Closed: a view bound to a callee's walk answer `2` keeps that answer's sources (`rva_`), so handing the binding back hands the answer on — for those sources only (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a parameter's loop element handed on by two forwarders, the outer through a binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ fwd ( Vec String ) q → s {
    ^ ( first q )
}

@ fwd2 ( Vec String ) r → s {
    : s v ( fwd r )
    ^ v
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( fwd2 t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
