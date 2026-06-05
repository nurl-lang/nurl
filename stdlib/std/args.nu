// stdlib/std/args.nu — getopt/argparse-style CLI argument parser
//
// A small, allocation-light command-line parser. You build a spec by
// registering options (boolean flags and value-taking options), then
// parse either the real process argv or an explicit token list. Parse
// results are queried by long name.
//
// Supported syntax (GNU-ish):
//   --long                  boolean flag
//   --long VALUE            value option, value in the next token
//   --long=VALUE            value option, value glued with '='
//   -s                      short flag
//   -s VALUE / -sVALUE      short value option
//   -abc                    clustered short flags (each a flag)
//   --                      end-of-options terminator; the rest are
//                           positionals (so a positional can start '-')
//   -                       a lone '-' is a positional (stdin convention)
//
// API:
//   ( args_new prog about )            → ArgParser   prog name + one-line blurb
//   ( args_flag p long short help )    → v   register a boolean flag
//   ( args_opt p long short mv help )  → v   register a value option (mv =
//                                            metavar shown in usage, e.g. `FILE`)
//   ( args_parse_argv p )              → b   parse real argv[1..]; F on error
//   ( args_parse p tokens )            → b   parse an explicit ( Vec String )
//   ( args_present p long )            → b   was the option seen?
//   ( args_count p long )              → i   times seen (clustered/repeated)
//   ( args_value p long )              → ? String   last value (owned copy)
//   ( args_value_or p long default )   → String     value or a default (owned)
//   ( args_positional_count p )        → i
//   ( args_positionals p )             → ( Vec String )  BORROW — do not free
//   ( args_has_error p )               → b
//   ( args_error p )                   → s   borrowed message ("" when ok)
//   ( args_usage p )                   → String   generated --help text
//   ( args_free p )                    → v   release everything
//
// `short` is a byte/char code (e.g. `v` is 118); pass 0 for none. Pass
// `` (empty) for a missing long name. Query functions key off the long
// name, so give every option a long name if you want to look it up.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Types ─────────────────────────────────────────────────────────────
//
// Spec and parse state live in parallel vectors indexed by option slot.
// `counts` is mutated in place (primitive, no ownership churn); captured
// values are append-only (val_idx[k] = which option, val_str[k] = value),
// so a repeated value option keeps its history and the last one wins.

: ArgParser {
    String prog
    String about
    ( Vec String ) longs        // long name per option, "" if none
    ( Vec i ) shorts            // short char code per option, 0 if none
    ( Vec i ) kinds             // 0 = flag, 1 = value option
    ( Vec String ) metavars     // usage placeholder for value options
    ( Vec String ) helps        // help text per option
    ( Vec i ) counts            // parse result: times each option was seen
    ( Vec i ) val_idx           // append-only: option slot for a captured value
    ( Vec String ) val_str      // append-only: the captured value
    ( Vec String ) positionals  // collected positional arguments
    String error                // non-empty after a failed parse
}

@ args_new s prog s about → ArgParser {
    ^ @ ArgParser {
        ( string_from prog )
        ( string_from about )
        ( vec_new [String] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [String] )
        ( vec_new [String] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [String] )
        ( vec_new [String] )
        ( string_new )
    }
}

// ── Registration ──────────────────────────────────────────────────────

@ __args_add ArgParser p s long i short i kind s metavar s help → v {
    ( vec_push [String] . p longs ( string_from long ) )
    ( vec_push [i] . p shorts short )
    ( vec_push [i] . p kinds kind )
    ( vec_push [String] . p metavars ( string_from metavar ) )
    ( vec_push [String] . p helps ( string_from help ) )
    ( vec_push [i] . p counts 0 )
}

@ args_flag ArgParser p s long i short s help → v {
    ( __args_add p long short 0 `` help )
}

@ args_opt ArgParser p s long i short s metavar s help → v {
    ( __args_add p long short 1 metavar help )
}

// ── Internal lookups / mutation ───────────────────────────────────────

@ __args_find_long ArgParser p s name → i {
    : i n ( vec_len [String] . p longs )
    : ~ i k 0
    : ~ i res -1
    ~ < k n {
        : ?String lo ( vec_get [String] . p longs k )
        : s lraw ?? lo { T x → ( string_data x ) F → `` }
        ? == 1 ( nurl_str_eq lraw name ) { = res k = k n } {}
        = k + k 1
    }
    ^ res
}

@ __args_find_short ArgParser p i ch → i {
    : i n ( vec_len [i] . p shorts )
    : ~ i k 0
    : ~ i res -1
    ~ < k n {
        : i sc ?? ( vec_get [i] . p shorts k ) { T x → x F → 0 }
        ? & == sc ch != ch 0 { = res k = k n } {}
        = k + k 1
    }
    ^ res
}

@ __args_bump ArgParser p i idx → v {
    : i c ?? ( vec_get [i] . p counts idx ) { T x → x F → 0 }
    ( vec_set [i] . p counts idx + c 1 )
}

