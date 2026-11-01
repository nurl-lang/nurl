// inout_option_holder_given_a_callee_local_view_then_return: agora #336 — as inout_holder_given_a_callee_local_view_then_return, for an `inout ?s` holder.
// Closed: storage the caller holds (a parameter) given whole a view of a binding the function releases is refused at every `^`, as where the body's scope ends (bck_param_view_check's borrower clause; agora #336, after #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: an inout `?s` holder given a callee local's view, then `^`
$ `stdlib/core/string.nu`

@ fill inout ? s w → i {
    : String b ( string_from `the callee's local string` )
    = w @ ?s { T ( string_data b ) }
    ^ 0
}

@ main → i {
    : ~ ? s w @ ?s { F }
    : i _r ( fill w )
    ?? w { T v → { ( nurl_println v ) } F → { ( nurl_println `none` ) } }
    ^ 0
}
