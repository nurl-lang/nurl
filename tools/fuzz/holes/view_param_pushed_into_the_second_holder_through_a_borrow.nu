// view_param_pushed_into_the_second_holder_through_a_borrow: a view parameter pushed through a borrow of the second holder parameter.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder or a result given it names that parameter in the function's answers, g_fn_vkeeps / g_fn_rviews, and a view argument is tied to the holder its callee's answer names (agora #341, #346, #370).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #370 (#397): a view parameter pushed through a borrow of the second holder parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ idv ( Vec s ) v → ( Vec s ) { ^ v }
@ put inout ( Vec s ) first inout ( Vec s ) v s x → v {
    : ( Vec s ) w ( idv v )
    ( vec_push [s] w x )
}
@ main → i {
    : ~ ( Vec s ) other ( vec_new [s] )
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        ( put other hold ( string_data s ) )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
