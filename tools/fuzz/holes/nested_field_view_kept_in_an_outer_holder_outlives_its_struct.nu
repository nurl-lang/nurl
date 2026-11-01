// nested_field_view_kept_in_an_outer_holder_outlives_its_struct: agora #309 — the same with a field of a field (`. . h inner name`).
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #309: the same with a field of a field (`. . h inner name`)
$ `stdlib/core/string.nu`

: W { s v }
: I { String name }
: H { I inner }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : H h @ H { @ I { ( string_from `a nested field's string` ) } }
        = w @ W { ( string_data . . h inner name ) }
    }
    ( nurl_println . w v )
    ^ 0
}
