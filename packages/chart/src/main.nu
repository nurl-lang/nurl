// chart — draw charts in your terminal from numbers on stdin.
//
// A genuinely-everyday companion to `nq` and friends: pipe numbers into
// `chart` and see them. Four modes, one per renderer in the `chart`
// library (`src/chart.nu`):
//
//   chart spark      one-line sparkline of the numbers           ▁▂▃▄▅▆▇█
//   chart bar        labelled horizontal bars                    ██████▌
//   chart hist       histogram (bin the numbers, --bins N)
//   chart line       line/scatter plot on a grid (--width/--height)
//
// Input is whitespace-separated numbers from stdin (or --file), e.g.
//
//   seq 1 20 | chart spark
//   chart line -f temps.txt --height 12
//   printf '%s\n' 'apples 8' 'pears 6' 'cherries 2' | chart bar
//
// In `bar` mode each input *line* is one bar: `<label...> <value>` (the
// last token is the value, the rest is the label), or a bare number whose
// label is its position. Every other mode reads a flat stream of numbers.
//
// Flags (parsed by the `argz` registry package):
//   -w / --width N     chart width in cells   (bar/hist/line; default 40)
//        --height N    plot height in rows     (line; default 10)
//   -b / --bins N      histogram buckets       (hist; default 10)
//   -f / --file PATH   read numbers from PATH instead of stdin
//   -t / --title TEXT  print TEXT above the chart
//   -h / --help        show this help
//
// Like the rest of the registry packages it leans on the ecosystem: the
// `chart` library does the drawing, `argz` parses the flags, and the
// shipped stdlib does everything else. Leak-clean under ASan/LSan on
// every path.

$ `stdlib/core/io.nu`
$ `stdlib/core/char.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/env.nu`
$ `deps/argz/src/argz.nu`
$ `src/chart.nu`

// ── Input parsing ─────────────────────────────────────────────────────

// Split `s` into whitespace-delimited tokens (owned Strings).
@ __ws_tokens String s → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : s raw ( string_data s )
    : i n ( nurl_str_len raw )
    : String cur ( string_new )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get raw i )
        ? != 0 ( is_space c ) {
            ? > ( string_len cur ) 0 {
                ( vec_push [String] out ( string_clone cur ) )
                ( string_clear cur )
            } {}
        } {
            ( string_push_char cur c )
        }
        = i + i 1
    }
    ? > ( string_len cur ) 0 { ( vec_push [String] out ( string_clone cur ) ) } {}
    ( string_free cur )
    ^ out
}

