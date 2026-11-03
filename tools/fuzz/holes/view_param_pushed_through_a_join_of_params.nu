// view_param_pushed_through_a_join_of_params: a view parameter pushed into a join of two inout Vec parameters, read after its source ends.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name), so a store of it through a loop element, a join or an element binding of the function's own parameter lands in that parameter (`hr_`) as a pair of the function's g_fn_vkeeps answer, and the caller's argument holds the view (agora #454).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #454: a view parameter pushed into a join of two inout Vec parameters, read after its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fill inout ( Vec s ) a inout ( Vec s ) b i c s x → v {
    : ( Vec s ) t ? == c 0 a b
    ( vec_push [s] t x )
}

@ main → i {
    : ~ ( Vec s ) a ( vec_new [s] )
    : ~ ( Vec s ) b ( vec_new [s] )
    {
        : String loc ( string_from `a string that ends first, long enough for heap` )
        ( fill a b 1 ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] b 0 ) )
    ^ 0
}
