// bare_view_of_a_loop_element_handed_on_by_a_forwarder_through_a_mutable_binding: agora #471 — `: ~ s v d  = v ( first q )  ^ v`; the caller clears its Vec, then reads the view
// Closed: a view bound to a callee's walk answer `2` keeps that answer's sources (`rva_`), so handing the binding back hands the answer on — for those sources only (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a parameter's loop element handed on through a binding given it by `=`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ fwd s d ( Vec String ) q → s {
    : ~ s v d
    = v ( first q )
    ^ v
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( fwd `none` t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
