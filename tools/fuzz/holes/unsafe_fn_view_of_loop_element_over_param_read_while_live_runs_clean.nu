// unsafe_fn_view_of_loop_element_over_param_read_while_live_runs_clean: the guard of unsafe_fn_hands_back_a_view_of_its_loop_element: the caller reads the view while the container still holds the element, then clears it
// Closed (agora #489): the view points into the caller's argument, which lives while it is read; nothing is refused.
// map: §2.10 | A2 | runs-clean | - | agora #489: a raw view of an unsafe function's loop element, read while its container lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string read while it lives` ) )
    : s v ( first t )
    ( nurl_println v )
    ( vec_clear [String] t )
    ^ 0
}
