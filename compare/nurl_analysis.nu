// nurl_analysis.nu — load → filter → sort → top-10 → write pipeline
// over `compare/test_data.csv`. Output format is shared with
// `compare/polars_analysis.py` so `zig build bench-csv` can diff timings.
//
// Hot predicate uses cached `vec_data` pointers captured into the
// closure: each csv_table_view call would otherwise pay three FFI
// hops per cell (rsp / rlp / fcp). On a 1 M-row table that is the
// difference between ~150 ms and ~300 ms of filter time.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : i t0 ( monotonic_ns )

    : *CSVTable df ( csv_table_load `test_data.csv` )
    ? == # i df 0 {
        ( nurl_print `ERROR: failed to load test_data.csv\n` )
        ^ 1
    } {}
    : i t_load ( monotonic_ns )
    ( nurl_print `Loaded ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows df ) ) )
    ( nurl_print ` rows x ` ) ( nurl_print ( nurl_str_int ( csv_table_n_cols df ) ) )
    ( nurl_print ` cols in ` )
    ( nurl_print ( nurl_str_int / - t_load t0 1000000 ) ) ( nurl_print `ms\n` )

    : ? i col_vf2_o ( csv_table_col_index df `val_float2` )
    : ? i col_tw_o ( csv_table_col_index df `text_words` )
    : ? i col_vi_o ( csv_table_col_index df `val_int` )
    : i col_vf2 ( opt_unwrap_or [i] col_vf2_o -1 )
    : i col_tw ( opt_unwrap_or [i] col_tw_o -1 )
    : i col_vi ( opt_unwrap_or [i] col_vi_o -1 )

    // Filter: val_float2 > 0  AND  text_words contains "juliet".
    //
    // Combined-predicate helper does both checks in a single C call
    // with row-level short-circuit (float check first; ~85 % of
    // rows skip the substring scan). For one-shot filter use this
    // beats the P3b pre-parse path because no inline parse is
    // added to load — see `csv_table_load_typed_f` for the
    // pre-parse alternative when the float column is consumed
    // multiple times (aggregations, multi-pass filters).
    ( csv_table_filter_float_gt_and_str_contains df col_vf2 0.0 col_tw `juliet` )
    : i t_filter ( monotonic_ns )
    ( nurl_print `Filtered to ` )
    ( nurl_print ( nurl_str_int ( csv_table_n_rows df ) ) )
    ( nurl_print ` rows in ` )
    ( nurl_print ( nurl_str_int / - t_filter t_load 1000000 ) ) ( nurl_print `ms\n` )

    ( csv_table_sort_by_int df col_vi F )
    : i t_sort ( monotonic_ns )
    ( nurl_print `Sorted (val_int desc) in ` )
    ( nurl_print ( nurl_str_int / - t_sort t_filter 1000000 ) ) ( nurl_print `ms\n` )

    ( csv_table_truncate df 10 )
    : b ok ( csv_table_write df `nurl_top10.csv` ( csv_dialect_default ) )
    : i t_write ( monotonic_ns )
    ? ok {
        ( nurl_print `Top-10 written to nurl_top10.csv in ` )
        ( nurl_print ( nurl_str_int / - t_write t_sort 1000000 ) ) ( nurl_print `ms\n` )
    } { ( nurl_print `Write failed.\n` ) }

    ( nurl_print `\nTotal: ` )
    ( nurl_print ( nurl_str_int / - t_write t0 1000000 ) ) ( nurl_print `ms\n\n` )

    // Pretty-print top-10
    : ( Vec String ) hdrs . df headers
    : i nh ( vec_len [String] hdrs )
    : *String hp ( vec_data [String] hdrs )
    : ~ i ci 0
    ~ < ci nh {
        : String h . hp ci
        ( nurl_print ( string_data h ) )
        ? < ci - nh 1 { ( nurl_print `,` ) } {}
        = ci + ci 1
    }
    ( nurl_print `\n` )

    : i nr ( csv_table_n_rows df )
    : ~ i ri 0
    ~ < ri nr {
        : i row_count ( csv_table_n_cells_in_row df ri )
        : ~ i j 0
        ~ < j row_count {
            : ? String s_opt ( csv_table_get df ri j )
            ?? s_opt {
                T s → { ( nurl_print ( string_data s ) ) ( string_free s ) }
                F → {}
            }
            ? < j - row_count 1 { ( nurl_print `,` ) } {}
            = j + j 1
        }
        ( nurl_print `\n` )
        = ri + ri 1
    }

    ( csv_table_free df )
    ^ 0
}
