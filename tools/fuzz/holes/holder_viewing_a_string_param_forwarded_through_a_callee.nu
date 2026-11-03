// holder_viewing_a_string_param_forwarded_through_a_callee: a function hands back what another one hands back.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a function hands back what another one hands back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkh String s → ( Vec s ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ h
}

@ outer String s → ( Vec s ) { ^ ( mkh s ) }

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( outer s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
