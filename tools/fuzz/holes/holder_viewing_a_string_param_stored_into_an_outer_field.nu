// holder_viewing_a_string_param_stored_into_an_outer_field: the returned holder is stored into a field of an outer struct.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: the returned holder is stored into a field of an outer struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box1 { ( Vec s ) items }
@ mkh String s → ( Vec s ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ h
}
@ main → i {
    : Box1 b @ Box1 { ( vec_new [s] ) }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = . b items ( mkh s )
    }
    ( nurl_println ( vec_at [s] . b items 0 ) )
    ^ 0
}
