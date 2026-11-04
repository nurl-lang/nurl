// view_of_a_loop_element_over_a_param_returned_past_its_source: agora #471 — `views` returns a `( Vec s )` of `( string_data x )` for each `~ x xs` of its parameter; the caller's `t` ends before the result is read
// Closed: the value handed back views the parameter's elements' own storage: `^k` in its g_fn_rviews answer (bck_ret_view_check, __rv_note), and the caller's result depends on its argument through an element (agora #471, #422).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a Vec of views of a parameter's loop elements returned, read after the caller's argument ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ views ( Vec String ) xs → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    ~ x xs { ( vec_push [s] out ( string_data x ) ) }
    ^ out
}

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block` ) )
        = ws ( views t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
