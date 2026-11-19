// unsafe_fn_hands_back_a_view_of_its_loop_element_inside_a_loop_over_another_param: an `unsafe` function hands back a view of its inner `~` loop's element over one parameter, inside a loop over another; its safe caller cleared the first and read the view
// Closed (agora #489): in raw code a `~` loop's element is derived, in the raw provenance graph, from what the loop iterates (gen_foreach, as a `:` binding of a read out of it is), so a view of it handed back points into that parameter (retptr) and the caller's view is tied to its argument. Safe code's walk answers it itself, `^k` (agora #471).
// main 1072fd23: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #489: a view of an unsafe function's inner loop element over a parameter, the outer loop over another
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec i ) q ( Vec String ) p → s {
    ~ k q {
        ~ x p { ^ ( string_data x ) }
    }
    ^ `none`
}

@ main → i {
    : ( Vec i ) n ( vec_new [i] )
    ( vec_push [i] n 1 )
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first n t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
