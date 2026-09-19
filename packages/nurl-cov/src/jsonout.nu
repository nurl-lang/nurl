// nurl-cov/jsonout.nu — the machine-readable shape of the same numbers.
//
// For a CI step that wants to compare two runs, post a comment, or gate on
// something more specific than one percentage. The line map is an object
// keyed by line number, so a consumer can ask about a line directly
// instead of scanning an array.
//
//   { "objects": 7,
//     "totals": { "lines_found": …, "lines_hit": …, … },
//     "files": [ { "path": "src/x.nu",
//                  "lines_found": …, "lines_hit": …,
//                  "lines": { "12": 4, "13": 0 },
//                  "branches": [ { "line": 12, "index": 0, "count": 4 } ],
//                  "functions": [ { "name": "f", "line": 3, "called": 4 } ] } ] }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `model.nu`

@ __js_str String out s text → v {
    ( string_push_char out 34 )
    : i n ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_at text n k )
        ? == ch 34 { ( string_push_str out `\\"` ) } {
            ? == ch 92 { ( string_push_str out `\\\\` ) } {
                ? == ch 10 { ( string_push_str out `\\n` ) } {
                    ? < ch 32 { ( __js_escape out ch ) } {
                        ( string_push_char out ch )
                    }
                }
            }
        }
        = k + k 1
    }
    ( string_push_char out 34 )
}

@ __js_escape String out i ch → v {
    ( string_push_str out `\\u00` )
    ( string_push_char out ( __js_hex / ch 16 ) )
    ( string_push_char out ( __js_hex % ch 16 ) )
}

@ __js_hex i n → i {
    ^ ? < n 10 + 48 n + 87 n
}

@ __js_field String out s name i value b comma → v {
    ? comma { ( string_push_char out 44 ) } {}
    ( __js_str out name )
    ( string_push_char out 58 )
    ( string_push_int out value )
}

@ json_render * Cov c → String {
    : String out ( string_with_cap 65536 )
    ( string_push_str out `{"objects":` )
    ( string_push_int out . c objects )
    ( string_push_str out `,"totals":` )
    : CovStat t ( cov_total c )
    ( __js_stat out t )
    ( string_push_str out `,"files":[` )
    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        ? > i 0 { ( string_push_char out 44 ) } {}
        ( __js_file out c i )
        = i + i 1
    }
    ( string_push_str out `]}\n` )
    ^ out
}

@ __js_stat String out CovStat s → v {
    ( string_push_char out 123 )
    ( __js_field out `lines_found` . s lines_found F )
    ( __js_field out `lines_hit` . s lines_hit T )
    ( __js_field out `branches_found` . s branches_found T )
    ( __js_field out `branches_hit` . s branches_hit T )
    ( __js_field out `functions_found` . s funcs_found T )
    ( __js_field out `functions_hit` . s funcs_hit T )
    ( string_push_char out 125 )
}

@ __js_file String out * Cov c i idx → v {
    : CovStat s ( cov_file_stat c idx )
    ( string_push_str out `{"path":` )
    ( __js_str out ( cov_file_path c idx ) )
    ( string_push_char out 44 )
    ( __js_field out `lines_found` . s lines_found F )
    ( __js_field out `lines_hit` . s lines_hit T )
    ( __js_field out `branches_found` . s branches_found T )
    ( __js_field out `branches_hit` . s branches_hit T )
    ( __js_field out `functions_found` . s funcs_found T )
    ( __js_field out `functions_hit` . s funcs_hit T )

    ( string_push_str out `,"lines":{` )
    : i last ( cov_max_line c idx )
    : ~ b first T
    : ~ i l 1
    ~ <= l last {
        ? ( cov_line_exists c idx l ) {
            ? ! first { ( string_push_char out 44 ) } {}
            = first F
            ( string_push_char out 34 )
            ( string_push_int out l )
            ( string_push_str out `":` )
            ( string_push_int out ( cov_line_count c idx l ) )
        } {}
        = l + l 1
    }
    ( string_push_str out `},"branches":[` )
    : i nb ( cov_branch_rows c idx )
    : ~ i k 0
    ~ < k nb {
        ? > k 0 { ( string_push_char out 44 ) } {}
        ( string_push_str out `{"line":` )
        ( string_push_int out ( cov_branch_field c idx k CBR_LINE ) )
        ( string_push_str out `,"index":` )
        ( string_push_int out ( cov_branch_field c idx k CBR_IDX ) )
        ( string_push_str out `,"count":` )
        ( string_push_int out ( cov_branch_field c idx k CBR_COUNT ) )
        ( string_push_char out 125 )
        = k + k 1
    }
    ( string_push_str out `],"functions":[` )
    : i nf ( cov_fn_rows c idx )
    = k 0
    ~ < k nf {
        ? > k 0 { ( string_push_char out 44 ) } {}
        ( string_push_str out `{"name":` )
        ( __js_str out ( cov_fn_name c idx k ) )
        ( string_push_str out `,"line":` )
        ( string_push_int out ( cov_fn_line c idx k ) )
        ( string_push_str out `,"called":` )
        ( string_push_int out ( cov_fn_called c idx k ) )
        ( string_push_char out 125 )
        = k + k 1
    }
    ( string_push_str out `]}` )
}