@ __args_err3 ArgParser p s a s b s c → v {
    ( string_clear . p error )
    ( string_push_str . p error a )
    ( string_push_str . p error b )
    ( string_push_str . p error c )
}

// ── Parsing ───────────────────────────────────────────────────────────

@ __args_is_long String tok → b {
    ^ ( string_starts_with tok `--` )
}

@ __args_is_short String tok → b {
    ? > ( string_len tok ) 1 { ^ ( string_starts_with tok `-` ) } {}
    ^ F
}

// Handle a `--…` token. Returns the number of input tokens consumed
// (1 or 2), or -1 on error (with p.error set).
@ __args_do_long ArgParser p String tok ( Vec String ) toks i i → i {
    : i tl ( string_len tok )
    : ?i eqo ( string_index_of tok `=` )
    : ~ i keyend tl
    : ~ b haveval F
    : ~ i valstart tl
    ?? eqo {
        T x → { = keyend x = haveval T = valstart + x 1 }
        F → {}
    }
    : String key ( string_substr tok 2 - keyend 2 )
    : i idx ( __args_find_long p ( string_data key ) )
    ? < idx 0 {
        ( __args_err3 p `unknown option: --` ( string_data key ) `` )
        ( string_free key )
        ^ -1
    } {}
    : i kind ?? ( vec_get [i] . p kinds idx ) { T x → x F → 0 }
    ? == kind 0 {
        ? haveval {
            ( __args_err3 p `option '--` ( string_data key ) `' takes no value` )
            ( string_free key )
            ^ -1
        } {}
        ( __args_bump p idx )
        ( string_free key )
        ^ 1
    } {}
    // value option
    ? haveval {
        : String valstr ( string_substr tok valstart - tl valstart )
        ( vec_push [i] . p val_idx idx )
        ( vec_push [String] . p val_str valstr )
        ( __args_bump p idx )
        ( string_free key )
        ^ 1
    } {}
    : i n ( vec_len [String] toks )
    ? < + i 1 n {
        : ?String nxo ( vec_get [String] toks + i 1 )
        : s nraw ?? nxo { T x → ( string_data x ) F → `` }
        ( vec_push [i] . p val_idx idx )
        ( vec_push [String] . p val_str ( string_from nraw ) )
        ( __args_bump p idx )
        ( string_free key )
        ^ 2
    } {}
    ( __args_err3 p `option '--` ( string_data key ) `' requires a value` )
    ( string_free key )
    ^ -1
}

// Handle a `-…` token (possibly a cluster). Returns tokens consumed
// (1 or 2), or -1 on error.
@ __args_do_short ArgParser p String tok ( Vec String ) toks i i → i {
    : i tl ( string_len tok )
    : s raw ( string_data tok )
    : ~ i j 1
    ~ < j tl {
        : i ch ( nurl_str_get raw j )
        : i idx ( __args_find_short p ch )
        ? < idx 0 {
            ( string_clear . p error )
            ( string_push_str . p error `unknown option: -` )
            ( string_push_char . p error ch )
            ^ -1
        } {}
        : i kind ?? ( vec_get [i] . p kinds idx ) { T x → x F → 0 }
        ? == kind 0 {
            ( __args_bump p idx )
            = j + j 1
        } {
            // value option: take the rest of the cluster, else next token
            ? < + j 1 tl {
                : String valstr ( string_substr tok + j 1 - tl + j 1 )
                ( vec_push [i] . p val_idx idx )
                ( vec_push [String] . p val_str valstr )
                ( __args_bump p idx )
                ^ 1
            } {}
            : i n ( vec_len [String] toks )
            ? < + i 1 n {
                : ?String nxo ( vec_get [String] toks + i 1 )
                : s nraw ?? nxo { T x → ( string_data x ) F → `` }
                ( vec_push [i] . p val_idx idx )
                ( vec_push [String] . p val_str ( string_from nraw ) )
                ( __args_bump p idx )
                ^ 2
            } {}
            ( string_clear . p error )
            ( string_push_str . p error `option '-` )
            ( string_push_char . p error ch )
            ( string_push_str . p error `' requires a value` )
            ^ -1
        }
    }
    ^ 1
}

@ args_parse ArgParser p ( Vec String ) toks → b {
    : i n ( vec_len [String] toks )
    : ~ i i 0
    : ~ b term F
    : ~ b ok T
    ~ & ok < i n {
        : ?String toko ( vec_get [String] toks i )
        : s traw ?? toko { T x → ( string_data x ) F → `` }
        : String tok ( string_from traw )
        : i tl ( string_len tok )
        ? term {
            ( vec_push [String] . p positionals ( string_from traw ) )
            = i + i 1
        } {
            ? ( __args_is_long tok ) {
                ? == tl 2 {
                    = term T
                    = i + i 1
                } {
                    : i adv ( __args_do_long p tok toks i )
                    ? < adv 0 { = ok F } { = i + i adv }
                }
            } {
                ? ( __args_is_short tok ) {
                    : i adv ( __args_do_short p tok toks i )
                    ? < adv 0 { = ok F } { = i + i adv }
                } {
                    ( vec_push [String] . p positionals ( string_from traw ) )
                    = i + i 1
                }
            }
        }
        ( string_free tok )
    }
    ^ ok
}

