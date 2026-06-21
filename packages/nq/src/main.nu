// nq — a tiny, dependency-light JSON query tool for the command line.
//
// Think "jq, but small": read JSON from stdin (or a file), apply a
// jq-lite filter, and print the result pretty (default), compact, or
// raw. It is the kind of thing every developer reaches for daily, which
// is exactly why it belongs in the NURL registry rather than the core
// stdlib — it stitches the ecosystem together: the `argz` registry
// package parses its flags, and the shipped `stdlib/ext/json` does the
// parsing/printing.
//
//   nq                      pretty-print stdin
//   nq .user.name           navigate into an object/array (.0 = index 0)
//   nq '.items[]'           iterate an array/object, one result per line
//   nq '.items[].id'        project a field out of each element
//   nq '. | keys'           object keys (or array indices)
//   nq '. | length'         length of an array / object / string
//   nq -c .                 compact single-line output
//   nq -r .user.name        raw string output (no surrounding quotes)
//   nq -f data.json .       read from a file instead of stdin
//
// Filter grammar (v0.1), deliberately tiny:
//
//   filter      := path [ '|' func ]
//   path        := '.' | '.' seg ( ('.' | '[' int ']') seg )* [ '[]' [ '.' seg … ] ]
//   func        := 'keys' | 'length'
//
// A single trailing `[]` turns the result into a stream: the preceding
// path must select an array or object, and the rest of the path is then
// applied to each element, one line of output per element.

