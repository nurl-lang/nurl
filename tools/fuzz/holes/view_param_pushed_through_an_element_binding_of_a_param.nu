// view_param_pushed_through_an_element_binding_of_a_param: a view parameter pushed into an element of a Vec parameter bound first, read after its source ends.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name), so a store of it through a loop element, a join or an element binding of the function's own parameter lands in that parameter (`hr_`) as a pair of the function's g_fn_vkeeps answer, and the caller's argument holds the view (agora #454).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #454: a view parameter pushed into an element of a Vec parameter bound first, read after its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fill ( Vec ( Vec s ) ) vv s x → v {
    : ( Vec s ) e ( vec_at [( Vec s )] vv 0 )
    ( vec_push [s] e x )
}

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    {
        : String loc ( string_from `a string that ends first, long enough for heap` )
        ( fill vv ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
