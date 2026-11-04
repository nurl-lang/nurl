// bare_view_of_a_loop_element_over_a_param_handed_back_runs_clean: agora #471 — `first` hands back `( string_data x )` from inside `~ x p`; the caller grows its Vec, then reads the view (the shape the fix must keep)
// Closed: the answer is `^k`, through an element: the caller's Vec growing leaves the view be (agora #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a bare view of a parameter's loop element handed back, read after the caller grew its argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string that outlives its view` ) )
    : s v ( first t )
    ( vec_push [String] t ( string_from `a second string, which may move the buffer` ) )
    ( nurl_println v )
    ^ 0
}
