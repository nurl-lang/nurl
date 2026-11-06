// closure_hands_back_a_local_vec_of_its_captured_view: a closure literal pushes a captured view into a local Vec and hands it back.
// Closed: a closure's capture or inout parameter that holds views (`cv_`) stands for itself in `bck_sx_name` (`@cap` / `@cip` / `@cpv`), and `bck_ret_view_check` refuses a closure return whose sources reach any capture (`__srcs_any_capture`, h220; agora #473).
// main a3be3e7c: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | rejected | h220 | agora #473: a closure literal pushes a captured view into a local Vec and hands it back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ call1 ( @ ( Vec s ) i ) f → ( Vec s ) { ^ ( f 0 ) }

@ leak → ( Vec s ) {
    : String s ( string_from `hello world from freed string buffer on heap` )
    : s w ( string_data s )
    ^ ( call1 \ i x → ( Vec s ) {
        : ( Vec s ) v ( vec_new [s] )
        ( vec_push [s] v w )
        ^ v
    } )
}

@ main → i {
    : ( Vec s ) out ( leak )
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
