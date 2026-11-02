// view_param_pushed_through_an_element_of_a_vec_parameter: agora #370 — a callee pushes its view parameter into an element of a Vec-of-Vecs parameter (agora #397)
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a callee pushes its view parameter into an element of a Vec-of-Vecs parameter (agora #397)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ push_into ( Vec ( Vec s ) ) vv s x → v {
    : ( Vec s ) w ( vec_at [( Vec s )] vv 0 )
    ( vec_push [s] w x )
}

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    {
        : String loc ( string_from `a heap string freed at the end of the inner block` )
        ( push_into vv ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
