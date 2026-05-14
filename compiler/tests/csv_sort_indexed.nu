// csv_sort_indexed.nu — coverage of the indexed CSVTable sort path
// (csv_table_sort_by_int / _by_float / _by_string).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/csv.nu`

@ load_table s csv → *CSVTable {
    : String text ( string_from csv )
    : *CSVTable t ( csv_table_from_string text )
    ( string_free text )
    ^ t
}

@ print_col * CSVTable t i col → v {
    : i n ( csv_table_n_rows t )
    : ~ i i 0
    ~ < i n {
        : ?String s_opt ( csv_table_get t i col )
        ?? s_opt {
            T s → { ( nurl_print ( string_data s ) ) ( nurl_print ` ` ) }
            F → { ( nurl_print `? ` ) }
        }
        = i + i 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    // ── 1. ascending int sort with mixed positives/negatives ──────────
    : *CSVTable t1 ( load_table `n,name\n7,a\n-3,b\n0,c\n42,d\n-1,e\n` )
    ( csv_table_sort_by_int t1 0 T )
    ( nurl_print `int_asc: ` ) ( print_col t1 0 )
    ( nurl_print `int_asc_names: ` ) ( print_col t1 1 )

    // ── 2. descending int sort ────────────────────────────────────────
    ( csv_table_sort_by_int t1 0 F )
    ( nurl_print `int_desc: ` ) ( print_col t1 0 )
    ( csv_table_free t1 )

    // ── 3. all-equal keys preserve relative input order ───────────────
    : *CSVTable t2 ( load_table `k,id\n5,a\n5,b\n5,c\n5,d\n` )
    ( csv_table_sort_by_int t2 0 T )
    ( nurl_print `equal_keys_id: ` ) ( print_col t2 1 )
    ( csv_table_free t2 )

    // ── 4. unparseable cells coerce to 0 ──────────────────────────────
    : *CSVTable t3 ( load_table `n,tag\n3,x\nabc,y\n-1,z\n` )
    ( csv_table_sort_by_int t3 0 T )
    ( nurl_print `unparseable_asc: ` ) ( print_col t3 0 )
    ( nurl_print `unparseable_tag: ` ) ( print_col t3 1 )
    ( csv_table_free t3 )

    // ── 5. float ascending — NaN-free, mixed sign ─────────────────────
    : *CSVTable t4 ( load_table `f,name\n3.14,pi\n-2.5,n25\n0.0,zero\n10.5,big\n` )
    ( csv_table_sort_by_float t4 0 T )
    ( nurl_print `float_asc_names: ` ) ( print_col t4 1 )
    ( csv_table_free t4 )

    // ── 6. float descending ───────────────────────────────────────────
    : *CSVTable t5 ( load_table `f,name\n3.14,pi\n-2.5,n25\n0.0,zero\n10.5,big\n` )
    ( csv_table_sort_by_float t5 0 F )
    ( nurl_print `float_desc_names: ` ) ( print_col t5 1 )
    ( csv_table_free t5 )

    // ── 7. string ascending ───────────────────────────────────────────
    : *CSVTable t6 ( load_table `name,id\ndelta,1\nalpha,2\ncharlie,3\nbravo,4\n` )
    ( csv_table_sort_by_string t6 0 T )
    ( nurl_print `str_asc_id: ` ) ( print_col t6 1 )
    ( csv_table_free t6 )

    // ── 8. string descending ──────────────────────────────────────────
    : *CSVTable t7 ( load_table `name,id\ndelta,1\nalpha,2\ncharlie,3\nbravo,4\n` )
    ( csv_table_sort_by_string t7 0 F )
    ( nurl_print `str_desc_id: ` ) ( print_col t7 1 )
    ( csv_table_free t7 )

    // ── 9. single-row table is a no-op ────────────────────────────────
    : *CSVTable t8 ( load_table `n,name\n42,solo\n` )
    ( csv_table_sort_by_int t8 0 T )
    ( nurl_print `single_row_n: ` ) ( print_col t8 0 )
    ( csv_table_free t8 )

    // ── 10. round-trip stability check (sort asc → desc → asc) ────────
    : *CSVTable t9 ( load_table `n,name\n3,c\n1,a\n2,b\n5,e\n4,d\n` )
    ( csv_table_sort_by_int t9 0 T )
    ( csv_table_sort_by_int t9 0 F )
    ( csv_table_sort_by_int t9 0 T )
    ( nurl_print `round_trip_n: ` ) ( print_col t9 0 )
    ( nurl_print `round_trip_names: ` ) ( print_col t9 1 )
    ( csv_table_free t9 )

    ( nurl_print `done\n` )
    ^ 0
}
