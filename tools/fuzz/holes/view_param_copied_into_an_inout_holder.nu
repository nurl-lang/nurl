// view_param_copied_into_an_inout_holder: a local copy of a view parameter stored into an inout struct, the source ending first.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #346: a local copy of a view parameter stored into an inout struct, the source ending first
$ `stdlib/core/string.nu`

: V { s v }

@ setw inout V w s p → v {
    : s t p
    = w @ V { t }
}

@ main → i {
    : ~ V w @ V { `literal` }
    {
        : String b ( string_from `a heap string long enough to be on the heap for sure` )
        ( setw w ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
