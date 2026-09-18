// nurl-cov/lcov.nu — the tracefile everything else already reads.
//
// LCOV's `.info` format is the lingua franca of coverage: genhtml renders
// it, Codecov and Coveralls ingest it, and editors draw the gutter from
// it. Emitting it is what lets a NURL package sit in a CI pipeline that
// was never taught anything about NURL.
//
//   SF:<path>            one section per source file
//   FN:<line>,<name>     a function and where it starts
//   FNDA:<count>,<name>  how often it was called
//   FNF/FNH              functions found / hit
//   BRDA:<line>,0,<n>,<count>   a branch outcome ("-" when never reached)
//   BRF/BRH              branches found / hit
//   DA:<line>,<count>    a line and its count
//   LF/LH                lines found / hit
//   end_of_record
//
// The block field of BRDA is always 0: NURL has no notion a consumer could
// use it for, and lcov itself only requires the triple to be stable.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `model.nu`

@ lcov_render * Cov c → String {
    : String out ( string_with_cap 65536 )
    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        ( __lc_file out c i )
        = i + i 1
    }
    ^ out
}

@ __lc_kv String out s key i value → v {
    ( string_push_str out key )
    ( string_push_int out value )
    ( string_push_char out 10 )
}

@ __lc_file String out * Cov c i idx → v {
    : CovStat s ( cov_file_stat c idx )
    ( string_push_str out `SF:` )
    ( string_push_str out ( cov_file_path c idx ) )
    ( string_push_char out 10 )

    : i nf ( cov_fn_rows c idx )
    : ~ i k 0
    ~ < k nf {
        ( string_push_str out `FN:` )
        ( string_push_int out ( cov_fn_line c idx k ) )
        ( string_push_char out 44 )
        ( string_push_str out ( cov_fn_name c idx k ) )
        ( string_push_char out 10 )
        = k + k 1
    }
    = k 0
    ~ < k nf {
        ( string_push_str out `FNDA:` )
        ( string_push_int out ( cov_fn_called c idx k ) )
        ( string_push_char out 44 )
        ( string_push_str out ( cov_fn_name c idx k ) )
        ( string_push_char out 10 )
        = k + k 1
    }
    ( __lc_kv out `FNF:` . s funcs_found )
    ( __lc_kv out `FNH:` . s funcs_hit )

    : i nb ( cov_branch_rows c idx )
    = k 0
    ~ < k nb {
        ( string_push_str out `BRDA:` )
        ( string_push_int out ( cov_branch_field c idx k CBR_LINE ) )
        ( string_push_str out `,0,` )
        ( string_push_int out ( cov_branch_field c idx k CBR_IDX ) )
        ( string_push_char out 44 )
        ( string_push_int out ( cov_branch_field c idx k CBR_COUNT ) )
        ( string_push_char out 10 )
        = k + k 1
    }
    ( __lc_kv out `BRF:` . s branches_found )
    ( __lc_kv out `BRH:` . s branches_hit )

    : i last ( cov_max_line c idx )
    : ~ i l 1
    ~ <= l last {
        ? ( cov_line_exists c idx l ) {
            ( string_push_str out `DA:` )
            ( string_push_int out l )
            ( string_push_char out 44 )
            ( string_push_int out ( cov_line_count c idx l ) )
            ( string_push_char out 10 )
        } {}
        = l + l 1
    }
    ( __lc_kv out `LF:` . s lines_found )
    ( __lc_kv out `LH:` . s lines_hit )
    ( string_push_str out `end_of_record\n` )
}
