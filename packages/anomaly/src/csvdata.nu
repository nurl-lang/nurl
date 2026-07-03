// anomaly/csvdata.nu — numeric CSV → row-major matrix (batch inputs).
//
// Same forgiving shape as the `iforest` CLI parser: split lines, split on
// the delimiter, keep numeric fields; the first data row fixes the column
// count, later rows with a different numeric-field count are skipped. With
// `has_header`, the first line's names are captured (for batch reports
// that echo column values by name) instead of being parsed as data.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

// Parsed matrix: `data` is row-major rows*cols; `headers` is empty when
// the input had no header row.
: AnomCsv {
    ( Vec f ) data
    i rows
    i cols
    ( Vec String ) headers
}

@ anom_csv_free AnomCsv ds → v {
    ( vec_free [f] . ds data )
    ( vec_free_with [String] . ds headers \ String x → v { ( string_free x ) } )
}

@ anom_parse_csv s input s delim b has_header → AnomCsv {
    : String text ( string_from input )
    : ( Vec String ) lines ( string_split text `\n` )
    ( string_free text )

    : ( Vec f ) data ( vec_new [f] )
    : ( Vec String ) headers ( vec_new [String] )
    : ~ i cols -1
    : ~ i rows 0
    : i nl ( vec_len [String] lines )
    : ~ i li 0
    ~ < li nl {
        ?? ( vec_get [String] lines li ) {
            T line → {
                : String tl ( string_trim line )
                ? > ( string_len tl ) 0 {
                    ? & == li 0 has_header {
                        : ( Vec String ) hfields ( string_split tl delim )
                        : i nh ( vec_len [String] hfields )
                        : ~ i hi 0
                        ~ < hi nh {
                            ?? ( vec_get [String] hfields hi ) {
                                T h → { ( vec_push [String] headers ( string_trim h ) ) }
                                F _ → {}
                            }
                            = hi + hi 1
                        }
                        ( vec_free_with [String] hfields \ String x → v { ( string_free x ) } )
                    } {
                        : ( Vec String ) fields ( string_split tl delim )
                        : ( Vec f ) rowvals ( vec_new [f] )
                        : i nf ( vec_len [String] fields )
                        : ~ i fi 0
                        ~ < fi nf {
                            ?? ( vec_get [String] fields fi ) {
                                T fld → {
                                    : String ft ( string_trim fld )
                                    ?? ( string_to_float ft ) {
                                        T x → { ( vec_push [f] rowvals x ) }
                                        F _ → {}
                                    }
                                    ( string_free ft )
                                }
                                F _ → {}
                            }
                            = fi + fi 1
                        }
                        ( vec_free_with [String] fields \ String x → v { ( string_free x ) } )

                        : i nv ( vec_len [f] rowvals )
                        ? > nv 0 {
                            ? < cols 0 { = cols nv } {}
                            ? == nv cols {
                                ( vec_extend [f] data rowvals )
                                = rows + rows 1
                            } {}
                        } {}
                        ( vec_free [f] rowvals )
                    }
                } {}
                ( string_free tl )
            }
            F _ → {}
        }
        = li + li 1
    }
    ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
    ? < cols 0 { = cols 0 } {}
    ^ @ AnomCsv { data rows cols headers }
}
