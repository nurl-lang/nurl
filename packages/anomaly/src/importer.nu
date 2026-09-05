// anomaly/importer.nu — a file of history becomes a stream of points.
//
// The service is built around one point at a time arriving from a producer.
// Importing is the other direction: a file that already holds the history,
// turned into the same records the ingest path takes, so nothing downstream
// has to know where a point came from.
//
// Three shapes, because these are the three a data file actually arrives in:
//
//   csv    a header row naming the columns, one row per point. Cells that
//          parse as numbers become numbers; everything else stays a string,
//          which the preprocessing layer already knows what to do with
//          (categories, ISO-8601 timestamps → calendar features).
//   json   an array of objects, or an object with the array under `data`,
//          `points` or `rows` — the three spellings an export tool picks.
//   jsonl  one object per line. What this service's own /data route emits,
//          so a model can be moved by exporting and importing it.
//
// `auto` sniffs: a body whose first non-space character is `[` or `{` is
// JSON or JSONL, anything else is CSV. Detection is offered because a
// browser upload rarely knows its own format, and is never mandatory —
// naming the format explicitly always wins.
//
// A row that cannot be read does not stop the import: it is counted and the
// first few are described. A file of ten thousand rows with one bad line is
// a file with one bad line, not a failed import.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `src/imptime.nu`

// A file bigger than this is refused before it is parsed. Generous enough
// for years of minute-resolution history, small enough that a mistaken
// upload cannot exhaust memory.
: i ANOM_IMPORT_MAX_BYTES 67108864
: i ANOM_IMPORT_MAX_ROWS 1000000

// How many bad rows are described rather than merely counted.
: i ANOM_IMPORT_MAX_NOTES 5

: ImportParse {
    ( Vec Json ) rows
    i skipped
    ( Vec String ) notes  // why the first few were skipped
    String err  // non-empty ⇒ nothing was read at all
    String format  // what it turned out to be
}

@ import_parse_free ImportParse ip → v {
    ( vec_free_with [Json] . ip rows \ Json j → v { ( json_free j ) } )
    ( vec_free_with [String] . ip notes \ String s → v { ( string_free s ) } )
    ( string_free . ip err )
    ( string_free . ip format )
}

@ __imp_fail s why → ImportParse {
    ^ @ ImportParse {
        ( vec_new [Json] ) 0 ( vec_new [String] ) ( string_from why ) ( string_new )
    }
}

// Trim a raw string into an owned one. `string_trim` does not consume its
// argument, so composing it with `string_from` leaks the temporary — which
// it did, in five places, until an ASan run said so.
@ __imp_trimmed s raw → String {
    : String tmp ( string_from raw )
    : String out ( string_trim tmp )
    ( string_free tmp )
    ^ out
}

@ __imp_note ( Vec String ) notes i line s why → v {
    ? < ( vec_len [String] notes ) ANOM_IMPORT_MAX_NOTES {} { ^ }
    : String m ( string_from `line ` )
    ( string_push_int m line )
    ( string_push_str m `: ` )
    ( string_push_str m why )
    ( vec_push [String] notes m )
}

// ── Detection ─────────────────────────────────────────────────────────

@ __imp_first_glyph s text → i {
    : i n ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at text n k )
        ? | | | == c 32 == c 9 == c 13 == c 10 { = k + k 1 } { ^ c }
    }
    ^ 0
}

// Which of the three this body is. `[` starts a JSON array; `{` starts
// either a lone object or the first line of JSONL, and which one is
// settled by whether a later line also starts an object.
@ import_sniff s text → String {
    : i c ( __imp_first_glyph text )
    ? == c 91 { ^ ( string_from `json` ) } {}
    ? == c 123 {
        : String t ( string_from text )
        : ( Vec String ) ls ( string_split t `\n` )
        ( string_free t )
        : i n ( vec_len [String] ls )
        : ~ i objs 0
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [String] ls k ) {
                T l → { ? == ( __imp_first_glyph ( string_data l ) ) 123 { = objs + objs 1 } {} }
                F _ → {}
            }
            = k + k 1
        }
        ( vec_free_with [String] ls \ String x → v { ( string_free x ) } )
        ? > objs 1 { ^ ( string_from `jsonl` ) } {}
        ^ ( string_from `json` )
    } {}
    ^ ( string_from `csv` )
}

