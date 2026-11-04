// bare_view_of_a_loop_element_over_a_struct_params_field_handed_back_by_a_callee_below: agora #471 — `@ f s a B b → s { ~ x . b items { ^ ( string_data x ) } ^ a }` defined below its caller; the caller clears `. b items`, then reads the view
// Closed: a caller of a bare-`s` callee not walked yet, handed something a loop could iterate a part of (a parameter that is not a number, a view or a String — here the second, a struct), waits for its answer, `^1` (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of the element of a loop over a struct parameter's field, handed back by a callee defined below its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ main → i {
    : B b @ B { ( vec_new [String] ) 0 }
    ( vec_push [String] . b items ( string_from `a string the caller clears before reading` ) )
    : s v ( f `lit` b )
    ( vec_clear [String] . b items )
    ( nurl_println v )
    ^ 0
}

@ f s a B b → s {
    ~ x . b items { ^ ( string_data x ) }
    ^ a
}
