$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : i t0 ( monotonic_ns )

    ( nurl_print `Loading test_data.csv...\n` )
    : *CSVTable tbl ( csv_table_load `test_data.csv` )
    ? == # i tbl 0 {
        ( nurl_print `ERROR: failed to load test_data.csv\n` )
        ^ 1
    } {}

    ( nurl_print `Loaded in ` )
    ( nurl_print ( nurl_str_int ( elapsed_ms_since t0 ) ) )
    ( nurl_print `ms\n` )

    ( nurl_print `Rows: ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows tbl ) ) )
    ( nurl_print `   Cols: ` ) ( nurl_print ( nurl_str_int ( csv_table_n_cols tbl ) ) )
    ( nurl_print `\n` )

    : ?i date_col ( csv_table_col_index tbl `date` )
    ?? date_col {
        T col → {
            ( nurl_print `'date' column index: ` )
            ( nurl_print ( nurl_str_int col ) ) ( nurl_print `\n` )
        }
        F → { ( nurl_print `'date' column not found\n` ) }
    }

    : ?String first_date ( csv_table_get_by_name tbl 0 `date` )
    ?? first_date {
        T s → {
            ( nurl_print `Row 0 date = ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
        }
        F → {}
    }

    ( nurl_print `\nFinding first row with text_words = 'juliet golf india'...\n` )
    : ?i tw_col ( csv_table_col_index tbl `text_words` )
    ?? tw_col {
        T col → {
            : i tf0 ( monotonic_ns )
            : ?i hit ( csv_table_find_first tbl col `juliet golf india` )
            : i el ( elapsed_ms_since tf0 )
            ?? hit {
                T idx → {
                    ( nurl_print `Found at row ` )
                    ( nurl_print ( nurl_str_int idx ) )
                    ( nurl_print ` in ` ) ( nurl_print ( nurl_str_int el ) ) ( nurl_print `ms\n` )
                }
                F → { ( nurl_print `Not found.\n` ) }
            }

            : i tf1 ( monotonic_ns )
            : ( Vec i ) all ( csv_table_find_all tbl col `juliet golf india` )
            : i el2 ( elapsed_ms_since tf1 )
            ( nurl_print `Total rows matching: ` )
            ( nurl_print ( nurl_str_int ( vec_len [i] all ) ) )
            ( nurl_print ` (` ) ( nurl_print ( nurl_str_int el2 ) ) ( nurl_print `ms)\n` )
            ( vec_free [i] all )
        }
        F → {}
    }

    ( nurl_print `\nSorting by 'date' ascending...\n` )
    : i ts ( monotonic_ns )
    ?? date_col {
        T col → ( csv_table_sort_by tbl col T )
        F → {}
    }
    ( nurl_print `Sorted in ` ) ( nurl_print ( nurl_str_int ( elapsed_ms_since ts ) ) ) ( nurl_print `ms\n` )

    : ?String new_first ( csv_table_get_by_name tbl 0 `date` )
    ?? new_first {
        T s → { ( nurl_print `New row 0 date = ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) }
        F → {}
    }

    ( nurl_print `\nSelecting columns id,date,text_words...\n` )
    : ( Vec String ) cols ( vec_with_cap [String] 3 )
    ( vec_push [String] cols ( string_from `id` ) )
    ( vec_push [String] cols ( string_from `date` ) )
    ( vec_push [String] cols ( string_from `text_words` ) )
    : i tsel ( monotonic_ns )
    : *CSVTable proj ( csv_table_select_cols tbl cols )
    ( nurl_print `Selected ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows proj ) ) )
    ( nurl_print ` rows in ` ) ( nurl_print ( nurl_str_int ( elapsed_ms_since tsel ) ) ) ( nurl_print `ms\n` )

    ( nurl_print `Writing csv_demo_output.csv...\n` )
    : i tw ( monotonic_ns )
    : b ok ( csv_table_write proj `csv_demo_output.csv` ( csv_dialect_default ) )
    ? ok {
        ( nurl_print `Wrote in ` ) ( nurl_print ( nurl_str_int ( elapsed_ms_since tw ) ) ) ( nurl_print `ms\n` )
    } { ( nurl_print `Write failed.\n` ) }

    ( csv_table_free proj )
    : ( @ v String ) sd \ String s → v { ( string_free s ) }
    ( vec_free_with [String] cols sd )
    ( csv_table_free tbl )

    ( nurl_print `\nTotal time: ` ) ( nurl_print ( nurl_str_int ( elapsed_ms_since t0 ) ) ) ( nurl_print `ms\n` )
    ^ 0
}
