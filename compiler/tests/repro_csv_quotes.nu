$ `stdlib/ext/csv.nu`
$ `stdlib/core/string.nu`

@ main → v {
    : String content ( string_from `name,note\n"alice","hello\nworld"\n"bob","hi"\n` )
    : *CSVReader r ( csv_reader_new content )

    : ~ i count 0
    : ~ b done F
    ~ ! done {
        : ?( Vec String ) row_opt ( csv_reader_next r )
        ?? row_opt {
            T row → {
                = count + count 1
                ( nurl_print `Row ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print `: ` )
                : i n ( vec_len [String] row )
                : ~ i i 0
                ~ < i n {
                    : ?String s_opt ( vec_get [String] row i )
                    ?? s_opt { T s → { ( nurl_print `[` ) ( nurl_print ( string_data s ) ) ( nurl_print `] ` ) } F → {} }
                    = i + i 1
                }
                ( nurl_print `\n` )
                ( _csv_row_free row )
            }
            F → { = done T }
        }
    }

    ( nurl_print `Total rows: ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print `\n` )
    ( string_free content )
}
