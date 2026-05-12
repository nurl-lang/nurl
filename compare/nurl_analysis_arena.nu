// nurl_analysis_arena.nu — same pipeline as nurl_analysis.nu but built
// on `CSVTableA` (arena loader). Output format is byte-identical so
// run_bench.sh can score arena vs Polars without changes.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : i t0 ( monotonic_ns )

    : *CSVTableA df ( csv_table_a_load `test_data.csv` )
    ? == # i df 0 {
        ( nurl_print `ERROR: failed to load test_data.csv\n` )
        ^ 1
    } {}
    : i t_load ( monotonic_ns )
    ( nurl_print `Loaded ` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_rows df ) ) )
    ( nurl_print ` rows x ` ) ( nurl_print ( nurl_str_int ( csv_table_a_n_cols df ) ) )
    ( nurl_print ` cols in ` )
    ( nurl_print ( nurl_str_int / - t_load t0 1000000 ) ) ( nurl_print `ms\n` )

    : ? i col_vf2_o ( csv_table_a_col_index df `val_float2` )
    : ? i col_tw_o ( csv_table_a_col_index df `text_words` )
    : ? i col_vi_o ( csv_table_a_col_index df `val_int` )
    : i col_vf2 ( opt_unwrap_or [i] col_vf2_o -1 )
    : i col_tw ( opt_unwrap_or [i] col_tw_o -1 )
    : i col_vi ( opt_unwrap_or [i] col_vi_o -1 )

    // Filter: val_float2 > 0  AND  text_words contains "juliet".
    // Prefetch the arena's data pointers ONCE at closure-creation time
    // so the hot per-row predicate skips csv_table_a_view's 3 internal
    // vec_data FFI calls per access (4 accesses × 3 = 12 M FFI saved
    // across 1 M rows).  Pointers stay valid for the duration of the
    // filter call: csv_table_a_filter reads row_starts/row_lens
    // through its own prefetched pointers and never grows the vecs.
    : *i fcp_cap ( vec_data [i] . df flat_cells )
    : *i rsp_cap ( vec_data [i] . df row_starts )
    : *i rlp_cap ( vec_data [i] . df row_lens )
    : *u cd_cap # *u ( string_data . df content )

    ( csv_table_a_filter df \ *CSVTableA tt i row → b {
        : i row_first . rsp_cap row
        : i row_count . rlp_cap row

        // val_float2 cell
        ? < col_vf2 0 { ^ F } {}
        ? >= col_vf2 row_count { ^ F } {}
        : i cell_idx_vf2 + row_first col_vf2
        : i off_vf2 . fcp_cap * cell_idx_vf2 2
        : i len_vf2 . fcp_cap + * cell_idx_vf2 2 1
        ? == len_vf2 0 { ^ F } {}
        : *u p_vf2 # *u + # i cd_cap off_vf2
        : f f2 ( nurl_parse_float_range # s p_vf2 len_vf2 )
        ? <= f2 0.0 { ^ F } {}

        // text_words cell
        ? < col_tw 0 { ^ F } {}
        ? >= col_tw row_count { ^ F } {}
        : i cell_idx_tw + row_first col_tw
        : i off_tw . fcp_cap * cell_idx_tw 2
        : i len_tw . fcp_cap + * cell_idx_tw 2 1
        ? == len_tw 0 { ^ F } {}
        : *u p_tw # *u + # i cd_cap off_tw
        ^ >= ( nurl_memmem_range # s p_tw len_tw `juliet` 6 ) 0
    } )
    : i t_filter ( monotonic_ns )
    ( nurl_print `Filtered to ` )
    ( nurl_print ( nurl_str_int ( csv_table_a_n_rows df ) ) )
    ( nurl_print ` rows in ` )
    ( nurl_print ( nurl_str_int / - t_filter t_load 1000000 ) ) ( nurl_print `ms\n` )

    ( csv_table_a_sort_by_int df col_vi F )
    : i t_sort ( monotonic_ns )
    ( nurl_print `Sorted (val_int desc) in ` )
    ( nurl_print ( nurl_str_int / - t_sort t_filter 1000000 ) ) ( nurl_print `ms\n` )

    ( csv_table_a_truncate df 10 )
    : b ok ( csv_table_a_write df `nurl_top10.csv` ( csv_dialect_default ) )
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

    : i nr ( csv_table_a_n_rows df )
    : ~ i ri 0
    ~ < ri nr {
        : i row_count ( csv_table_a_n_cells_in_row df ri )
        : ~ i j 0
        ~ < j row_count {
            : ? String s_opt ( csv_table_a_get_string df ri j )
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

    ( csv_table_a_free df )
    ^ 0
}
