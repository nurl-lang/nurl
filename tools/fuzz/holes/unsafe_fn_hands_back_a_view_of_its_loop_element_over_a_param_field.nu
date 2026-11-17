// unsafe_fn_hands_back_a_view_of_its_loop_element_over_a_param_field: an `unsafe` function hands back a view of its `~` loop's element over a struct parameter's field; its safe caller cleared the field and read the view
// Closed (agora #489): in raw code a `~` loop's element is derived, in the raw provenance graph, from what the loop iterates (gen_foreach, as a `:` binding of a read out of it is), so a view of it handed back points into that parameter (retptr) and the caller's view is tied to its argument. Safe code's walk answers it itself, `^k` (agora #471).
// main 1072fd23: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function hands back a view of its `~` loop's element over a struct parameter's field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rows { ( Vec String ) rows }

unsafe @ first Rows p → s {
    ~ x . p rows { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : Rows t @ Rows { ( vec_new [String] ) }
    ( vec_push [String] . t rows ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] . t rows )
    ( nurl_println v )
    ^ 0
}
