// coverage.nu — the coverage table of a corpus's certificates (AGORA-1015,
// spec.program-cert.2 §6 M2): `nurl-cert coverage DIR` reads every
// bundle `DIR/*.cert/manifest.json` and prints, as Markdown,
//   - the programs by verdict;
//   - their own functions by status (`coverage.functions`), counted once
//     each and by the source lines they span;
//   - the reasons of the `unsupported` ones, most frequent first.
// A function's span is its first line up to the next function's in the same
// file (a closure's lines are its own, not its parent's), the last one's to
// the file's end. Functions that start on the same line (a generic's
// instances) count its lines once, with the first of them. A reason is
// counted without the function's name in front and with its variable ids
// and parenthesised details left out, so one family is one row.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `util.nu`
$ `manifest.nu`

: s COV_STATUSES `proved validated refused open unsupported error`

// The reasons table's rows: the most frequent families, then the rest in one.
: i COV_ROWS 25

// One function of one bundle.
: CovFn {
    String file
    i line
    String status
    String reason
    String name
}

// A row of a counted table: a key, how many, how many lines, an example.
: CovRow {
    String key
    i n
    i lines
    String eg
}

@ __cov_add ( Vec CovRow ) rows s key i lines s eg → v {
    : i n ( vec_len [CovRow] rows )
    : ~ i at -1
    : ~ i k 0
    ~ < k n {
        ? & < at 0 ( nc_is . ( vec_at [CovRow] rows k ) key key ) { = at k } {}
        = k + k 1
    }
    ? < at 0 {
        ( vec_push [CovRow] rows @ CovRow { ( string_from key ) 1 lines ( string_from eg ) } )
    } {
        : CovRow r ( vec_at [CovRow] rows at )
        : b _s ( vec_set [CovRow] rows at @ CovRow { ( string_clone . r key ) + . r n 1 + . r lines lines ( string_clone . r eg ) } )
    }
}

@ __cov_get ( Vec CovRow ) rows s key → CovRow {
    : i n ( vec_len [CovRow] rows )
    : ~ i k 0
    ~ < k n {
        : CovRow r ( vec_at [CovRow] rows k )
        ? ( nc_is . r key key ) { ^ @ CovRow { ( string_clone . r key ) . r n . r lines ( string_clone . r eg ) } } {}
        = k + k 1
    }
    ^ @ CovRow { ( string_from key ) 0 0 ( string_new ) }
}

// The family of reason `why` of function `name`: no `name: ` in front, a
// variable id `v<digits>` as `vN`, a parenthesised detail as `(…)`.
@ cov_family s name s why → String {
    : ( Slice u ) w ( slice_of_str why )
    : i n ( slice_len [u] w )
    : ~ i a 0
    : String pre ( string_from name )
    ( string_push_str pre `: ` )
    ? ( string_starts_with ( string_from why ) ( string_data pre ) ) { = a ( string_len pre ) } {}
    : String o ( string_with_cap n )
    : ~ i depth 0
    : ~ i k a
    ~ < k n {
        : i c ( slice_byte w k )
        ? == c 40 {
            ? == depth 0 { ( string_push_str o `(…)` ) } {}
            = depth + depth 1
            = k + k 1
        } {
            ? == c 41 {
                ? > depth 0 { = depth - depth 1 } { ( string_push_char o c ) }
                = k + k 1
            } {
                ? > depth 0 { = k + k 1 } {
                    // `v` + digits at a word's start: a variable id
                    : b start | == k 0 ! ( __cov_word ( slice_byte w - k 1 ) )
                    : b digit & < + k 1 n ( __cov_digit ( slice_byte w + k 1 ) )
                    ? & & == c 118 start digit {
                        ( string_push_str o `vN` )
                        = k + k 1
                        ~ & < k n ( __cov_digit ( slice_byte w k ) ) { = k + k 1 }
                    } {
                        ( string_push_char o c )
                        = k + k 1
                    }
                }
            }
        }
    }
    ^ o
}

