// H103: a CSV cell view (not NUL-terminated) read as a string ran past the cell.
$ `stdlib/core/string.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : CSVTable t ( csv_table_from_string ( string_from `"a""b",c\n` ) )
    ( nurl_println ( csv_table_view t 0 0 ) )
    ^ 0
}
