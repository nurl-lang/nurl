// argz — a small, dependency-free command-line argument parser for NURL.
//
// Clap-shaped but deliberately tiny: boolean flags, value options
// (`--name X` and `--name=X`), short aliases (`-n`), a `--` end-of-options
// separator, positional arguments, and an auto-generated `--help` body.
//
// This package lives in the NURL registry (it is NOT part of the core
// stdlib): every CLI wants argument parsing, but the shape of a parser is
// opinionated enough that it belongs to the ecosystem, not the language.
//
// Surface:
//   ( argz_new prog about )                  → Argz
//   ( argz_flag p long short help )          → v      bool flag (--long / -short)
//   ( argz_opt  p long short help )          → v      value option (--long V)
//   ( argz_parse p argv )                    → ! ArgzMatch ArgzErr
//   ( argz_has   m long )                    → b      flag/option present?
//   ( argz_value m long )                    → ?String value of an option (borrows)
//   ( argz_positionals m )                   → ( Vec String )   (borrows)
//   ( argz_help  p )                         → String  rendered usage text
//   ( argz_err_name e )                      → s
//   ( argz_free p ) / ( argz_match_free m )  → v
//
// `short` may be empty (""), meaning the spec has no short alias. Option
// values and positionals returned by the accessors BORROW the match's
// storage — do not free them; `argz_match_free` owns the whole match.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Types ─────────────────────────────────────────────────────────────

: ArgSpec {
    String long        // canonical name, without the leading "--"
    String short       // single letter without the leading "-"; "" = none
    i takes_value      // 1 = consumes a value, 0 = boolean flag
    String help        // one-line description for --help
}

: Argz {
    String prog
    String about
    ( Vec ArgSpec ) specs
}

: ArgzMatch {
    ( Vec String ) names    // long name of each flag/option that was seen
    ( Vec String ) values   // parallel to names; "" for boolean flags
    ( Vec String ) rest     // positional arguments, in order
}

: | ArgzErr {
    ArgzUnknownFlag      // a --flag / -f not registered with the parser
    ArgzMissingValue     // a value option appeared with no value after it
}

@ argz_err_name ArgzErr e → s {
    ^ ?? e {
        ArgzUnknownFlag → `ArgzUnknownFlag`
        ArgzMissingValue → `ArgzMissingValue`
    }
}

// ── Construction ──────────────────────────────────────────────────────

@ argz_new s prog s about → Argz {
    ^ @ Argz {
        ( string_from prog )
        ( string_from about )
        ( vec_new [ArgSpec] )
    }
}

@ __argz_push Argz p s long s short i takes_value s help → v {
    ( vec_push [ArgSpec] . p specs @ ArgSpec {
        ( string_from long )
        ( string_from short )
        takes_value
        ( string_from help )
    } )
}

@ argz_flag Argz p s long s short s help → v {
    ( __argz_push p long short 0 help )
}

@ argz_opt Argz p s long s short s help → v {
    ( __argz_push p long short 1 help )
}

// ── Spec lookup ───────────────────────────────────────────────────────
//
// Returns the index of the spec matching a long name, or -1. Borrows.
@ __argz_find_long Argz p s long → i {
    : i n ( vec_len [ArgSpec] . p specs )
    : ~ i i 0
    ~ < i n {
        : ?ArgSpec s ( vec_get [ArgSpec] . p specs i )
        ?? s {
            T sp → { ? ( nurl_str_eq ( string_data . sp long ) long ) { ^ i } {} }
            F _ → {}
        }
        = i + i 1
    }
    ^ -1
}

