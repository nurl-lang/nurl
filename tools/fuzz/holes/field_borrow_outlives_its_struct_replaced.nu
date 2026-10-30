// field_borrow_outlives_its_struct_replaced: a binding read out of a field outlived its struct given a new value (`= h @ Holder { … }`), which released the old one, field and all.
// Closed: the borrow borrows the field's path, and its struct given a new value ends it, as any borrow's source does; a store replacing just that field instead hands the old value to the binding (a String / Vec / handle field: `fborrow`, __fs_viewers_take).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h332 | the same binding outlived its struct given a new value; ended by it now (a store replacing just that field hands the binding the old value)
$ `stdlib/core/string.nu`

: Holder { String name }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `x` ) }
    : String n . h name
    = h @ Holder { ( string_from `y` ) }
    ( nurl_println ( string_data n ) )
    ^ 0
}
