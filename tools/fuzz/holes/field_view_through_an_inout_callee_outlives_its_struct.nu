// field_view_through_an_inout_callee_outlives_its_struct: agora #309 — a view of a block-local struct's String field handed to an `inout` callee that stores it whole, read after the block.
// Closed: a binding's scope end ends what borrows from or depends on its fields too (a view of `. h name` is recorded on the field's path; bck_root_end), and storage the caller holds that borrows from a binding released here is refused, as storage that depends on one is (bck_borrow_end → bck_caller_view_diag; agora #309).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #309: a view of a block-local struct's String field handed to an `inout` callee that stores it whole, read after the block
$ `stdlib/core/string.nu`

: W { s v }

@ point inout W w s v → v { = w @ W { v } }

: H { String name }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : H h @ H { ( string_from `a field's string, freed with its struct` ) }
        ( point w ( string_data . h name ) )
    }
    ( nurl_println . w v )
    ^ 0
}
