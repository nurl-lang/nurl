// H471: `csv_table_load` of a file it could not read returned the null
// table, and every accessor read through it: `csv_table_n_rows` of it
// dereferenced address 0.
// Closed: a failed load returns an empty table that `csv_table_ok`
// answers F for; every accessor reads it as a table of no rows.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/string.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : CSVTable t ( csv_table_load `/nonexistent/h471.csv` )
    ( nurl_println_int ( csv_table_n_rows t ) )
    ( nurl_println_int ? ( csv_table_ok t ) 1 0 )
    ^ 0
}
