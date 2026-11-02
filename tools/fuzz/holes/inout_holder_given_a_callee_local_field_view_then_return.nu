// inout_holder_given_a_callee_local_field_view_then_return: agora #336 — as inout_holder_given_a_callee_local_view_then_return, the view of a field of the callee's local struct.
// Closed: storage the caller holds (a parameter) given whole a view of a binding the function releases is refused at every `^`, as where the body's scope ends (bck_param_view_check's borrower clause; agora #336, after #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: an inout holder given a callee local field's view, then `^`
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ fill inout W w → i {
    : H h @ H { ( string_from `the callee's local struct's name` ) }
    = w @ W { ( string_data . h name ) }
    ^ 0
}

@ main → i {
    : ~ W w @ W { `literal` }
    ( fill w )
    ( nurl_println . w v )
    ^ 0
}
