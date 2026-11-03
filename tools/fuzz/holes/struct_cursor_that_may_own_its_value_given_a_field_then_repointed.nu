// struct_cursor_that_may_own_its_value_given_a_field_then_repointed: a struct cursor that may own its value (a borrow on one path, its own on the other) is given a field through itself; a view of the field is read after the cursor is re-pointed.
// Closed: a field given a value through a cursor keeps the cursor's raw state, BCK_MAYBE_OWNED, where bck_borrow_sweep put it back (it was read as a borrow and put back as one, so re-pointing it ended nothing).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a struct cursor that may own its value, given a field, re-pointed: a view of the field is read
$ `stdlib/core/string.nu`

: H { String name }

@ pick b own → i {
    : H root @ H { ( string_from `the root name, long enough to be on the heap surely` ) }
    : ~ H cur root
    ? own { = cur @ H { ( string_from `a fresh name, long enough to be on the heap surely` ) } } {}
    = . cur name ( string_from `a replaced name, long enough to be on the heap surely` )
    : s v ( string_data . cur name )
    = cur @ H { ( string_from `the next name, long enough to be on the heap surely` ) }
    ^ ( nurl_str_len v )
}

@ main → i {
    ( nurl_print_int ( pick T ) ) ( nurl_print `\n` )
    ^ 0
}
