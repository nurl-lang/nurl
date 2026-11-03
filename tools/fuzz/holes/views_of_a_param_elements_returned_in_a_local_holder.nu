// views_of_a_param_elements_returned_in_a_local_holder: a local Vec of views of a parameter element handed back, the parameter cleared after.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #404: a local Vec of views of a parameter element handed back, the parameter cleared after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
@ index ( Vec String ) arena → ( Vec s ) {
    : ( Vec s ) idx ( vec_new [s] )
    : String e ( vec_at [String] arena 0 )
    ( vec_push [s] idx ( string_data e ) )
    ^ idx
}
@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    ( vec_push [String] arena ( string_from `an arena string long enough for the heap, surely` ) )
    : ( Vec s ) idx ( index arena )
    ( vec_clear [String] arena )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
