// callee_local_field_view_given_whole_to_an_inout_holder: agora #309 — the same with a view of a field of the callee's own local struct.
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #309: the same with a view of a field of the callee's own local struct
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ fill inout W w → v {
    : H h @ H { ( string_from `the callee's local struct's name` ) }
    = w @ W { ( string_data . h name ) }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ( fill w )
    ( nurl_println . w v )
    ^ 0
}
