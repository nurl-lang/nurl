// callee_local_view_given_whole_to_an_inout_holder: agora #309 — an `inout` callee assigns its parameter a struct of views viewing its own local String; the caller reads it after the call.
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #309: an `inout` callee assigns its parameter a struct of views viewing its own local String; the caller reads it after the call
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w → v {
    : String b ( string_from `the callee's local string` )
    = w @ W { ( string_data b ) }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ( fill w )
    ( nurl_println . w v )
    ^ 0
}
