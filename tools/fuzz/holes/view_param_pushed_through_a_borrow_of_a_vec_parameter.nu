// view_param_pushed_through_a_borrow_of_a_vec_parameter: agora #370 — a callee pushes its view parameter into a Vec parameter through ( id v ) (agora #397, folded in)
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a callee pushes its view parameter into a Vec parameter through ( id v ) (agora #397, folded in)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec s ) x → ( Vec s ) { ^ x }

@ push_into ( Vec s ) v s x → v {
    : ( Vec s ) w ( id v )
    ( vec_push [s] w x )
}

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    {
        : String loc ( string_from `a heap string freed at the end of the inner block` )
        ( push_into vs ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
