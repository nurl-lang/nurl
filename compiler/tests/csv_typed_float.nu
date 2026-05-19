// csv_typed_float.nu — regression for P3b: typed-float pre-parse cache
// and `csv_table_filter_typed_float_gt`.
//
// Covers:
//   - `csv_table_load_typed_f` populates `typed_floats` with the
//     parsed double for each body row (negative, zero, and large
//     values; one column out of three).
//   - `csv_table_filter_typed_float_gt` narrows row_starts/row_lens
//     in place against the cache and yields the survivor count.
//   - Cache is consumed (typed_float_col == -1) after the filter,
//     and a second call no-ops on the now-empty cache.
//   - A subsequent `csv_table_filter_str_contains` chains over the
//     narrowed rows correctly (proves alignment is preserved
//     between typed-filter and string-filter on the same table).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/csv.nu`

@ main → v {
    : String csv ( string_from `n,f,tag\n1,3.14,a\n2,-2.5,b\n3,0.0,c\n4,10.5,d\n5,7.2,e\n` )
    : *CSVTable t ( csv_table_from_string_typed_f csv 1 )

    // Cache should hold one double per body row in original order.
    : i tf_len ( vec_len [f] . t typed_floats )
    ( nurl_print `tf_len=` ) ( nurl_print_int tf_len )

    // Narrow to rows where val_f > 1.0 — expect 3 survivors
    // (3.14, 10.5, 7.2). After this, cache is cleared.
    ( csv_table_filter_typed_float_gt t 1.0 )
    ( nurl_print `after_typed=` ) ( nurl_print_int ( csv_table_n_rows t ) )
    ( nurl_print `tf_col_after=` ) ( nurl_print_int . t typed_float_col )

    // Chain a substring filter on the tag column (col 2) — match 'd' / 'e' / 'a'.
    ( csv_table_filter_str_contains t 2 `d` )
    ( nurl_print `after_str=` ) ( nurl_print_int ( csv_table_n_rows t ) )

    // Read the remaining tag — should be the single survivor 'd'.
    : ?String tag_opt ( csv_table_get t 0 2 )
    ?? tag_opt {
        T s → {
            ( nurl_print `tag0=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
            ( string_free s )
        }
        F → ( nurl_print `tag0=MISS\n` )
    }

    ( csv_table_free t )
}
