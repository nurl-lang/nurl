// H479: `( csv_table_view t row col )` returned a Slice into the table's
// buffer built from a bare pointer, so the borrow checker did not tie it
// to `t`: it was read after `csv_table_free t` released the buffer.
// Closed: the view is read through the table's state bound out of the
// handle, so it borrows from `t` and ends with it (docs/MEMORY.md §2.10).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : CSVTable t ( csv_table_from_string ( string_from `a,b\n1111111111111111111111111111,2\n` ) )
    : ( Slice u ) v ( csv_table_view t 0 0 )
    ( csv_table_free t )
    ( nurl_println_int # i ( slice_byte v 3 ) )
    ^ 0
}
