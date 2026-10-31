// csv_filter_predicate_frees_the_rows_it_walks: `csv_table_filter t pred` held raw pointers to the table's row
// index across the predicate calls, and the predicate holds the table:
// sorting it there replaced the index, and the filter read the freed one.
// Closed: the index is read afresh after each call, and a row the
// predicate dropped is not kept.
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §3.3d | B | runs-clean | h478 | `csv_table_filter t pred` held raw pointers to the table's row index across the predicate calls, and the predicate holds the table: sorting it there replaced the index, and the filter read the…
$ `stdlib/core/string.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : CSVTable t ( csv_table_from_string ( string_from `a,b\n1,2\n3,4\n5,6\n7,8\n9,10\n` ) )
    ( csv_table_filter t \ CSVTable x i r → b {
        ( csv_table_sort_by_int x 0 F )
        ^ T
    } )
    ( nurl_println_int ( csv_table_n_rows t ) )
    ^ 0
}
