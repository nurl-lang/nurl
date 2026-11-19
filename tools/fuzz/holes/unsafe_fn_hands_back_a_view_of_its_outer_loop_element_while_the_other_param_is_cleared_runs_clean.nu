// unsafe_fn_hands_back_a_view_of_its_outer_loop_element_while_the_other_param_is_cleared_runs_clean: the guard of unsafe_fn_hands_back_a_view_of_its_outer_loop_element_from_an_inner_loop: the caller clears the other argument, the one the view is not of, then reads the view
// Closed (agora #489): in raw code a `~` loop's element is derived, in the raw provenance graph, from what the loop iterates (gen_foreach, as a `:` binding of a read out of it is), so a view of it handed back points into that parameter (retptr) and the caller's view is tied to its argument. Safe code's walk answers it itself, `^k` (agora #471).
// main 1072fd23: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #489: a view of an unsafe function's outer loop element is tied to its own argument only
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec String ) p ( Vec i ) q → s {
    ~ x p {
        ~ k q { ^ ( string_data x ) }
    }
    ^ `none`
}

@ main → i {
    : ( Vec i ) n ( vec_new [i] )
    ( vec_push [i] n 1 )
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t n )
    ( vec_clear [i] n )
    ( nurl_println v )
    ^ 0
}
