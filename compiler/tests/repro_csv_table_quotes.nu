$ `stdlib/ext/csv.nu`
$ `stdlib/core/string.nu`

@ main → v {
    : String content ( string_from `name,note\n"alice","hello\nworld"\n"bob","hi"\n` )
    : *CSVTable t ( csv_table_from_string content )

    ( nurl_print `Headers: ` )
    : ( Vec String ) hs . t headers
    : i nh ( vec_len [String] hs )
    : ~ i i 0
    ~ < i nh {
        : ?String s_opt ( vec_get [String] hs i )
        ?? s_opt { T s → { ( nurl_print `[` ) ( nurl_print ( string_data s ) ) ( nurl_print `] ` ) } F → {} }
        = i + i 1
    }
    ( nurl_print `\n` )

    ( nurl_print `Rows: ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t ) ) ) ( nurl_print `\n` )

    : i nr ( csv_table_n_rows t )
    = i 0
    ~ < i nr {
        ( nurl_print `Row ` ) ( nurl_print ( nurl_str_int + i 1 ) ) ( nurl_print `: ` )
        : i nc ( csv_table_n_cells_in_row t i )
        : ~ i j 0
        ~ < j nc {
            : ?String s_opt ( csv_table_get t i j )
            ?? s_opt {
                T s → {
                    ( nurl_print `[` ) ( nurl_print ( string_data s ) ) ( nurl_print `] ` )
                    ( string_free s )
                }
                F → {}
            }
            = j + j 1
        }
        ( nurl_print `\n` )
        = i + i 1
    }

    ( csv_table_free t )
}
