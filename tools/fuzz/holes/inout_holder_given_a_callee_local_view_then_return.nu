// inout_holder_given_a_callee_local_view_then_return: agora #336 — a callee `→ i` assigning its `inout` struct of views, whole, a view of its own local String, then `^ 0`; the caller reads the holder.
// Closed: storage the caller holds (a parameter) given whole a view of a binding the function releases is refused at every `^`, as where the body's scope ends (bck_param_view_check's borrower clause; agora #336, after #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: an inout holder given a callee local's view, then `^`
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string` )
    = w @ W { ( string_data b ) }
    ^ 0
}

@ main → i {
    : ~ W w @ W { `literal` }
    ( fill w )
    ( nurl_println . w v )
    ^ 0
}
