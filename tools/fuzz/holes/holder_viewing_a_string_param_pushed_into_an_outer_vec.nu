// holder_viewing_a_string_param_pushed_into_an_outer_vec: the returned holder is pushed into an outer Vec.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: the returned holder is pushed into an outer Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkh String s → ( Vec s ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ h
}

@ main → i {
    : ( Vec ( Vec s ) ) all ( vec_new [( Vec s )] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        ( vec_push [( Vec s )] all ( mkh s ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] all 0 ) 0 ) )
    ^ 0
}