@ __cov_digit i c → b { ^ & >= c 48 <= c 57 }

@ __cov_word i c → b { ^ | | ( __cov_digit c ) & >= c 97 <= c 122 | & >= c 65 <= c 90 == c 95 }

// The number of lines of file `path`, 0 when it cannot be read; kept in
// `paths`/`counts` once read.
@ __cov_file_lines ( Vec String ) paths ( Vec i ) counts s path → i {
    : i n ( vec_len [String] paths )
    : ~ i k 0
    ~ < k n {
        ? ( nc_is ( vec_at [String] paths k ) path ) { ^ ( vec_at [i] counts k ) } {}
        = k + k 1
    }
    : ~ i lines 0
    ?? ( nc_read path ) {
        T text → {
            : ( Slice u ) t ( slice_of_str ( string_data text ) )
            : i m ( slice_len [u] t )
            : ~ i j 0
            ~ < j m {
                ? == ( slice_byte t j ) 10 { = lines + lines 1 } {}
                = j + j 1
            }
            ? & > m 0 != ( slice_byte t - m 1 ) 10 { = lines + lines 1 } {}
        }
        F → {}
    }
    ( vec_push [String] paths ( string_from path ) )
    ( vec_push [i] counts lines )
    ^ lines
}

// The span of function `k` of `fns` (one bundle's functions): up to the
// next function's first line in the same file, else the file's end; 0 for
// a function that starts where an earlier one does.
@ __cov_span ( Vec CovFn ) fns i k ( Vec String ) paths ( Vec i ) counts → i {
    : CovFn f ( vec_at [CovFn] fns k )
    : i n ( vec_len [CovFn] fns )
    // (functions that start on one line of one file, as the instances of a
    // generic template do, share its lines: the first of them counts them,
    // so a line is counted once)
    : ~ i e 0
    ~ < e k {
        : CovFn h ( vec_at [CovFn] fns e )
        ? & ( nc_is . h file ( string_data . f file ) ) == . h line . f line { ^ 0 } {}
        = e + e 1
    }
    : ~ i next -1
    : ~ i j 0
    ~ < j n {
        : CovFn g ( vec_at [CovFn] fns j )
        ? & & ( nc_is . g file ( string_data . f file ) ) > . g line . f line | < next 0 < . g line next { = next . g line } {}
        = j + j 1
    }
    ? < next 0 {
        : i fl ( __cov_file_lines paths counts ( string_data . f file ) )
        = next + fl 1
    } {}
    : i sp - next . f line
    ? < sp 1 { ^ 1 } {}
    ^ sp
}

@ __cov_pct i a i b → String {
    ? == b 0 { ^ ( string_from `–` ) } {}
    : i t / + * a 1000 / b 2 b
    : String o ( string_new )
    ( string_push_int o / t 10 )
    ( string_push_str o `.` )
    ( string_push_int o % t 10 )
    ( string_push_str o ` %` )
    ^ o
}

