// field_view_kept_while_a_sibling_field_is_replaced: agora #309 — a holder given a view of one field by an `inout` callee while a sibling field is replaced: accepted (the shape the fix must keep).
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #309: a holder given a view of one field by an `inout` callee while a sibling field is replaced: accepted (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }
: H { String name String other }

@ point inout W w s v → v { = w @ W { v } }

@ main → i {
    : ~ H h @ H { ( string_from `the name, kept` ) ( string_from `the other` ) }
    : ~ W w @ W { `literal` }
    ( point w ( string_data . h name ) )
    = . h other ( string_from `another other` )
    ( nurl_println . w v )
    ^ 0
}
