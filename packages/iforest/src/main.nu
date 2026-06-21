// iforest — score the rows of a numeric CSV for anomalousness.
//
// Reads a numeric CSV (rows = samples, columns = features) from stdin or a
// file, trains an Isolation Forest, and prints an anomaly score in (0, 1]
// for each row — higher means more anomalous. By default one score per
// line, in input order (paste it back as a new column); with --top K it
// prints the K most anomalous rows as `index<TAB>score`, highest first.
//
//   iforest < data.csv                  # one score per row
//   iforest -f data.csv --top 10        # 10 most anomalous rows
//   iforest -f data.csv -H -t 200 -S 7  # skip header, 200 trees, seed 7
//
// Built on the `argz` registry package (flags) and this package's own
// `iforest` library.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/env.nu`
$ `deps/argz/src/argz.nu`
$ `src/iforest.nu`

// A parsed numeric matrix: `data` is row-major (rows*cols), owned by caller.
: Dataset {
    ( Vec f ) data
    i rows
    i cols
}

// One row's score, for the --top ranking. NB: the index field is `row`,
// not `idx` — a field named `idx` would collide with the generic vec.nu
// helpers' own `idx` parameter, so `. data idx` inside vec_get[ScoreRow]
// would resolve as a field access instead of an array index.
: ScoreRow {
    i row
    f score
}

// ── Helpers ───────────────────────────────────────────────────────────

// Value of an integer option, or `dflt` if it was not supplied.
@ __opt_int ArgzMatch m s name i dflt → i {
    ?? ( argz_value m name ) {
        T v → { ^ ( nurl_str_to_int ( string_data v ) ) }
        F _ → { ^ dflt }
    }
}

// Append a float and a newline to `out`.
@ __push_score_line String out f x → v {
    ( string_push_float out x )
    ( string_push_char out 10 )
}

// Drop helper for a ( Vec String ).
@ __free_strvec ( Vec String ) v → v {
    ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
}

// Descending by score (so sort_by yields most-anomalous first).
@ __cmp_score_desc ScoreRow a ScoreRow b → i {
    ? > . a score . b score { ^ -1 } {}
    ? < . a score . b score { ^ 1 } {}
    ^ 0
}

// ── CSV → matrix ──────────────────────────────────────────────────────
//
// Splits on newlines, then on `delim`. Non-numeric / empty fields are
// dropped; the first data row fixes the column count and later rows whose
// numeric-field count differs are skipped (keeping the matrix rectangular).
@ __parse_csv s input s delim b skip_header → Dataset {
    : String text ( string_from input )
    : ( Vec String ) lines ( string_split text `\n` )
    ( string_free text )

    : ( Vec f ) data ( vec_new [f] )
    : ~ i cols -1
    : ~ i rows 0
    : i nl ( vec_len [String] lines )
    : ~ i li 0
    ~ < li nl {
        ?? ( vec_get [String] lines li ) {
            T line → {
                ? & == li 0 skip_header { } {
                    : String tl ( string_trim line )
                    ? > ( string_len tl ) 0 {
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
                        ( __free_strvec fields )

                        : i nv ( vec_len [f] rowvals )
                        ? > nv 0 {
                            ? < cols 0 { = cols nv } {}
                            ? == nv cols {
                                ( vec_extend [f] data rowvals )
                                = rows + rows 1
                            } {}
                        } {}
                        ( vec_free [f] rowvals )
                    } {}
                    ( string_free tl )
                }
            }
            F _ → {}
        }
        = li + li 1
    }
    ( __free_strvec lines )
    ? < cols 0 { = cols 0 } {}
    ^ @ Dataset { data rows cols }
}

// ── Output ────────────────────────────────────────────────────────────

