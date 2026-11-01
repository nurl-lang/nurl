// field_view_pushed_into_an_outer_vec_outlives_its_struct: agora #309 — a view of a block-local struct's String field pushed into an outer Vec of views, read after the block.
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #309: a view of a block-local struct's String field pushed into an outer Vec of views, read after the block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name }

@ main → i {
    : ~ ( Vec s ) vs ( vec_new [s] )
    {
        : H h @ H { ( string_from `a field's string, freed with its struct` ) }
        ( vec_push [s] vs ( string_data . h name ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
