// view_param_kept_in_the_second_inout_holder: a view parameter stored into the second inout holder, read after its source ends.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #370: a view parameter stored into the second inout holder, read after its source ends
$ `stdlib/core/string.nu`

: W { s v }

@ second inout W first inout W other s src → v {
    = other @ W { src }
}

@ main → i {
    : ~ W a @ W { `a` }
    : ~ W b @ W { `b` }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        ( second a b ( string_data s ) )
    }
    ( nurl_println . b v )
    ^ 0
}
