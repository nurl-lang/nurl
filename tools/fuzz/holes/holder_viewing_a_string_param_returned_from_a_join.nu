// holder_viewing_a_string_param_returned_from_a_join: the holder is one arm of a join written in the return.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: the holder is one arm of a join written in the return
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick String s i c → ( Vec s ) {
    : ( Vec s ) a ( vec_new [s] )
    ( vec_push [s] a ( string_data s ) )
    : ( Vec s ) b ( vec_new [s] )
    ( vec_push [s] b `static` )
    ^ ? == c 0 a b
}
@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( pick s 0 )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