// ── CSV ───────────────────────────────────────────────────────────────

// The delimiter, from whichever of comma, semicolon and tab the header row
// holds most of. Guessing beats asking: an export from a Finnish locale is
// semicolon-separated and its author has no reason to know that.
@ __imp_delim s header → i {
    : i n ( nurl_str_len header )
    : ~ i comma 0
    : ~ i semi 0
    : ~ i tab 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at header n k )
        ? == c 44 { = comma + comma 1 } {}
        ? == c 59 { = semi + semi 1 } {}
        ? == c 9 { = tab + tab 1 } {}
        = k + k 1
    }
    ? & >= semi comma >= semi tab { ? > semi 0 { ^ 59 } {} } {}
    ? & >= tab comma > tab 0 { ^ 9 } {}
    ^ 44
}

// Split one CSV line, honouring quoted fields: a delimiter inside quotes is
// data, and `""` inside a quoted field is one quote.
@ __imp_split_row s line i delim → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len line )
    : ~ String cur ( string_new )
    : ~ b quoted F
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at line n k )
        ? quoted {
            ? == c 34 {
                ? & < + k 1 n == ( nurl_str_at line n + k 1 ) 34 {
                    ( string_push_char cur 34 )
                    = k + k 2
                } { = quoted F = k + k 1 }
            } { ( string_push_char cur c ) = k + k 1 }
        } {
            ? == c 34 { = quoted T = k + k 1 } {
                ? == c delim {
                    ( vec_push [String] out cur )
                    = cur ( string_new )
                    = k + k 1
                } {
                    ? == c 13 { = k + k 1 } { ( string_push_char cur c ) = k + k 1 }
                }
            }
        }
    }
    ( vec_push [String] out cur )
    ^ out
}

// One cell as JSON. A number stays a number; everything else stays text,
// because the preprocessing layer is where a string becomes a category or
// an ISO-8601 stamp becomes calendar features — not here.
// The markers exporters write for "no value": a dash (the weather
// service), R's NA, a spreadsheet's #N/A, JSON's null, Python's None, a
// NaN. Each is the same as a blank cell — no field.
@ __imp_is_missing s t → b {
    ? == ( nurl_str_eq t `-` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `--` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `NA` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `N/A` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `n/a` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `#N/A` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `NaN` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `nan` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `null` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `NULL` ) 1 { ^ T } {}
    ? == ( nurl_str_eq t `None` ) 1 { ^ T } {}
    ^ F
}

@ __imp_cell s raw → ?Json {
    : String t ( __imp_trimmed raw )
    ? > ( string_len t ) 0 {} {
        // An empty cell contributes no field at all rather than an empty
        // category: a column that is blank in one row is missing there, and
        // the projection already means "missing" by leaving it out.
        ( string_free t )
        ^ @ ?Json { F }
    }
    ? ( __imp_is_missing ( string_data t ) ) {
        ( string_free t )
        ^ @ ?Json { F }
    } {}
    ?? ( string_to_int t ) {
        T n → {
            ( string_free t )
            ^ @ ?Json { T ( json_int n ) }
        }
        F _ → {}
    }
    ?? ( string_to_float t ) {
        T x → {
            ( string_free t )
            ^ @ ?Json { T ( json_float x ) }
        }
        F → {}
    }
    : Json j ( json_str_lit ( string_data t ) )
    ( string_free t )
    ^ @ ?Json { T j }
}

