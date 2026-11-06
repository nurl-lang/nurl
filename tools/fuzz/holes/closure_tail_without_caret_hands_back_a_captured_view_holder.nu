// closure_tail_without_caret_hands_back_a_captured_view_holder: a closure literal's implicit tail `?` expression without `^` hands back a local Vec holding a view of its capture.
// Closed: `gen_block_expr` propagates the tail expression's source summary (`g_bck_fall_sx`) across `?` and `??`, and `__bck_fall_ret_record` emits the `ret` row before `bck_block_exit` closes the body's scope (h220; agora #473).
// main a3be3e7c: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | rejected | h220 | agora #473: a closure literal's implicit tail `?` without `^` hands back a local Vec of its captured view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ call1 ( @ ( Vec s ) b ) f → ( Vec s ) { ^ ( f T ) }

@ leak → ( Vec s ) {
    : String s ( string_from `hello world from freed string buffer on heap` )
    ^ ( call1 \ b c → ( Vec s ) {
        : ( Vec s ) v ( vec_new [s] )
        ( vec_push [s] v ( string_data s ) )
        ? c v ( vec_new [s] )
    } )
}

@ main → i {
    : ( Vec s ) out ( leak )
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