// Index of the spec whose short alias equals `short` (non-empty), or -1.
@ __argz_find_short Argz p s short → i {
    : i n ( vec_len [ArgSpec] . p specs )
    : ~ i i 0
    ~ < i n {
        : ?ArgSpec s ( vec_get [ArgSpec] . p specs i )
        ?? s {
            T sp → {
                ? & > ( string_len . sp short ) 0 != 0 ( nurl_str_eq ( string_data . sp short ) short )
                { ^ i } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ -1
}

// ── Parsing ───────────────────────────────────────────────────────────
//
// Records one (long-name, value) hit into the match.
@ __argz_record ArgzMatch m s long s value → v {
    ( vec_push [String] . m names ( string_from long ) )
    ( vec_push [String] . m values ( string_from value ) )
}

@ argz_parse Argz p ( Vec String ) argv → !ArgzMatch ArgzErr {
    : ArgzMatch m @ ArgzMatch {
        ( vec_new [String] )
        ( vec_new [String] )
        ( vec_new [String] )
    }
    : i n ( vec_len [String] argv )
    : ~ i i 0
    : ~ b only_pos F   // after a bare "--", everything is positional
    ~ < i n {
        : ?String av ( vec_get [String] argv i )
        ?? av {
            F _ → { = i + i 1 }
            T arg → {
                : s a ( string_data arg )
                : i alen ( string_len arg )
                ? only_pos {
                    ( vec_push [String] . m rest ( string_clone arg ) )
                    = i + i 1
                } {
                    ? & == alen 2 != 0 ( nurl_str_eq a `--` ) {
                        = only_pos T
                        = i + i 1
                    } {
                        ? ( nurl_str_starts a `--` ) {
                            // long form: --name  or  --name=value
                            : i eq ( nurl_str_find a `=` )
                            : s name ? >= eq 0 ( nurl_str_slice a 2 - eq 2 ) ( nurl_str_slice a 2 - alen 2 )
                            : i si ( __argz_find_long p name )
                            ? < si 0 {
                                ( nurl_free name )
                                ( argz_match_free m )
                                ^ @ !ArgzMatch ArgzErr { F # ArgzErr ArgzUnknownFlag }
                            } {}
                            : ?ArgSpec sp ( vec_get [ArgSpec] . p specs si )
                            : ~ i needs 0
                            ?? sp { T s → { = needs . s takes_value } F _ → {} }
                            ? == needs 0 {
                                ( __argz_record m name `` )
                                ( nurl_free name )
                                = i + i 1
                            } {
                                ? >= eq 0 {
                                    // --name=value
                                    : s val ( nurl_str_slice a + eq 1 - alen + eq 1 )
                                    ( __argz_record m name val )
                                    ( nurl_free val )
                                    ( nurl_free name )
                                    = i + i 1
                                } {
                                    // --name value  (consume next argv)
                                    ? >= + i 1 n {
                                        ( nurl_free name )
                                        ( argz_match_free m )
                                        ^ @ !ArgzMatch ArgzErr { F # ArgzErr ArgzMissingValue }
                                    } {}
                                    : ?String nv ( vec_get [String] argv + i 1 )
                                    ?? nv {
                                        T v2 → { ( __argz_record m name ( string_data v2 ) ) }
                                        F _ → {}
                                    }
                                    ( nurl_free name )
                                    = i + i 2
                                }
                            }
                        } {
                            ? & != 0 ( nurl_str_starts a `-` ) > alen 1 {
                                // short form: -x  (optionally -x value)
                                : s sh ( nurl_str_slice a 1 - alen 1 )
                                : i si ( __argz_find_short p sh )
                                ( nurl_free sh )
                                ? < si 0 {
                                    ( argz_match_free m )
                                    ^ @ !ArgzMatch ArgzErr { F # ArgzErr ArgzUnknownFlag }
                                } {}
                                : ?ArgSpec sp ( vec_get [ArgSpec] . p specs si )
                                : ~ i needs 0
                                : ~ s long2 ``
                                ?? sp {
                                    T s → { = needs . s takes_value = long2 ( string_data . s long ) }
                                    F _ → {}
                                }
                                ? == needs 0 {
                                    ( __argz_record m long2 `` )
                                    = i + i 1
                                } {
                                    ? >= + i 1 n {
                                        ( argz_match_free m )
                                        ^ @ !ArgzMatch ArgzErr { F # ArgzErr ArgzMissingValue }
                                    } {}
                                    : ?String nv ( vec_get [String] argv + i 1 )
                                    ?? nv {
                                        T v2 → { ( __argz_record m long2 ( string_data v2 ) ) }
                                        F _ → {}
                                    }
                                    = i + i 2
                                }
                            } {
                                // bare positional
                                ( vec_push [String] . m rest ( string_clone arg ) )
                                = i + i 1
                            }
                        }
                    }
                }
            }
        }
    }
    ^ @ !ArgzMatch ArgzErr { T m }
}

// ── Accessors (all BORROW the match) ──────────────────────────────────

@ argz_has ArgzMatch m s long → b {
    : i n ( vec_len [String] . m names )
    : ~ i i 0
    ~ < i n {
        : ?String nm ( vec_get [String] . m names i )
        ?? nm {
            T s → { ? ( nurl_str_eq ( string_data s ) long ) { ^ T } {} }
            F _ → {}
        }
        = i + i 1
    }
    ^ F
}

@ argz_value ArgzMatch m s long → ?String {
    : i n ( vec_len [String] . m names )
    : ~ i i 0
    ~ < i n {
        : ?String nm ( vec_get [String] . m names i )
        ?? nm {
            T s → {
                ? ( nurl_str_eq ( string_data s ) long ) {
                    ^ ( vec_get [String] . m values i )
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ @ ?String { F }
}

@ argz_positionals ArgzMatch m → ( Vec String ) {
    ^ . m rest
}

// ── Help rendering ────────────────────────────────────────────────────

@ argz_help Argz p → String {
    : String out ( string_with_cap 256 )
    ( string_push_str out ( string_data . p prog ) )
    ? > ( string_len . p about ) 0 {
        ( string_push_str out ` — ` )
        ( string_push_str out ( string_data . p about ) )
    } {}
    ( string_push_str out `\n\nUSAGE:\n  ` )
    ( string_push_str out ( string_data . p prog ) )
    ( string_push_str out ` [OPTIONS] [ARGS]\n\nOPTIONS:\n` )
    : i n ( vec_len [ArgSpec] . p specs )
    : ~ i i 0
    ~ < i n {
        : ?ArgSpec s ( vec_get [ArgSpec] . p specs i )
        ?? s {
            T sp → {
                ( string_push_str out `  ` )
                ? > ( string_len . sp short ) 0 {
                    ( string_push_str out `-` )
                    ( string_push_str out ( string_data . sp short ) )
                    ( string_push_str out `, ` )
                } {
                    ( string_push_str out `    ` )
                }
                ( string_push_str out `--` )
                ( string_push_str out ( string_data . sp long ) )
                ? > . sp takes_value 0 { ( string_push_str out ` <VALUE>` ) } {}
                ( string_push_str out `\n      ` )
                ( string_push_str out ( string_data . sp help ) )
                ( string_push_str out `\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ out
}

// ── Cleanup ───────────────────────────────────────────────────────────

@ argz_free Argz p → v {
    ( string_free . p prog )
    ( string_free . p about )
    : i n ( vec_len [ArgSpec] . p specs )
    : ~ i i 0
    ~ < i n {
        : ?ArgSpec s ( vec_get [ArgSpec] . p specs i )
        ?? s {
            T sp → {
                ( string_free . sp long )
                ( string_free . sp short )
                ( string_free . sp help )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [ArgSpec] . p specs )
}

@ argz_match_free ArgzMatch m → v {
    : i nn ( vec_len [String] . m names )
    : ~ i i 0
    ~ < i nn {
        ?? ( vec_get [String] . m names i ) { T s → { ( string_free s ) } F _ → {} }
        ?? ( vec_get [String] . m values i ) { T s → { ( string_free s ) } F _ → {} }
        = i + i 1
    }
    : i nr ( vec_len [String] . m rest )
    : ~ i j 0
    ~ < j nr {
        ?? ( vec_get [String] . m rest j ) { T s → { ( string_free s ) } F _ → {} }
        = j + j 1
    }
    ( vec_free [String] . m names )
    ( vec_free [String] . m values )
    ( vec_free [String] . m rest )
}
