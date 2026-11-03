// vec_of_drop_literals_holding_a_view_param_returned_viewing_a_younger_string: a `% Drop` literal holding a view parameter pushed into a returned Vec, given a view of a younger String.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #341: a `% Drop` literal holding a view parameter pushed into a returned Vec, given a view of a younger String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ mk s v → ( Vec W ) {
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { v } )
    ^ ws
}

@ main → i {
    : ~ ( Vec W ) a ( mk `literal` )
    : String s ( string_from `a string declared after a, so dropped before it at the end of main` )
    = a ( mk ( string_data s ) )
    ^ 0
}