// Parse every whitespace-separated numeric token in `input` into floats;
// non-numeric tokens are skipped.
@ __parse_floats String input → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : ( Vec String ) toks ( __ws_tokens input )
    : i n ( vec_len [String] toks )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] toks i ) {
            T t → {
                ?? ( string_to_float t ) {
                    T x → { ( vec_push [f] out x ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
    ^ out
}

// Join the first `count` tokens with single spaces (owned String).
@ __join_first ( Vec String ) toks i count → String {
    : String out ( string_new )
    : ~ i i 0
    ~ < i count {
        ? > i 0 { ( string_push_char out 32 ) } {}
        ?? ( vec_get [String] toks i ) {
            T s → { ( string_push_str out ( string_data s ) ) }
            F _ → {}
        }
        = i + i 1
    }
    ^ out
}

// Parse `input` line-by-line into parallel (labels, values) for bar mode:
// the last token of a line is the value, the rest is the label; a bare
// number is labelled with its 1-based position.
@ __parse_bar String input ( Vec String ) labels ( Vec f ) values → v {
    : ( Vec String ) lines ( string_split input `\n` )
    : i nl ( vec_len [String] lines )
    : ~ i auto 1
    : ~ i li 0
    ~ < li nl {
        ?? ( vec_get [String] lines li ) {
            T line → {
                : ( Vec String ) toks ( __ws_tokens line )
                : i nt ( vec_len [String] toks )
                ? > nt 0 {
                    ?? ( vec_get [String] toks - nt 1 ) {
                        T last → {
                            ?? ( string_to_float last ) {
                                T x → {
                                    ( vec_push [f] values x )
                                    ? > nt 1 {
                                        ( vec_push [String] labels ( __join_first toks - nt 1 ) )
                                    } {
                                        : String lbl ( string_new )
                                        ( string_push_int lbl auto )
                                        ( vec_push [String] labels lbl )
                                    }
                                    = auto + auto 1
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                } {}
                ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
            }
            F _ → {}
        }
        = li + li 1
    }
    ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
}

// ── Flag helpers ──────────────────────────────────────────────────────

// Integer value of flag `long`, or `dflt` if absent / unparseable.
@ __opt_int ArgzMatch m s long i dflt → i {
    ?? ( argz_value m long ) {
        T v → {
            ?? ( string_to_int v ) {
                T n → { ^ n }
                F _ → { ^ dflt }
            }
        }
        F _ → { ^ dflt }
    }
}

@ __emit String out → v {
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// ── Help ──────────────────────────────────────────────────────────────

@ __usage Argz p → v {
    ( nurl_print `chart — draw charts in your terminal\n\n` )
    ( nurl_print `usage: chart <spark|bar|hist|line> [options]\n\n` )
    ( nurl_print `  spark   one-line sparkline\n` )
    ( nurl_print `  bar     labelled horizontal bars ('<label> <value>' per line)\n` )
    ( nurl_print `  hist    histogram of the numbers (--bins)\n` )
    ( nurl_print `  line    line/scatter plot (--width/--height)\n\n` )
    : String h ( argz_help p )
    ( nurl_print ( string_data h ) )
    ( string_free h )
    ( nurl_print `\nNumbers are read whitespace-separated from stdin (or --file).\n` )
}

// ── Main ──────────────────────────────────────────────────────────────

@ main → i {
    : Argz p ( argz_new `chart` `draw charts in your terminal` )
    ( argz_opt  p `width`  `w` `chart width in cells (default 40)` )
    ( argz_opt  p `height` `H` `plot height in rows (default 10)` )
    ( argz_opt  p `bins`   `b` `histogram buckets (default 10)` )
    ( argz_opt  p `file`   `f` `read numbers from FILE instead of stdin` )
    ( argz_opt  p `title`  `t` `print TITLE above the chart` )
    ( argz_flag p `help`   `h` `show this help` )

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
            ( nurl_eprint `chart: ` ) ( nurl_eprintln ( argz_err_name e ) )
            ( nurl_eprintln `try 'chart --help'` )
            = rc 2
        }
        T m → {
            ? ( argz_has m `help` ) {
                ( __usage p )
            } {
                // Mode = first positional (default "spark").
                : ( Vec String ) ps ( argz_positionals m )
                : ~ s mode `spark`
                ? > ( vec_len [String] ps ) 0 {
                    ?? ( vec_get [String] ps 0 ) {
                        T m0 → { = mode ( string_data m0 ) }
                        F _ → {}
                    }
                } {}

                // Read input: --file or stdin.
                : ~ String input ( string_new )
                : ~ b ok T
                ?? ( argz_value m `file` ) {
                    T fv → {
                        ?? ( read_file ( string_data fv ) ) {
                            T txt → { ( string_free input ) = input txt }
                            F _ → {
                                ( nurl_eprint `chart: cannot read file: ` )
                                ( nurl_eprintln ( string_data fv ) )
                                = rc 1 = ok F
                            }
                        }
                    }
                    F _ → {
                        ( string_free input )
                        = input ( read_all_stdin )
                    }
                }

                ? ok {
                    : i width  ( __opt_int m `width`  40 )
                    : i height ( __opt_int m `height` 10 )
                    : i bins   ( __opt_int m `bins`   10 )

                    // Optional title line.
                    ?? ( argz_value m `title` ) {
                        T tv → {
                            ( nurl_print ( string_data tv ) ) ( nurl_print `\n` )
                        }
                        F _ → {}
                    }

                    ? != 0 ( nurl_str_eq mode `bar` ) {
                        : ( Vec String ) labels ( vec_new [String] )
                        : ( Vec f ) values ( vec_new [f] )
                        ( __parse_bar input labels values )
                        ( __emit ( chart_bars labels values width ) )
                        ( vec_free_with [String] labels \ String s → v { ( string_free s ) } )
                        ( vec_free [f] values )
                    } {
                        : ( Vec f ) values ( __parse_floats input )
                        ? == 0 ( vec_len [f] values ) {
                            ( nurl_eprintln `chart: no numbers in input` )
                            = rc 1
                        } {
                            ? != 0 ( nurl_str_eq mode `hist` ) {
                                ( __emit ( chart_hist values bins width ) )
                            } {
                                ? != 0 ( nurl_str_eq mode `line` ) {
                                    ( __emit ( chart_plot values width height ) )
                                } {
                                    ? != 0 ( nurl_str_eq mode `plot` ) {
                                        ( __emit ( chart_plot values width height ) )
                                    } {
                                        ? != 0 ( nurl_str_eq mode `spark` ) {
                                            ( __emit ( chart_sparkline values ) )
                                            ( nurl_print `\n` )
                                        } {
                                            ( nurl_eprint `chart: unknown mode '` )
                                            ( nurl_eprint mode )
                                            ( nurl_eprintln `' (try spark|bar|hist|line)` )
                                            = rc 2
                                        }
                                    }
                                }
                            }
                        }
                        ( vec_free [f] values )
                    }
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