// One score per line, in input order.
@ __emit_all IForest fo Dataset ds → v {
    : String out ( string_with_cap * . ds rows 12 )
    : ~ i r 0
    ~ < r . ds rows {
        ( __push_score_line out ( iforest_score_row fo . ds data r ) )
        = r + r 1
    }
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// The `k` most anomalous rows, as `index<TAB>score`, highest first.
@ __emit_top IForest fo Dataset ds i k → v {
    : ( Vec ScoreRow ) rank ( vec_with_cap [ScoreRow] . ds rows )
    : ~ i r 0
    ~ < r . ds rows {
        : f sc ( iforest_score_row fo . ds data r )
        ( vec_push [ScoreRow] rank @ ScoreRow { r sc } )
        = r + r 1
    }
    ( sort_by [ScoreRow] rank \ ScoreRow a ScoreRow b → i { ( __cmp_score_desc a b ) } )

    : ~ i lim k
    ? > lim . ds rows { = lim . ds rows } {}
    ? < lim 0 { = lim 0 } {}

    : String out ( string_with_cap * lim 16 )
    : ~ i j 0
    ~ < j lim {
        ?? ( vec_get [ScoreRow] rank j ) {
            T sr → {
                ( string_push_int out . sr row )
                ( string_push_char out 9 )
                ( string_push_float out . sr score )
                ( string_push_char out 10 )
            }
            F _ → {}
        }
        = j + j 1
    }
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ( vec_free [ScoreRow] rank )
}

// ── Entry point ───────────────────────────────────────────────────────

@ main → i {
    : Argz p ( argz_new `iforest` `Isolation Forest anomaly detection over a numeric CSV` )
    ( argz_flag p `help`   `h` `show this help` )
    ( argz_flag p `header` `H` `skip the first line (treat it as a header)` )
    ( argz_opt  p `file`   `f` `read CSV from FILE instead of stdin` )
    ( argz_opt  p `trees`  `t` `number of trees in the forest (default 100)` )
    ( argz_opt  p `sample` `s` `subsample size per tree (default 256)` )
    ( argz_opt  p `seed`   `S` `PRNG seed for reproducible forests (default 42)` )
    ( argz_opt  p `top`    `k` `print only the K most anomalous rows (index<TAB>score, desc)` )
    ( argz_opt  p `delim`  `d` `field delimiter (default ",")` )

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }

    : ~ i rc 0
    : !ArgzMatch ArgzErr r ( argz_parse p argv )
    ?? r {
        F e → {
            ( nurl_eprint `iforest: ` ) ( nurl_eprintln ( argz_err_name e ) )
            ( nurl_eprintln `try 'iforest --help'` )
            = rc 2
        }
        T m → {
            ? ( argz_has m `help` ) {
                : String h ( argz_help p )
                ( nurl_print `iforest — Isolation Forest anomaly detection\n\n` )
                ( nurl_print `Reads a numeric CSV (rows = samples, columns = features) from stdin\n` )
                ( nurl_print `unless --file is given, and prints an anomaly score in (0, 1] per row\n` )
                ( nurl_print `(higher = more anomalous).\n\n` )
                ( nurl_print ( string_data h ) )
                ( string_free h )
            } {
                : i trees  ( __opt_int m `trees`  100 )
                : i sample ( __opt_int m `sample` 256 )
                : i seed   ( __opt_int m `seed`   42 )
                : ~ i topk -1
                ? ( argz_has m `top` ) { = topk ( __opt_int m `top` 10 ) } {}
                : ~ s delim `,`
                ?? ( argz_value m `delim` ) { T dv → { = delim ( string_data dv ) } F _ → {} }
                : b skip_header ( argz_has m `header` )

                // Input: --file, else stdin.
                : ~ String input ( string_new )
                : ~ b have_input T
                ?? ( argz_value m `file` ) {
                    T fv → {
                        ?? ( read_file ( string_data fv ) ) {
                            T txt → { ( string_free input ) = input txt }
                            F _ → {
                                ( nurl_eprint `iforest: cannot read file: ` )
                                ( nurl_eprintln ( string_data fv ) )
                                = rc 1
                                = have_input F
                            }
                        }
                    }
                    F _ → {
                        ( string_free input )
                        = input ( read_all_stdin )
                    }
                }

                ? have_input {
                    : Dataset ds ( __parse_csv ( string_data input ) delim skip_header )
                    ? || <= . ds rows 0 <= . ds cols 0 {
                        ( nurl_eprintln `iforest: no numeric rows found in input` )
                        = rc 1
                    } {
                        : IForest fo ( iforest_train . ds data . ds rows . ds cols trees sample seed )
                        ? < topk 0 {
                            ( __emit_all fo ds )
                        } {
                            ( __emit_top fo ds topk )
                        }
                        ( iforest_free fo )
                    }
                    ( vec_free [f] . ds data )
                } {}
                ( string_free input )
            }
            ( argz_match_free m )
        }
    }

    ( argz_free p )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
