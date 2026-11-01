// field_view_kept_while_its_struct_lives: agora #309 — a holder given a view of a struct's field, read while the struct lives: accepted (the shape the fix must keep).
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #309: a holder given a view of a struct's field, read while the struct lives: accepted (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ main → i {
    : H h @ H { ( string_from `a name that outlives the holder` ) }
    : ~ W w @ W { `literal` }
    = w @ W { ( string_data . h name ) }
    ( nurl_println . w v )
    ^ 0
}