// The Markdown table of the bundles under `dir`; F when it cannot be listed.
@ cov_table s dir s label → ?String {
    : ( Vec String ) ents ?? ( dir_list dir ) {
        T v → v
        F _ → { ^ @ ?String { F } }
    }
    ( nc_sort ents )
    : ( Vec CovRow ) verdicts ( vec_new [CovRow] )
    : ( Vec CovRow ) stats ( vec_new [CovRow] )
    : ( Vec CovRow ) reasons ( vec_new [CovRow] )
    : ( Vec String ) paths ( vec_new [String] )
    : ( Vec i ) counts ( vec_new [i] )
    : ~ i nprog 0
    : ~ i nfn 0
    : ~ i nlines 0
    : i ne ( vec_len [String] ents )
    : ~ i e 0
    ~ < e ne {
        : String ent ( string_clone ( vec_at [String] ents e ) )
        ? ( string_ends_with ent `.cert` ) {
            : String mp ( nc_join ( string_data ( nc_join dir ( string_data ent ) ) ) `manifest.json` )
            ?? ( nc_read ( string_data mp ) ) {
                T mtext → {
                    ?? ( json_parse ( string_data mtext ) ) {
                        T m → {
                            = nprog + nprog 1
                            : String vd ( mj_get_str m `program.verdict` )
                            ( __cov_add verdicts ( string_data vd ) 0 ( string_data ent ) )
                            : ( Vec CovFn ) fns ( vec_new [CovFn] )
                            : ~ i f 0
                            ~ ( __cov_has m f ) {
                                : String fl ( mj_get_str m ( string_data ( __cov_path f `file` ) ) )
                                : String ln ( mj_get_str m ( string_data ( __cov_path f `line` ) ) )
                                : i lno ?? ( string_to_int ln ) { T x → x F _ → 0 }
                                ( vec_push [CovFn] fns @ CovFn { fl lno ( mj_get_str m ( string_data ( __cov_path f `status` ) ) )
                                    ( mj_get_str m ( string_data ( __cov_path f `reason` ) ) ) ( mj_get_str m ( string_data ( __cov_path f `name` ) ) ) } )
                                = f + f 1
                            }
                            : i nf ( vec_len [CovFn] fns )
                            : ~ i k 0
                            ~ < k nf {
                                : CovFn fn ( vec_at [CovFn] fns k )
                                : i sp ( __cov_span fns k paths counts )
                                = nfn + nfn 1
                                = nlines + nlines sp
                                ( __cov_add stats ( string_data . fn status ) sp ( string_data . fn name ) )
                                ? ( nc_is . fn status `unsupported` ) {
                                    : String fam ( cov_family ( string_data . fn name ) ( string_data . fn reason ) )
                                    : String eg ( string_from ( string_data ent ) )
                                    ( string_push_str eg ` ` )
                                    ( string_push_str eg ( string_data . fn name ) )
                                    ( __cov_add reasons ( string_data fam ) sp ( string_data eg ) )
                                } {}
                                = k + k 1
                            }
                        }
                        F _ → {}
                    }
                }
                F → {}
            }
        } {}
        = e + e 1
    }
    : String o ( string_new )
    ( string_push_str o `### ` )
    ( string_push_str o label )
    ( string_push_str o `\n\n| programs | accepted | refused | unsupported | error |\n|---:|---:|---:|---:|---:|\n| ` )
    ( string_push_int o nprog )
    : ( Vec String ) vks ( string_split ( string_from `accepted refused unsupported error` ) ` ` )
    : ~ i q 0
    ~ < q ( vec_len [String] vks ) {
        ( string_push_str o ` | ` )
        ( string_push_int o . ( __cov_get verdicts ( string_data ( vec_at [String] vks q ) ) ) n )
        = q + q 1
    }
    ( string_push_str o ` |\n\n| own functions |` )
    : ( Vec String ) sks ( string_split ( string_from COV_STATUSES ) ` ` )
    = q 0
    ~ < q ( vec_len [String] sks ) {
        ( string_push_str o ` ` )
        ( string_push_str o ( string_data ( vec_at [String] sks q ) ) )
        ( string_push_str o ` |` )
        = q + q 1
    }
    ( string_push_str o `\n|---|---:|---:|---:|---:|---:|---:|\n| by count (` )
    ( string_push_int o nfn )
    ( string_push_str o `) |` )
    = q 0
    ~ < q ( vec_len [String] sks ) {
        : i c . ( __cov_get stats ( string_data ( vec_at [String] sks q ) ) ) n
        ( string_push_str o ` ` )
        ( string_push_int o c )
        ( string_push_str o ` (` )
        ( string_push_str o ( string_data ( __cov_pct c nfn ) ) )
        ( string_push_str o `) |` )
        = q + q 1
    }
    ( string_push_str o `\n| by lines (` )
    ( string_push_int o nlines )
    ( string_push_str o `) |` )
    = q 0
    ~ < q ( vec_len [String] sks ) {
        : i c . ( __cov_get stats ( string_data ( vec_at [String] sks q ) ) ) lines
        ( string_push_str o ` ` )
        ( string_push_int o c )
        ( string_push_str o ` (` )
        ( string_push_str o ( string_data ( __cov_pct c nlines ) ) )
        ( string_push_str o `) |` )
        = q + q 1
    }
    ( string_push_str o `\n` )
    : i nr ( vec_len [CovRow] reasons )
    ? > nr 0 {
        ( string_push_str o `\n| functions | lines | why unsupported | e.g. |\n|---:|---:|---|---|\n` )
        // most frequent first; ties by the family's text
        : ( Vec i ) order ( vec_new [i] )
        : ~ i r 0
        ~ < r nr { ( vec_push [i] order r ) = r + r 1 }
        : ~ i a 1
        ~ < a nr {
            : ~ i b a
            ~ & > b 0 ( __cov_before reasons ( vec_at [i] order b ) ( vec_at [i] order - b 1 ) ) {
                : i x ( vec_at [i] order b )
                : b _1 ( vec_set [i] order b ( vec_at [i] order - b 1 ) )
                : b _2 ( vec_set [i] order - b 1 x )
                = b - b 1
            }
            = a + a 1
        }
        = r 0
        : i shown ? > nr COV_ROWS COV_ROWS nr
        ~ < r shown {
            : CovRow row ( vec_at [CovRow] reasons ( vec_at [i] order r ) )
            ( string_push_str o `| ` )
            ( string_push_int o . row n )
            ( string_push_str o ` | ` )
            ( string_push_int o . row lines )
            ( string_push_str o ` | ` )
            ( string_push_str o ( string_data ( __cov_cell ( string_data . row key ) ) ) )
            ( string_push_str o ` | ` )
            ( string_push_str o ( string_data ( __cov_cell ( string_data . row eg ) ) ) )
            ( string_push_str o ` |\n` )
            = r + r 1
        }
        // the rest in one row: how many families, functions and lines
        ? > nr shown {
            : ~ i rn 0
            : ~ i rl 0
            ~ < r nr {
                : CovRow row ( vec_at [CovRow] reasons ( vec_at [i] order r ) )
                = rn + rn . row n
                = rl + rl . row lines
                = r + r 1
            }
            ( string_push_str o `| ` )
            ( string_push_int o rn )
            ( string_push_str o ` | ` )
            ( string_push_int o rl )
            ( string_push_str o ` | ` )
            ( string_push_int o - nr shown )
            ( string_push_str o ` other reasons | |\n` )
        } {}
    } {}
    ^ @ ?String { T o }
}

