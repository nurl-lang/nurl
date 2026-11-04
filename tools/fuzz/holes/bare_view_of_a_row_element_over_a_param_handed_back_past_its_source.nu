// bare_view_of_a_row_element_over_a_param_handed_back_past_its_source: agora #471 — `~ row p { ^ ( string_data ( vec_at [String] row 0 ) ) }` over a `( Vec ( Vec String ) )` parameter; the caller clears its Vec, then reads the view
// Closed: a view of an element of a loop element is reached through an element of what the loop iterates too (`^row ^p`): `^k` (agora #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of an element of a parameter's loop element handed back, read after the caller cleared its argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec ( Vec String ) ) p → s {
    ~ row p { ^ ( string_data ( vec_at [String] row 0 ) ) }
    ^ `none`
}

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string the caller clears before reading` ) )
    ( vec_push [( Vec String )] vv r0 )
    : s v ( first vv )
    ( vec_clear [( Vec String )] vv )
    ( nurl_println v )
    ^ 0
}
