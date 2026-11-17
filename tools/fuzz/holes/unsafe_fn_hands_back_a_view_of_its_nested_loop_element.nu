// unsafe_fn_hands_back_a_view_of_its_nested_loop_element: an `unsafe` function hands back a view of the inner `~` loop's element over rows of a parameter; its safe caller cleared the container and read the view
// Closed (agora #489): in raw code a `~` loop's element is derived, in the raw provenance graph, from what the loop iterates (gen_foreach, as a `:` binding of a read out of it is), so a view of it handed back points into that parameter (retptr) and the caller's view is tied to its argument. Safe code's walk answers it itself, `^k` (agora #471).
// main 1072fd23: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function hands back a view of the inner `~` loop's element over rows of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec ( Vec String ) ) p → s {
    ~ row p {
        ~ x row { ^ ( string_data x ) }
    }
    ^ `none`
}

@ main → i {
    : ( Vec ( Vec String ) ) t ( vec_new [( Vec String )] )
    : ( Vec String ) row ( vec_new [String] )
    ( vec_push [String] row ( string_from `a string the caller clears before reading its view` ) )
    ( vec_push [( Vec String )] t row )
    : s v ( first t )
    ( vec_clear [( Vec String )] t )
    ( nurl_println v )
    ^ 0
}
