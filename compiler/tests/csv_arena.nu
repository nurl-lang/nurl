// csv_arena.nu — coverage of the arena-backed CSVTable.
//
// The table layout (one content blob + flat (off, len) cells +
// parallel row_starts / row_lens) exposes both borrowed `s` views
// and owned-String accessors. We exercise:
//   - basic load → n_rows / n_cols / view / view_len / get / get_string
//   - col_index lookup
//   - filter (closure-based; (row_starts, row_lens) shrink only)
//   - sort_by_int / _by_float / _by_string (permutation on the
//     parallel vecs, flat_cells untouched)
//   - sort stability + edge cases (all-equal keys, single row)
//   - truncate (in-place row count clamp)
//
// All tests print compact tags so correct.txt diffs are obvious.

$ `stdlib/core/string.nu`
$ `stdlib/ext/csv.nu`

@ load_table s csv → *CSVTable {
    : String text ( string_from csv )
    : *CSVTable t ( csv_table_from_string text )
    ^ t
}

@ print_col * CSVTable t i col → v {
    : i n ( csv_table_n_rows t )
    : ~ i i 0
    ~ < i n {
        : ?String s_opt ( csv_table_get t i col )
        ?? s_opt {
            T s → { ( nurl_print ( string_data s ) ) ( nurl_print ` ` ) ( string_free s ) }
            F → { ( nurl_print `? ` ) }
        }
        = i + i 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    // ── 1. basic load: shape + headers + first/last row access ────────
    : *CSVTable t1 ( load_table `n,name,score\n7,a,1.5\n-3,b,2.5\n0,c,3.5\n` )
    ( nurl_print `n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `n_cols=` ) ( nurl_print ( nurl_str_int ( csv_table_n_cols t1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `col_n=` ) ( print_col t1 0 )
    ( nurl_print `col_name=` ) ( print_col t1 1 )

    // ── 2. col_index lookup ───────────────────────────────────────────
    : ?i ci_o ( csv_table_col_index t1 `name` )
    ?? ci_o { T ix → { ( nurl_print `idx_name=` ) ( nurl_print ( nurl_str_int ix ) ) ( nurl_print `\n` ) } F → {} }
    : ?i miss_o ( csv_table_col_index t1 `nope` )
    ?? miss_o { T _ → { ( nurl_print `idx_nope=hit\n` ) } F → { ( nurl_print `idx_nope=miss\n` ) } }

    // ── 3. view / view_len: borrowed bytes (NOT NUL-terminated) ───────
    : i vl ( csv_table_view_len t1 1 1 )
    ( nurl_print `view_len_(1,1)=` ) ( nurl_print ( nurl_str_int vl ) ) ( nurl_print `\n` )
    : ?String gs ( csv_table_get t1 1 1 )
    ?? gs { T s → { ( nurl_print `get(1,1)=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } F → {} }
    ( csv_table_free t1 )

    // ── 4. sort_by_int asc on a 5-row table ───────────────────────────
    : *CSVTable t2 ( load_table `n,tag\n7,a\n-3,b\n0,c\n42,d\n-1,e\n` )
    ( csv_table_sort_by_int t2 0 T )
    ( nurl_print `int_asc_n=` ) ( print_col t2 0 )
    ( nurl_print `int_asc_tag=` ) ( print_col t2 1 )

    // ── 5. sort_by_int desc on the same table ─────────────────────────
    ( csv_table_sort_by_int t2 0 F )
    ( nurl_print `int_desc_n=` ) ( print_col t2 0 )
    ( csv_table_free t2 )

    // ── 6. unparseable cells coerce to 0 ──────────────────────────────
    : *CSVTable t3 ( load_table `n,tag\n3,x\nabc,y\n-1,z\n` )
    ( csv_table_sort_by_int t3 0 T )
    ( nurl_print `unparse_n=` ) ( print_col t3 0 )
    ( nurl_print `unparse_tag=` ) ( print_col t3 1 )
    ( csv_table_free t3 )

    // ── 7. sort_by_float asc/desc, mixed signs ────────────────────────
    : *CSVTable t4 ( load_table `f,name\n3.14,pi\n-2.5,n25\n0.0,zero\n10.5,big\n` )
    ( csv_table_sort_by_float t4 0 T )
    ( nurl_print `float_asc_name=` ) ( print_col t4 1 )
    ( csv_table_sort_by_float t4 0 F )
    ( nurl_print `float_desc_name=` ) ( print_col t4 1 )
    ( csv_table_free t4 )

    // ── 8. sort_by_string asc/desc ────────────────────────────────────
    : *CSVTable t5 ( load_table `name,id\ndelta,1\nalpha,2\ncharlie,3\nbravo,4\n` )
    ( csv_table_sort_by_string t5 0 T )
    ( nurl_print `str_asc_id=` ) ( print_col t5 1 )
    ( csv_table_sort_by_string t5 0 F )
    ( nurl_print `str_desc_id=` ) ( print_col t5 1 )
    ( csv_table_free t5 )

    // ── 9. filter: keep rows where col 0 (int) > 0 ────────────────────
    : *CSVTable t6 ( load_table `n,tag\n5,a\n-1,b\n0,c\n7,d\n-3,e\n2,f\n` )
    ( csv_table_filter t6 \ * CSVTable tt i row → b {
        : s sv ( csv_table_view tt row 0 )
        : i sl ( csv_table_view_len tt row 0 )
        : i n ( nurl_parse_int_range sv sl )
        ^ > n 0
    } )
    ( nurl_print `filter_n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t6 ) ) ) ( nurl_print `\n` )
    ( nurl_print `filter_tag=` ) ( print_col t6 1 )
    ( csv_table_free t6 )

    // ── 10. truncate (clamp + no-op when n exceeds row count) ─────────
    : *CSVTable t7 ( load_table `n,tag\n1,a\n2,b\n3,c\n4,d\n5,e\n` )
    ( csv_table_truncate t7 3 )
    ( nurl_print `trunc3_n=` ) ( print_col t7 0 )
    ( csv_table_truncate t7 99 )  // no-op: keep > current
    ( nurl_print `trunc_keep_n=` ) ( print_col t7 0 )
    ( csv_table_truncate t7 0 )
    ( nurl_print `trunc0_n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t7 ) ) ) ( nurl_print `\n` )
    ( csv_table_free t7 )

    // ── 11. all-equal keys: relative input order preserved ────────────
    : *CSVTable t8 ( load_table `k,id\n5,a\n5,b\n5,c\n5,d\n` )
    ( csv_table_sort_by_int t8 0 T )
    ( nurl_print `equal_keys_id=` ) ( print_col t8 1 )
    ( csv_table_free t8 )

    // ── 12. single-row table is a sort no-op ──────────────────────────
    : *CSVTable t9 ( load_table `n,name\n42,solo\n` )
    ( csv_table_sort_by_int t9 0 T )
    ( nurl_print `single_row_n=` ) ( print_col t9 0 )
    ( csv_table_free t9 )

    // ── 13. round-trip: sort asc → desc → asc preserves row identity ──
    : *CSVTable t10 ( load_table `n,name\n3,c\n1,a\n2,b\n5,e\n4,d\n` )
    ( csv_table_sort_by_int t10 0 T )
    ( csv_table_sort_by_int t10 0 F )
    ( csv_table_sort_by_int t10 0 T )
    ( nurl_print `round_trip_n=` ) ( print_col t10 0 )
    ( nurl_print `round_trip_name=` ) ( print_col t10 1 )
    ( csv_table_free t10 )

    ( nurl_print `done\n` )
    ^ 0
}
