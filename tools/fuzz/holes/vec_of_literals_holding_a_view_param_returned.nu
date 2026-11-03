// vec_of_literals_holding_a_view_param_returned: a literal holding a view parameter pushed into a local Vec that is handed back, kept past the String.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #341: a literal holding a view parameter pushed into a local Vec that is handed back, kept past the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ mk s v → ( Vec W ) {
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { v } )
    ^ ws
}

@ main → i {
    : ~ ( Vec W ) a ( mk `literal` )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = a ( mk ( string_data s ) )
    }
    ( nurl_println . ( vec_at [W] a 0 ) v )
    ^ 0
}
