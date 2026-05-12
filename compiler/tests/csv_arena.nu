// csv_arena.nu — coverage of the CSVTableA arena loader and its
// sort/filter/truncate/write surface. The arena layout (one content
// blob + flat (off,len) cells + parallel row_starts / row_lens) has
// different invariants from CSVTable v1, so we exercise:
//   - basic load → n_rows / n_cols / view / view_len / get_string
//   - col_index lookup
//   - filter (closure-based; (row_starts, row_lens) shrink only)
//   - sort_by_int / _by_float / _by_string (permutation on the
//     parallel vecs, flat_cells untouched)
//   - truncate (in-place row count clamp)
//   - to_table (deep-copy promotion to v1)
//
// All tests print compact tags so correct.txt diffs are obvious.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/csv.nu`

@ load_arena s csv → *CSVTableA {
    : String text ( string_from csv )
    : *CSVTableA t ( csv_table_a_from_string text )
    ^ t
}

@ print_col *CSVTableA t i col → v {
    : i n ( csv_table_a_n_rows t )
    : ~ i i 0
    ~ < i n {
        : ? String s_opt ( csv_table_a_get_string t i col )
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
    : *CSVTableA t1 ( load_arena `n,name,score\n7,a,1.5\n-3,b,2.5\n0,c,3.5\n` )
    ( nurl_print `n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_rows t1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `n_cols=` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_cols t1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `col_n=` )    ( print_col t1 0 )
    ( nurl_print `col_name=` ) ( print_col t1 1 )

    // ── 2. col_index lookup ───────────────────────────────────────────
    : ? i ci_o ( csv_table_a_col_index t1 `name` )
    ?? ci_o { T ix → { ( nurl_print `idx_name=` ) ( nurl_print ( nurl_str_int ix ) ) ( nurl_print `\n` ) } F → {} }
    : ? i miss_o ( csv_table_a_col_index t1 `nope` )
    ?? miss_o { T _ → { ( nurl_print `idx_nope=hit\n` ) } F → { ( nurl_print `idx_nope=miss\n` ) } }

    // ── 3. view / view_len: borrowed bytes (NOT NUL-terminated) ───────
    : i vl ( csv_table_a_view_len t1 1 1 )
    ( nurl_print `view_len_(1,1)=` ) ( nurl_print ( nurl_str_int vl ) ) ( nurl_print `\n` )
    : ? String gs ( csv_table_a_get_string t1 1 1 )
    ?? gs { T s → { ( nurl_print `get(1,1)=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } F → {} }
    ( csv_table_a_free t1 )

    // ── 4. sort_by_int asc on a 5-row table ───────────────────────────
    : *CSVTableA t2 ( load_arena `n,tag\n7,a\n-3,b\n0,c\n42,d\n-1,e\n` )
    ( csv_table_a_sort_by_int t2 0 T )
    ( nurl_print `int_asc_n=` )    ( print_col t2 0 )
    ( nurl_print `int_asc_tag=` )  ( print_col t2 1 )

    // ── 5. sort_by_int desc on the same table ─────────────────────────
    ( csv_table_a_sort_by_int t2 0 F )
    ( nurl_print `int_desc_n=` ) ( print_col t2 0 )
    ( csv_table_a_free t2 )

    // ── 6. unparseable cells coerce to 0 ──────────────────────────────
    : *CSVTableA t3 ( load_arena `n,tag\n3,x\nabc,y\n-1,z\n` )
    ( csv_table_a_sort_by_int t3 0 T )
    ( nurl_print `unparse_n=` ) ( print_col t3 0 )
    ( nurl_print `unparse_tag=` ) ( print_col t3 1 )
    ( csv_table_a_free t3 )

    // ── 7. sort_by_float asc/desc, mixed signs ────────────────────────
    : *CSVTableA t4 ( load_arena `f,name\n3.14,pi\n-2.5,n25\n0.0,zero\n10.5,big\n` )
    ( csv_table_a_sort_by_float t4 0 T )
    ( nurl_print `float_asc_name=` ) ( print_col t4 1 )
    ( csv_table_a_sort_by_float t4 0 F )
    ( nurl_print `float_desc_name=` ) ( print_col t4 1 )
    ( csv_table_a_free t4 )

    // ── 8. sort_by_string asc/desc ────────────────────────────────────
    : *CSVTableA t5 ( load_arena `name,id\ndelta,1\nalpha,2\ncharlie,3\nbravo,4\n` )
    ( csv_table_a_sort_by_string t5 0 T )
    ( nurl_print `str_asc_id=` )  ( print_col t5 1 )
    ( csv_table_a_sort_by_string t5 0 F )
    ( nurl_print `str_desc_id=` ) ( print_col t5 1 )
    ( csv_table_a_free t5 )

    // ── 9. filter: keep rows where col 0 (int) > 0 ────────────────────
    : *CSVTableA t6 ( load_arena `n,tag\n5,a\n-1,b\n0,c\n7,d\n-3,e\n2,f\n` )
    ( csv_table_a_filter t6 \ *CSVTableA tt i row → b {
        : s sv ( csv_table_a_view tt row 0 )
        : i sl ( csv_table_a_view_len tt row 0 )
        : i n  ( nurl_parse_int_range sv sl )
        ^ > n 0
    } )
    ( nurl_print `filter_n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_rows t6 ) ) ) ( nurl_print `\n` )
    ( nurl_print `filter_tag=` ) ( print_col t6 1 )
    ( csv_table_a_free t6 )

    // ── 10. truncate (clamp + no-op when n exceeds row count) ─────────
    : *CSVTableA t7 ( load_arena `n,tag\n1,a\n2,b\n3,c\n4,d\n5,e\n` )
    ( csv_table_a_truncate t7 3 )
    ( nurl_print `trunc3_n=` ) ( print_col t7 0 )
    ( csv_table_a_truncate t7 99 )    // no-op: keep > current
    ( nurl_print `trunc_keep_n=` ) ( print_col t7 0 )
    ( csv_table_a_truncate t7 0 )
    ( nurl_print `trunc0_n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_rows t7 ) ) ) ( nurl_print `\n` )
    ( csv_table_a_free t7 )

    // ── 11. to_table: arena → v1 deep-copy promotion ──────────────────
    : *CSVTableA t8 ( load_arena `k,v\n10,foo\n20,bar\n` )
    : *CSVTable v1 ( csv_table_a_to_table t8 )
    ( nurl_print `to_table_n_rows=` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows v1 ) ) ) ( nurl_print `\n` )
    : ? String c00 ( csv_table_get v1 0 0 )
    ?? c00 { T s → { ( nurl_print `to_table_(0,0)=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) } F → {} }
    ( csv_table_free v1 )
    ( csv_table_a_free t8 )

    // ── 12. round-trip: sort asc → desc → asc preserves row identity ──
    : *CSVTableA t9 ( load_arena `n,name\n3,c\n1,a\n2,b\n5,e\n4,d\n` )
    ( csv_table_a_sort_by_int t9 0 T )
    ( csv_table_a_sort_by_int t9 0 F )
    ( csv_table_a_sort_by_int t9 0 T )
    ( nurl_print `round_trip_n=` ) ( print_col t9 0 )
    ( nurl_print `round_trip_name=` ) ( print_col t9 1 )
    ( csv_table_a_free t9 )

    ( nurl_print `done\n` )
    ^ 0
}
