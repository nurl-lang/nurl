// inout_holder_given_a_callee_local_view_early_return: agora #336 — as inout_holder_given_a_callee_local_view_then_return, the callee leaving by an early `^` in an arm before it points the holder back.
// Closed: storage the caller holds (a parameter) given whole a view of a binding the function releases is refused at every `^`, as where the body's scope ends (bck_param_view_check's borrower clause; agora #336, after #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: an inout holder given a callee local's view, then an early `^`
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → v {
    : String b ( string_from `the callee's local string` )
    = w @ W { ( string_data b ) }
    ? == k 1 { ^ } {}
    = w @ W { `literal` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
