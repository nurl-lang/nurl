$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
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
    ( nurl_print ( nurl_str_int ( elapsed_ms_since t0 ) ) ) ( nurl_print `ms\n` )

    : ? i col_vf2_o ( csv_table_col_index df `val_float2` )
    : ? i col_tw_o ( csv_table_col_index df `text_words` )
    : ? i col_vi_o ( csv_table_col_index df `val_int` )

    : i col_vf2 ( opt_unwrap_or [i] col_vf2_o -1 )
    : i col_tw ( opt_unwrap_or [i] col_tw_o -1 )
    : i col_vi ( opt_unwrap_or [i] col_vi_o -1 )

    // Filter: val_float2 > 0  AND  text_words contains "juliet"
    : *CSVTable filtered ( csv_table_filter df
        \ CSVRow r → b {
            : ( Vec String ) cells . r cells
            : ? String vf2_opt ( vec_get [String] cells col_vf2 )
            : ? String tw_opt ( vec_get [String] cells col_tw )
            : ~ b ok F
            ?? vf2_opt {
                T vfs → {
                    : ? f pf ( string_to_float vfs )
                    ?? pf {
                        T vff → {
                            ? > vff 0.0 {
                                ?? tw_opt {
                                    T tws → {
                                        ? ( string_contains tws `juliet` ) { = ok T } {}
                                    }
                                    F → {}
                                }
                            } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ^ ok
        }
    )
    : i t_filter ( monotonic_ns )
    ( nurl_print `Filtered to ` )
    ( nurl_print ( nurl_str_int ( csv_table_n_rows filtered ) ) )
    ( nurl_print ` rows in ` )
    ( nurl_print ( nurl_str_int ( elapsed_ms_since t_load ) ) ) ( nurl_print `ms\n` )

    // Sort by val_int desc (numeric)
    ( csv_table_sort_by_int filtered col_vi F )
    : i t_sort ( monotonic_ns )
    ( nurl_print `Sorted (val_int desc) in ` )
    ( nurl_print ( nurl_str_int ( elapsed_ms_since t_filter ) ) ) ( nurl_print `ms\n` )

    // Take top-10
    : *CSVTable top10 ( csv_table_head filtered 10 )
    : b ok ( csv_table_write top10 `nurl_top10.csv` ( csv_dialect_default ) )
    : i t_write ( monotonic_ns )
    ? ok {
        ( nurl_print `Top-10 written to nurl_top10.csv in ` )
        ( nurl_print ( nurl_str_int ( elapsed_ms_since t_sort ) ) ) ( nurl_print `ms\n` )
    } { ( nurl_print `Write failed.\n` ) }

    ( nurl_print `\nTotal: ` )
    ( nurl_print ( nurl_str_int ( elapsed_ms_since t0 ) ) ) ( nurl_print `ms\n\n` )

    // Pretty-print top-10 (header + rows)
    : ( Vec String ) hdrs . top10 headers
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
    : i nr ( csv_table_n_rows top10 )
    : *CSVRow rp ( vec_data [CSVRow] . top10 rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        : ( Vec String ) cs . r cells
        : i nc ( vec_len [String] cs )
        : *String cp ( vec_data [String] cs )
        : ~ i j 0
        ~ < j nc {
            : String c . cp j
            ( nurl_print ( string_data c ) )
            ? < j - nc 1 { ( nurl_print `,` ) } {}
            = j + j 1
        }
        ( nurl_print `\n` )
        = i + i 1
    }

    ( csv_table_free top10 )
    ( csv_table_free filtered )
    ( csv_table_free df )
    ^ 0
}
