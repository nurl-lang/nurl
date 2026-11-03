// field_given_through_a_struct_cursor_released_at_its_repoint: a field given a value through a `: ~` copy of a struct is that copy's own; re-pointing the copy releases it under a view of it.
// Closed: a field given a value through a binding that borrows makes that binding maybe-owned (BCK_MAYBE_OWNED): codegen stores the value into the binding's copy and releases it where the binding is given a new value, so a view of it ends there (bck_borrow_sweep).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a field given through a `: ~` copy of a struct; a view of it outlives the copy's re-point
$ `stdlib/core/string.nu`

: H { String name }

@ main → i {
    : H root @ H { ( string_from `the root name, long enough to be on the heap surely` ) }
    : ~ H cur root
    = . cur name ( string_from `a replaced name, long enough to be on the heap surely` )
    : s v ( string_data . cur name )
    = cur @ H { ( string_from `x` ) }
    ( nurl_println v )
    ^ 0
}