// Does reasons row `a` come before row `b` (more functions; then by text)?
@ __cov_before ( Vec CovRow ) rows i a i b → b {
    : CovRow x ( vec_at [CovRow] rows a )
    : CovRow y ( vec_at [CovRow] rows b )
    ? != . x n . y n { ^ > . x n . y n } {}
    ^ < ( nurl_str_cmp ( string_data . x key ) ( string_data . y key ) ) 0
}

// A Markdown table cell: `|` escaped, in code.
@ __cov_cell s t → String {
    : ( Slice u ) w ( slice_of_str t )
    : i n ( slice_len [u] w )
    : String o ( string_with_cap + n 4 )
    // (in code: a `|` escaped, a backquote as a quote)
    ( string_push_char o 96 )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte w k )
        ? == c 124 {
            ( string_push_char o 92 )
            ( string_push_char o 124 )
        } {
            ? == c 96 { ( string_push_char o 39 ) } { ( string_push_char o c ) }
        }
        = k + k 1
    }
    ( string_push_char o 96 )
    ^ o
}

@ __cov_path i f s field → String {
    : String o ( string_from `coverage.functions.` )
    ( string_push_int o f )
    ? > ( nurl_str_len field ) 0 {
        ( string_push_str o `.` )
        ( string_push_str o field )
    } {}
    ^ o
}

@ __cov_has Json m i f → b {
    : String p ( __cov_path f `` )
    ^ ?? ( json_get m ( string_data p ) ) { T _ → T F → F }
}
