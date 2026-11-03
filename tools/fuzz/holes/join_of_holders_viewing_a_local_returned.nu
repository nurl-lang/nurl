// join_of_holders_viewing_a_local_returned: a join of local holders, one viewing a String the function releases, handed back.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a join of local holders, one viewing a String the function releases, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ bad i c → ( Vec s ) {
    : String own ( string_from `a local heap string long enough for the heap` )
    : ( Vec s ) a ( vec_new [s] )
    ( vec_push [s] a ( string_data own ) )
    : ( Vec s ) b ( vec_new [s] )
    ^ ? == c 0 a b
}

@ main → i {
    : ( Vec s ) h ( bad 0 )
    ( nurl_println ( vec_at [s] h 0 ) )
    ^ 0
}
