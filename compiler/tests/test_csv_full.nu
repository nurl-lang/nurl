$ `stdlib/ext/csv.nu`
$ `stdlib/core/string.nu`

@ main → v {
    // 1. Test csv_parse with quotes and newlines
    : String input ( string_from `name,city,note\n"alice","new york","hello\nworld"\n"bob","la","""quote"" test"\n` )
    : !( Vec ( Vec String ) ) ParseErr res ( csv_parse input )

    ?? res {
        T rows → {
            ( nurl_print `Parsed rows: ` ) ( nurl_print ( nurl_str_int ( vec_len [( Vec String )] rows ) ) ) ( nurl_print `\n` )

            // 2. Test csv_write round-trip
            : String output ( csv_write rows )
            ( nurl_print `Round-trip output:\n` )
            ( nurl_print ( string_data output ) )

            // Cleanup rows
            : i nr ( vec_len [( Vec String )] rows )
            : ~ i i 0
            ~ < i nr {
                : ?( Vec String ) row_opt ( vec_get [( Vec String )] rows i )
                ?? row_opt { T row → ( _csv_row_free row ) F → {} }
                = i + i 1
            }
            ( vec_free [( Vec String )] rows )
            ( string_free output )
        }
        F e → { ( nurl_print `Parse failed!\n` ) }
    }

    ( string_free input )
}
