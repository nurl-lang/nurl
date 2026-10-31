// field_borrow_outlives_its_struct_moved: a binding read out of a field (`: String n . h name`) borrowed nothing in the borrow checker, so it outlived its struct handed to a `sink` (`( eat h )`) and read what the callee released.
// Closed: such a borrow borrows the field's path (`h.name`): its struct moved, consumed or dropped, reading it is rejected — bck_record_binding kept the right-hand side's reads off the `let` row, and bck_note_borrow, reading them from there, recorded a borrow of nothing.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h331 | a binding read out of a field borrowed nothing in the checker (the let row's reads were empty) and outlived its struct handed to a sink; it borrows the field's path now
$ `stdlib/core/string.nu`

: Holder { String name }

@ eat sink Holder h → v {}

@ main → i {
    : Holder h @ Holder { ( string_from `x` ) }
    : String n . h name
    ( eat h )
    ( nurl_println ( string_data n ) )
    ^ 0
}