$ `stdlib/core/io.nu`
$ `stdlib/core/char.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `deps/argz/src/argz.nu`

// ── Output ────────────────────────────────────────────────────────────

// Print one JSON value followed by a newline, honouring -c / -r.
@ __nq_emit Json j b compact b raw → v {
    ? & raw ( json_is_str j ) {
        ( nurl_print ( json_str_data j ) )
        ( nurl_print `\n` )
    } {
        ? compact {
            : String out ( json_stringify j )
            ( nurl_print ( string_data out ) ) ( nurl_print `\n` )
            ( string_free out )
        } {
            : String out ( json_pretty j )
            ( nurl_print ( string_data out ) ) ( nurl_print `\n` )
            ( string_free out )
        }
    }
}

// ── Path normalisation ────────────────────────────────────────────────
//
// Turn a jq-ish path segment into the dotted form `json_get` expects:
// `[N]` → `.N`, leading dots dropped, runs of `.` collapsed, trailing
// `.` dropped. So `.items[0].name` → `items.0.name` and `.` → ``.
@ __nq_norm s rawpath → String {
    : i n ( nurl_str_len rawpath )
    : String out ( string_with_cap n )
    : ~ b any F        // emitted any real (non-dot) char yet?
    : ~ b pending F    // a separator is pending, flush it before next char
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get rawpath i )
        ? == c 93 {                       // ']' — drop
        } {
            : ~ i cc c
            ? == c 91 { = cc 46 } {}       // '[' → '.'
            ? == cc 46 {
                ? any { = pending T } {}   // ignore leading dots
            } {
                ? pending { ( string_push_char out 46 ) = pending F } {}
                ( string_push_char out cc )
                = any T
            }
        }
        = i + i 1
    }
    ^ out
}

// Copy src[from, to) into a fresh String with surrounding spaces trimmed.
@ __nq_substr_trim s src i from i to → String {
    : ~ i a from
    : ~ i b to
    ~ & < a b == 1 ( is_space ( nurl_str_get src a ) ) { = a + a 1 }
    ~ & < a b == 1 ( is_space ( nurl_str_get src - b 1 ) ) { = b - b 1 }
    : String out ( string_with_cap - b a )
    : ~ i i a
    ~ < i b {
        ( string_push_char out ( nurl_str_get src i ) )
        = i + i 1
    }
    ^ out
}

// ── Terminal functions (`| keys`, `| length`) ─────────────────────────
//
// Returns an OWNED Json (caller frees with json_free) on success, or
// `F` to signal "this function can't apply to a value of that type".
@ __nq_apply_func s fname Json j → ?Json {
    ? != 0 ( nurl_str_eq fname `keys` ) {
        ? ( json_is_obj j ) {
            : ( Vec String ) ks ( json_obj_keys j )
            // Match jq's `keys`: sorted (its insertion-order form is `keys_unsorted`).
            ( sort_by [String] ks \ String a String b → i { ^ ( cmp_string a b ) } )
            : Json arr ( json_arr_new )
            : i n ( vec_len [String] ks )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] ks k ) {
                    T s → { ( json_arr_push arr @ Json { JStr s } ) }   // moves s into arr
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] ks )   // shallow: the String handles now live in arr
            ^ @ ?Json { T arr }
        } {}
        ? ( json_is_arr j ) {
            : Json arr ( json_arr_new )
            : i n ( json_arr_len j )
            : ~ i k 0
            ~ < k n { ( json_arr_push arr ( json_int k ) ) = k + k 1 }
            ^ @ ?Json { T arr }
        } {}
        ^ @ ?Json { F @ Json { JNull } }
    } {}
    ? != 0 ( nurl_str_eq fname `length` ) {
        ? ( json_is_arr j ) { ^ @ ?Json { T ( json_int ( json_arr_len j ) ) } } {}
        ? ( json_is_obj j ) {
            : ( Vec String ) ks ( json_obj_keys j )
            : i n ( vec_len [String] ks )
            ( vec_free_with [String] ks \ String s → v { ( string_free s ) } )
            ^ @ ?Json { T ( json_int n ) }
        } {}
        ? ( json_is_str j ) { ^ @ ?Json { T ( json_int ( nurl_str_len ( json_str_data j ) ) ) } } {}
        ? ( json_is_null j ) { ^ @ ?Json { T ( json_int 0 ) } } {}
        ^ @ ?Json { F @ Json { JNull } }
    } {}
    // Unknown function name → treat as a non-applicable error.
    ^ @ ?Json { F @ Json { JNull } }
}

// Emit one stream value, applying an optional terminal function first.
// `func` is "" for "no function". Returns 0 on success, 1 on a type or
// unknown-function error (already reported to stderr).
@ __nq_out Json j s func b compact b raw → i {
    ? == 0 ( nurl_str_len func ) {
        ( __nq_emit j compact raw )
        ^ 0
    } {}
    : ?Json res ( __nq_apply_func func j )
    ?? res {
        T rj → { ( __nq_emit rj compact raw ) ( json_free rj ) ^ 0 }
        F _ → {
            ( nurl_eprint `nq: ` ) ( nurl_eprint func )
            ( nurl_eprint ` cannot be applied to ` ) ( nurl_eprint ( json_type_name j ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}

// Navigate `elem` by `postnorm` (possibly empty = identity), then emit.
@ __nq_emit_nav Json elem s postnorm s func b compact b raw → i {
    : ?Json sub ( json_get elem postnorm )
    : ~ i rc 0
    ?? sub {
        T sj → { = rc ( __nq_out sj func compact raw ) }
        F _ → { = rc ( __nq_out ( json_null ) func compact raw ) }   // missing → null
    }
    ^ rc
}

// `path[]` iteration: select the container at `prenorm`, then apply
// `postnorm` to each of its elements (array order / object value order).
@ __nq_iter Json doc s prenorm s postnorm s func b compact b raw → i {
    : ?Json cont ( json_get doc prenorm )
    : ~ i rc 0
    ?? cont {
        F _ → {
            ( nurl_eprint `nq: path not found\n` )
            ^ 1
        }
        T c → {
            ? ( json_is_arr c ) {
                : i n ( json_arr_len c )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get c k ) {
                        T e → {
                            : i er ( __nq_emit_nav e postnorm func compact raw )
                            ? > er rc { = rc er } {}
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
            } {
                ? ( json_is_obj c ) {
                    : ( Vec String ) keys ( json_obj_keys c )
                    : i n ( vec_len [String] keys )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [String] keys k ) {
                            T kk → {
                                ?? ( json_obj_get c ( string_data kk ) ) {
                                    T e → {
                                        : i er ( __nq_emit_nav e postnorm func compact raw )
                                        ? > er rc { = rc er } {}
                                    }
                                    F _ → {}
                                }
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
                } {
                    ( nurl_eprint `nq: cannot iterate over ` )
                    ( nurl_eprint ( json_type_name c ) ) ( nurl_eprint `\n` )
                    = rc 1
                }
            }
        }
    }
    ^ rc
}

// Evaluate a whole filter (`path` or `path | func`) against `doc`.
@ __nq_eval Json doc s filter b compact b raw → i {
    : i flen ( nurl_str_len filter )
    : i pipe ( nurl_str_find filter `|` )
    : ~ String left ( string_new )
    : ~ String func ( string_new )
    ? >= pipe 0 {
        ( string_free left ) = left ( __nq_substr_trim filter 0 pipe )
        ( string_free func ) = func ( __nq_substr_trim filter + pipe 1 flen )
    } {
        ( string_free left ) = left ( __nq_substr_trim filter 0 flen )
    }
    : s lp ( string_data left )
    : s fn ( string_data func )

    : i br ( nurl_str_find lp `[]` )
    : ~ i rc 0
    ? >= br 0 {
        : i llen ( nurl_str_len lp )
        : String pre ( __nq_substr_trim lp 0 br )
        : String post ( __nq_substr_trim lp + br 2 llen )
        : String prenorm ( __nq_norm ( string_data pre ) )
        : String postnorm ( __nq_norm ( string_data post ) )
        = rc ( __nq_iter doc ( string_data prenorm ) ( string_data postnorm ) fn compact raw )
        ( string_free prenorm ) ( string_free postnorm )
        ( string_free pre ) ( string_free post )
    } {
        : String norm ( __nq_norm lp )
        ?? ( json_get doc ( string_data norm ) ) {
            T sj → { = rc ( __nq_out sj fn compact raw ) }
            F _ → { = rc ( __nq_out ( json_null ) fn compact raw ) }
        }
        ( string_free norm )
    }
    ( string_free left )
    ( string_free func )
    ^ rc
}

// ── Help ──────────────────────────────────────────────────────────────

@ __nq_usage Argz p → v {
    ( nurl_print `nq — a tiny JSON query tool (jq-lite)\n\n` )
    ( nurl_print `Usage: nq [OPTIONS] [FILTER]\n\n` )
    ( nurl_print `FILTER is a jq-lite path; the default is '.', the whole document:\n` )
    ( nurl_print `  .                whole document\n` )
    ( nurl_print `  .user.name       navigate objects/arrays (use .0 for index 0)\n` )
    ( nurl_print `  .items[]         iterate an array/object — one result per line\n` )
    ( nurl_print `  .items[].id      project a field out of each element\n` )
    ( nurl_print `  . | keys         object keys (or array indices)\n` )
    ( nurl_print `  . | length       length of an array / object / string\n\n` )
    ( nurl_print `Reads JSON from stdin unless --file is given.\n\n` )
    : String h ( argz_help p )
    ( nurl_print ( string_data h ) )
    ( string_free h )
}

// ── Entry point ───────────────────────────────────────────────────────

@ main → i {
    : Argz p ( argz_new `nq` `a tiny JSON query tool (jq-lite)` )
    ( argz_flag p `compact` `c` `compact single-line output` )
    ( argz_flag p `raw`     `r` `raw output for string results (no quotes)` )
    ( argz_flag p `help`    `h` `show this help` )
    ( argz_opt  p `file`    `f` `read JSON from FILE instead of stdin` )

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
            ( nurl_eprint `nq: ` ) ( nurl_eprintln ( argz_err_name e ) )
            ( nurl_eprintln `try 'nq --help'` )
            = rc 2
        }
        T m → {
            ? ( argz_has m `help` ) {
                ( __nq_usage p )
            } {
                : b compact ( argz_has m `compact` )
                : b raw ( argz_has m `raw` )

                // Filter: first positional, default ".".
                : ( Vec String ) ps ( argz_positionals m )
                : ~ s filter `.`
                ? > ( vec_len [String] ps ) 0 {
                    ?? ( vec_get [String] ps 0 ) {
                        T f0 → { = filter ( string_data f0 ) }
                        F _ → {}
                    }
                } {}

                // Input: --file, else stdin.
                : ~ String input ( string_new )
                : ~ b have_input T
                ?? ( argz_value m `file` ) {
                    T fv → {
                        ?? ( read_file ( string_data fv ) ) {
                            T txt → { ( string_free input ) = input txt }
                            F _ → {
                                ( nurl_eprint `nq: cannot read file: ` )
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
                    ?? ( json_parse ( string_data input ) ) {
                        F je → {
                            : String em ( json_format_error je )
                            ( nurl_eprint `nq: ` ) ( nurl_eprintln ( string_data em ) )
                            ( string_free em )
                            = rc 1
                        }
                        T doc → {
                            = rc ( __nq_eval doc filter compact raw )
                            ( json_free doc )
                        }
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