@ args_parse_argv ArgParser p → b {
    : i n ( nurl_argv_count )
    : ( Vec String ) toks ( vec_new [String] )
    : ~ i k 1
    ~ < k n {
        : s raw ( nurl_argv_get k )
        ( vec_push [String] toks ( string_from raw ) )
        = k + k 1
    }
    : b ok ( args_parse p toks )
    ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
    ^ ok
}

// ── Queries ───────────────────────────────────────────────────────────

@ args_count ArgParser p s long → i {
    : i idx ( __args_find_long p long )
    ? < idx 0 { ^ 0 } {}
    ^ ?? ( vec_get [i] . p counts idx ) { T x → x F → 0 }
}

@ args_present ArgParser p s long → b {
    ^ > ( args_count p long ) 0
}

@ args_value ArgParser p s long → ?String {
    : i idx ( __args_find_long p long )
    ? < idx 0 { ^ @ ?String { F # String 0 } } {}
    : i n ( vec_len [i] . p val_idx )
    : ~ i found -1
    : ~ i k 0
    ~ < k n {
        : i vi ?? ( vec_get [i] . p val_idx k ) { T x → x F → -1 }
        ? == vi idx { = found k } {}
        = k + k 1
    }
    ? < found 0 { ^ @ ?String { F # String 0 } } {}
    : ?String so ( vec_get [String] . p val_str found )
    : s vraw ?? so { T x → ( string_data x ) F → `` }
    ^ @ ?String { T ( string_from vraw ) }
}

@ args_value_or ArgParser p s long s default → String {
    : ?String v ( args_value p long )
    ^ ?? v {
        T s → s
        F → ( string_from default )
    }
}

@ args_positional_count ArgParser p → i {
    ^ ( vec_len [String] . p positionals )
}

// BORROW: the returned Vec is owned by the parser; iterate it with
// vec_get [String] + string_data, but do NOT free it (args_free does).
@ args_positionals ArgParser p → ( Vec String ) {
    ^ . p positionals
}

@ args_has_error ArgParser p → b {
    ^ > ( string_len . p error ) 0
}

@ args_error ArgParser p → s {
    ^ ( string_data . p error )
}

// ── Usage text ────────────────────────────────────────────────────────

@ args_usage ArgParser p → String {
    : String out ( string_new )
    ( string_push_str out `Usage: ` )
    ( string_push_str out ( string_data . p prog ) )
    ( string_push_str out ` [OPTIONS] [ARGS]\n` )
    ? > ( string_len . p about ) 0 {
        ( string_push_str out ( string_data . p about ) )
        ( string_push_char out 10 )
    } {}
    : i n ( vec_len [String] . p longs )
    ? > n 0 { ( string_push_str out `\nOptions:\n` ) } {}
    : ~ i k 0
    ~ < k n {
        ( string_push_str out `  ` )
        : i sh ?? ( vec_get [i] . p shorts k ) { T x → x F → 0 }
        ? > sh 0 {
            ( string_push_char out 45 )  // '-'
            ( string_push_char out sh )
        } {
            ( string_push_str out `  ` )
        }
        : ?String lo ( vec_get [String] . p longs k )
        : s lraw ?? lo { T x → ( string_data x ) F → `` }
        ? > ( nurl_str_len lraw ) 0 {
            ? > sh 0 { ( string_push_str out `, ` ) } { ( string_push_str out `  ` ) }
            ( string_push_str out `--` )
            ( string_push_str out lraw )
        } {}
        : i kind ?? ( vec_get [i] . p kinds k ) { T x → x F → 0 }
        ? == kind 1 {
            ( string_push_char out 32 )
            : ?String mv ( vec_get [String] . p metavars k )
            : s mraw ?? mv { T x → ( string_data x ) F → `` }
            ? > ( nurl_str_len mraw ) 0 {
                ( string_push_str out mraw )
            } {
                ( string_push_str out `VALUE` )
            }
        } {}
        ( string_push_char out 10 )
        : ?String hp ( vec_get [String] . p helps k )
        : s hraw ?? hp { T x → ( string_data x ) F → `` }
        ? > ( nurl_str_len hraw ) 0 {
            ( string_push_str out `      ` )
            ( string_push_str out hraw )
            ( string_push_char out 10 )
        } {}
        = k + k 1
    }
    ^ out
}

// ── Cleanup ───────────────────────────────────────────────────────────

@ args_free ArgParser p → v {
    ( string_free . p prog )
    ( string_free . p about )
    ( string_free . p error )
    ( vec_free_with [String] . p longs \ String s → v { ( string_free s ) } )
    ( vec_free [i] . p shorts )
    ( vec_free [i] . p kinds )
    ( vec_free_with [String] . p metavars \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] . p helps \ String s → v { ( string_free s ) } )
    ( vec_free [i] . p counts )
    ( vec_free [i] . p val_idx )
    ( vec_free_with [String] . p val_str \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] . p positionals \ String s → v { ( string_free s ) } )
}
