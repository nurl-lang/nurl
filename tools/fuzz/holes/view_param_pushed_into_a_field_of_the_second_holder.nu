// view_param_pushed_into_a_field_of_the_second_holder: a view parameter pushed into a field of the second holder parameter.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #370 (#397): a view parameter pushed into a field of the second holder parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bag { ( Vec s ) items }
@ put inout Bag first inout Bag b s x → v { ( vec_push [s] . b items x ) }
@ main → i {
    : ~ Bag other @ Bag { ( vec_new [s] ) }
    : ~ Bag hold @ Bag { ( vec_new [s] ) }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        ( put other hold ( string_data s ) )
    }
    ( nurl_println ( vec_at [s] . hold items 0 ) )
    ^ 0
}
