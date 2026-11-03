// holder_viewing_a_string_param_returned_through_self_recursion: the holder comes back through a self-recursive function.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: the holder comes back through a self-recursive function
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fr String s i n → ( Vec s ) {
    ? == n 0 {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data s ) )
        ^ h
    } {}
    ^ ( fr s - n 1 )
}

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( fr s 3 )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