@ __imp_parse_csv s text → ImportParse {
    : String whole ( string_from text )
    : ( Vec String ) lines ( string_split whole `\n` )
    ( string_free whole )
    : i n ( vec_len [String] lines )
    ? > n 0 {} {
        ( vec_free [String] lines )
        ^ ( __imp_fail `the file is empty` )
    }

    // The header names the columns. Without it there is nothing to call the
    // values, and a model keyed on `col0` would be a model nobody can read.
    : ~ ( Vec String ) headers ( vec_new [String] )
    : ~ i start 0
    : ~ i delim 44
    : ~ b got_header F
    ~ & ! got_header < start n {
        ?? ( vec_get [String] lines start ) {
            T l → {
                : String t ( __imp_trimmed ( string_data l ) )
                ? > ( string_len t ) 0 {
                    = delim ( __imp_delim ( string_data l ) )
                    ( vec_free_with [String] headers \ String x → v { ( string_free x ) } )
                    = headers ( __imp_split_row ( string_data l ) delim )
                    = got_header T
                } {}
                ( string_free t )
            }
            F _ → {}
        }
        = start + start 1
    }
    ? got_header {} {
        ( vec_free [String] lines )
        ( vec_free [String] headers )
        ^ ( __imp_fail `the file has no header row` )
    }
    // Trim the names once: a header written with spaces after the commas
    // would otherwise produce fields nobody can address.
    : i hn ( vec_len [String] headers )
    : ~ i hk 0
    ~ < hk hn {
        ?? ( vec_get [String] headers hk ) {
            T h → {
                : String t ( __imp_trimmed ( string_data h ) )
                : b _s ( vec_set [String] headers hk t )
                ( string_free h )
            }
            F _ → {}
        }
        = hk + hk 1
    }

    : ( Vec Json ) rows ( vec_new [Json] )
    : ( Vec String ) notes ( vec_new [String] )
    : ~ i skipped 0
    : ~ i k start
    ~ < k n {
        ?? ( vec_get [String] lines k ) {
            T l → {
                : String t ( __imp_trimmed ( string_data l ) )
                : b blank == ( string_len t ) 0
                ( string_free t )
                ? blank {} {
                    ? >= ( vec_len [Json] rows ) ANOM_IMPORT_MAX_ROWS {} {
                        : ( Vec String ) cells ( __imp_split_row ( string_data l ) delim )
                        : i cn ( vec_len [String] cells )
                        ? != cn hn {
                            = skipped + skipped 1
                            ( __imp_note notes + k 1 `wrong number of columns` )
                        } {
                            : Json o ( json_obj_new )
                            : ~ i c 0
                            ~ < c cn {
                                ?? ( vec_get [String] headers c ) {
                                    T name → {
                                        ?? ( vec_get [String] cells c ) {
                                            T cell → {
                                                ?? ( __imp_cell ( string_data cell ) ) {
                                                    T v → { ( json_obj_set o ( string_data name ) v ) }
                                                    F → {}
                                                }
                                            }
                                            F _ → {}
                                        }
                                    }
                                    F _ → {}
                                }
                                = c + c 1
                            }
                            : ( Vec String ) got ( json_obj_keys o )
                            : i nfields ( vec_len [String] got )
                            ( vec_free_with [String] got \ String x → v { ( string_free x ) } )
                            ? > nfields 0 {
                                ( vec_push [Json] rows o )
                            } {
                                ( json_free o )
                                = skipped + skipped 1
                                ( __imp_note notes + k 1 `every column was empty` )
                            }
                        }
                        ( vec_free_with [String] cells \ String x → v { ( string_free x ) } )
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] headers \ String x → v { ( string_free x ) } )
    ^ @ ImportParse { rows skipped notes ( string_new ) ( string_from `csv` ) }
}

// ── JSON and JSONL ────────────────────────────────────────────────────

// Take the array out of a parsed document: the document itself when it is
// one, or the array under whichever of `data`, `points` or `rows` it hides
// behind. Those three are what export tools actually write.
@ __imp_array_of Json doc → ?Json {
    ? ( json_is_arr doc ) { ^ @ ?Json { T doc } } {}
    ? ( json_is_obj doc ) {
        ?? ( json_obj_get doc `data` ) {
            T v → { ? ( json_is_arr v ) { ^ @ ?Json { T v } } {} }
            F _ → {}
        }
        ?? ( json_obj_get doc `points` ) {
            T v → { ? ( json_is_arr v ) { ^ @ ?Json { T v } } {} }
            F _ → {}
        }
        ?? ( json_obj_get doc `rows` ) {
            T v → { ? ( json_is_arr v ) { ^ @ ?Json { T v } } {} }
            F _ → {}
        }
    } {}
    ^ @ ?Json { F }
}

@ __imp_parse_json s text → ImportParse {
    : !Json JsonError pr ( json_parse text )
    ?? pr {
        F _ → { ^ ( __imp_fail `the file is not valid JSON` ) }
        T doc → {
            : ~ ImportParse out ( __imp_fail `` )
            ?? ( __imp_array_of doc ) {
                F → {
                    ( import_parse_free out )
                    = out ( __imp_fail `expected an array of objects, or an object with a "data", "points" or "rows" array` )
                }
                T arr → {
                    : ( Vec Json ) rows ( vec_new [Json] )
                    : ( Vec String ) notes ( vec_new [String] )
                    : ~ i skipped 0
                    : i n ( json_arr_len arr )
                    : ~ i k 0
                    ~ < k n {
                        ? >= ( vec_len [Json] rows ) ANOM_IMPORT_MAX_ROWS { = k n } {
                            ?? ( json_arr_get arr k ) {
                                T e → {
                                    ? ( json_is_obj e ) {
                                        ( vec_push [Json] rows ( json_clone e ) )
                                    } {
                                        = skipped + skipped 1
                                        ( __imp_note notes + k 1 `not an object` )
                                    }
                                }
                                F _ → {}
                            }
                            = k + k 1
                        }
                    }
                    ( import_parse_free out )
                    = out @ ImportParse { rows skipped notes ( string_new ) ( string_from `json` ) }
                }
            }
            ( json_free doc )
            ^ out
        }
    }
}

@ __imp_parse_jsonl s text → ImportParse {
    : String whole ( string_from text )
    : ( Vec String ) lines ( string_split whole `\n` )
    ( string_free whole )
    : ( Vec Json ) rows ( vec_new [Json] )
    : ( Vec String ) notes ( vec_new [String] )
    : ~ i skipped 0
    : i n ( vec_len [String] lines )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] lines k ) {
            T l → {
                : String t ( __imp_trimmed ( string_data l ) )
                ? > ( string_len t ) 0 {
                    ? >= ( vec_len [Json] rows ) ANOM_IMPORT_MAX_ROWS {} {
                        : !Json JsonError r ( json_parse ( string_data t ) )
                        ?? r {
                            T j → {
                                ? ( json_is_obj j ) { ( vec_push [Json] rows j ) } {
                                    ( json_free j )
                                    = skipped + skipped 1
                                    ( __imp_note notes + k 1 `not an object` )
                                }
                            }
                            F _ → {
                                = skipped + skipped 1
                                ( __imp_note notes + k 1 `not valid JSON` )
                            }
                        }
                    }
                } {}
                ( string_free t )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
    ^ @ ImportParse { rows skipped notes ( string_new ) ( string_from `jsonl` ) }
}

// ── The one entry point ───────────────────────────────────────────────

@ import_parse s text s format → ImportParse {
    : i n ( nurl_str_len text )
    ? > n ANOM_IMPORT_MAX_BYTES { ^ ( __imp_fail `the file is too large (limit 64 MB)` ) } {}
    ? > n 0 {} { ^ ( __imp_fail `the file is empty` ) }

    : ~ String fmt ( string_from format )
    ? | == ( string_len fmt ) 0 == ( nurl_str_eq ( string_data fmt ) `auto` ) 1 {
        ( string_free fmt )
        = fmt ( import_sniff text )
    } {}
    : s f ( string_data fmt )
    : ~ ImportParse out ( __imp_fail `` )
    ? == ( nurl_str_eq f `csv` ) 1 {
        ( import_parse_free out )
        = out ( __imp_parse_csv text )
    } {
        ? == ( nurl_str_eq f `jsonl` ) 1 {
            ( import_parse_free out )
            = out ( __imp_parse_jsonl text )
        } {
            ? == ( nurl_str_eq f `json` ) 1 {
                ( import_parse_free out )
                = out ( __imp_parse_json text )
            } {
                ( import_parse_free out )
                = out ( __imp_fail `format must be "csv", "json", "jsonl" or "auto"` )
            }
        }
    }
    ( string_free fmt )
    ^ out
}
