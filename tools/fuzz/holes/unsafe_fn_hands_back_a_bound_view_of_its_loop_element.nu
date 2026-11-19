// unsafe_fn_hands_back_a_bound_view_of_its_loop_element: an `unsafe` function binds `: s w ( string_data x )` of its `~` loop's element over a parameter and hands `w` back; its safe caller cleared the container and read the view
// Closed (agora #489): in raw code a `~` loop's element is derived, in the raw provenance graph, from what the loop iterates (gen_foreach, as a `:` binding of a read out of it is), so a view of it handed back points into that parameter (retptr) and the caller's view is tied to its argument. Safe code's walk answers it itself, `^k` (agora #471).
// main 1072fd23: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function binds `: s w ( string_data x )` of its `~` loop's element over a parameter and hands `w` back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec String ) p → s {
    ~ x p {
        : s w ( string_data x )
        ^ w
    }
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
