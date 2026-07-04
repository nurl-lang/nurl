// cli/cli.nu — the ergonomic command-line facade over the stdlib.
//
// The stdlib ships a flat argument parser (std/args), terminal control
// (std/term: isatty + ANSI + a line editor), stdin/stdout (core/io) and the
// process environment (ext/env). What every CLI re-invents on top is the
// same glue: a subcommand dispatch cascade, typed flag accessors with env
// fallbacks and defaults, coloured `--help` / `--version` / usage, error →
// exit-code handling, and interactive prompts.
//
// `Cli` collapses that into one object:
//
//     : *Cli c ( cli_new `greet` `a tiny greeter` `1.0.0` )
//     ( cli_flag_str  c `name` 110 `NAME` `who to greet` `world` `` )
//     ( cli_flag_bool c `loud` 108 `shout it` )
//     ( cli_cmd c `hello` `print a greeting` \ CliCtx x → i {
//         : String who ( ctx_str x `name` )
//         ( nurl_print `hello, ` ) ( nurl_print ( string_data who ) ) ( nurl_print `\n` )
//         ( string_free who )
//         ^ 0
//     } )
//     ^ ( cli_run c )     // parse argv, route, auto --help/--version → exit code
//
// Scope: this facades the command-line surface (args + env + stdin + tty /
// colour / prompts + exit codes). It deliberately does NOT absorb terminal
// widgets (tables/spinners), config-file loading, or logging — those compose
// as their own packages.
//
// Memory model: `cli_new` returns a heap `*Cli`, mutable across the builder
// calls; free it with `cli_free`. Flags and commands accumulate into its
// Vecs. `cli_run` owns the parse and frees everything it allocates.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/term.nu`
$ `stdlib/ext/env.nu`
$ `prompt.nu`

// Flag kinds.
//   0 = string   1 = int   2 = bool (presence)   3 = float
: CliFlag {
    String long
    i short          // short-option char code, 0 = none
    String metavar   // value placeholder in help (empty for bool)
    String help
    i kind
    String dflt      // default rendered as text (empty = none)
    String env       // environment-variable fallback (empty = none)
}

: CliCmd {
    String name
    String help
    ( @ i CliCtx ) handler
}

: Cli {
    String prog
    String about
    String version
    ( Vec CliFlag ) globals
    ( Vec CliCmd ) cmds
}

// Passed to every command handler; wraps the parsed args plus a back-ref to
// the Cli so accessors can resolve env fallbacks and defaults.
: CliCtx {
    ArgParser parser
    *Cli cli
    String cmdname
}

// ── Colour (decided once per run: stdout is a TTY and $NO_COLOR unset) ──

: ~ b g_cli_color F

@ __cli_detect_color → v {
    : ~ b on ( term_is_tty 1 )
    ?? ( env_get `NO_COLOR` ) {
        T v → { = on F ( string_free v ) }
        F junk → { ( string_free junk ) }
    }
    = g_cli_color on
}

@ __wrap s open s text → String {
    ? g_cli_color {
        : String r ( string_from open )
        ( string_push_str r text )
        : String rst ( ansi_reset )
        ( string_push_str r ( string_data rst ) )
        ( string_free rst )
        ^ r
    } {
        ^ ( string_from text )
    }
}

@ __sgr i code s text → String {
    : String o ( ansi_sgr code )
    : String r ( __wrap ( string_data o ) text )
    ( string_free o )
    ^ r
}
@ __fg i color s text → String {
    : String o ( ansi_fg color )
    : String r ( __wrap ( string_data o ) text )
    ( string_free o )
    ^ r
}

// ── Construction / teardown ───────────────────────────────────────────

@ cli_new s prog s about s version → *Cli {
    : *Cli c # *Cli ( nurl_malloc Z Cli )
    = . c prog ( string_from prog )
    = . c about ( string_from about )
    = . c version ( string_from version )
    = . c globals ( vec_new [CliFlag] )
    = . c cmds ( vec_new [CliCmd] )
    ^ c
}

@ __cli_free_flags ( Vec CliFlag ) v → v {
    : i n ( vec_len [CliFlag] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliFlag] v k ) {
            T f → {
                ( string_free . f long )
                ( string_free . f metavar )
                ( string_free . f help )
                ( string_free . f dflt )
                ( string_free . f env )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [CliFlag] v )
}

@ __cli_free_cmds ( Vec CliCmd ) v → v {
    : i n ( vec_len [CliCmd] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliCmd] v k ) {
            T cm → { ( string_free . cm name ) ( string_free . cm help ) }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [CliCmd] v )
}

@ cli_free *Cli c → v {
    ( string_free . c prog )
    ( string_free . c about )
    ( string_free . c version )
    ( __cli_free_flags . c globals )
    ( __cli_free_cmds . c cmds )
    ( nurl_free c )
}

// ── Flag builders (global flags; applied across all commands) ──────────

@ __cli_add_flag *Cli c s long i short s metavar s help i kind s dflt s env → v {
    : CliFlag f @ CliFlag {
        ( string_from long ) short ( string_from metavar ) ( string_from help )
        kind ( string_from dflt ) ( string_from env )
    }
    ( vec_push [CliFlag] . c globals f )
}

@ cli_flag_bool *Cli c s long i short s help → v {
    ( __cli_add_flag c long short `` help 2 `` `` )
}
@ cli_flag_str *Cli c s long i short s metavar s help s dflt s env → v {
    ( __cli_add_flag c long short metavar help 0 dflt env )
}
@ cli_flag_int *Cli c s long i short s metavar s help i dflt s env → v {
    : String d ( string_new )
    ( string_push_int d dflt )
    ( __cli_add_flag c long short metavar help 1 ( string_data d ) env )
    ( string_free d )
}
@ cli_flag_float *Cli c s long i short s metavar s help f dflt s env → v {
    : String d ( string_new )
    ( string_push_float d dflt )
    ( __cli_add_flag c long short metavar help 3 ( string_data d ) env )
    ( string_free d )
}

// ── Command registration ──────────────────────────────────────────────

@ cli_cmd *Cli c s name s help ( @ i CliCtx ) handler → v {
    : CliCmd cmd @ CliCmd { ( string_from name ) ( string_from help ) handler }
    ( vec_push [CliCmd] . c cmds cmd )
}

// Index of the command named `name`, or None.
@ __cli_find_cmd *Cli c s name → ?i {
    : i n ( vec_len [CliCmd] . c cmds )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliCmd] . c cmds k ) {
            T cm → {
                ? == 1 ( nurl_str_eq ( string_data . cm name ) name ) { ^ @ ?i { T k } } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?i { F }
}

// ── Context accessors (used inside handlers) ──────────────────────────

// Resolve a string flag: explicit value → env fallback → default → "".
@ __cli_fallback *Cli c s name → String {
    : i n ( vec_len [CliFlag] . c globals )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliFlag] . c globals k ) {
            T f → {
                ? == 1 ( nurl_str_eq ( string_data . f long ) name ) {
                    ? > ( string_len . f env ) 0 {
                        ?? ( env_get ( string_data . f env ) ) {
                            T v → { ^ v }
                            F junk → { ( string_free junk ) }
                        }
                    } {}
                    ^ ( string_from ( string_data . f dflt ) )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ ( string_new )
}

@ ctx_str CliCtx x s name → String {
    ?? ( args_value . x parser name ) {
        T v → { ^ v }
        F junk → { ( string_free junk ) }
    }
    ^ ( __cli_fallback . x cli name )
}

@ ctx_int CliCtx x s name → i {
    : String s ( ctx_str x name )
    : ~ i r 0
    ?? ( string_to_int s ) { T v → { = r v } F _ → {} }
    ( string_free s )
    ^ r
}

@ ctx_float CliCtx x s name → f {
    : String s ( ctx_str x name )
    : ~ f r 0.0
    ?? ( string_to_float s ) { T v → { = r v } F _ → {} }
    ( string_free s )
    ^ r
}

@ ctx_bool CliCtx x s name → b {
    ^ ( args_present . x parser name )
}

// Number of positional arguments after the command token.
@ ctx_nargs CliCtx x → i {
    : i n ( args_positional_count . x parser )
    ? > n 0 { ^ - n 1 } {}
    ^ 0
}

// The idx-th positional after the command (0-based); empty String if absent.
// `args_positionals` hands back a BORROW of the parser's own vector — read
// from it and copy out the one element; never free it here.
@ ctx_arg CliCtx x i idx → String {
    : ( Vec String ) pos ( args_positionals . x parser )
    : i n ( vec_len [String] pos )
    : i want + idx 1
    ? < want n {
        ?? ( vec_get [String] pos want ) {
            T t → { ^ ( string_from ( string_data t ) ) }
            F _ → {}
        }
    } {}
    ^ ( string_new )
}

// Slurp stdin to EOF (for pipe-friendly commands).
@ ctx_stdin CliCtx x → String {
    ^ ( read_all_stdin )
}

// The command name that was invoked.
@ ctx_cmd CliCtx x → s {
    ^ ( string_data . x cmdname )
}

// ── Help / usage rendering ────────────────────────────────────────────

@ __cli_pad String out s text i width → v {
    ( string_push_str out text )
    : i n ( nurl_str_len text )
    : ~ i k n
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
}

// "-h, --long" (or "    --long" when there's no short).
@ __cli_flag_names CliFlag f → String {
    : String r ( string_new )
    ? > . f short 0 {
        ( string_push_char r 45 )
        ( string_push_char r . f short )
        ( string_push_str r `, ` )
    } {
        ( string_push_str r `    ` )
    }
    ( string_push_str r `--` )
    ( string_push_str r ( string_data . f long ) )
    ? > ( string_len . f metavar ) 0 {
        ( string_push_str r ` <` )
        ( string_push_str r ( string_data . f metavar ) )
        ( string_push_char r 62 )
    } {}
    ^ r
}

// "      " + cyan(names) + spaces padding the raw name width to column 24.
@ __cli_opt_col String out s names → v {
    : String cyan ( __fg 6 names )
    ( string_push_str out `      ` )
    ( string_push_str out ( string_data cyan ) )
    ( string_free cyan )
    : i raw ( nurl_str_len names )
    : ~ i pw raw
    ~ < pw 24 { ( string_push_char out 32 ) = pw + pw 1 }
}

@ __cli_render_options *Cli c String out → v {
    : String hdr ( __sgr 1 `OPTIONS` )
    ( string_push_str out ( string_data hdr ) )
    ( string_push_char out 10 )
    ( string_free hdr )
    // help + version are always present
    ( __cli_opt_col out `-h, --help` )
    ( string_push_str out `show this help\n` )
    ( __cli_opt_col out `    --version` )
    ( string_push_str out `print the version\n` )
    : i n ( vec_len [CliFlag] . c globals )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliFlag] . c globals k ) {
            T f → {
                : String names ( __cli_flag_names f )
                ( __cli_opt_col out ( string_data names ) )
                ( string_push_str out ( string_data . f help ) )
                ? > ( string_len . f dflt ) 0 {
                    ( string_push_str out ` [default: ` )
                    ( string_push_str out ( string_data . f dflt ) )
                    ( string_push_char out 93 )
                } {}
                ? > ( string_len . f env ) 0 {
                    ( string_push_str out ` [env: ` )
                    ( string_push_str out ( string_data . f env ) )
                    ( string_push_char out 93 )
                } {}
                ( string_push_char out 10 )
                ( string_free names )
            }
            F _ → {}
        }
        = k + k 1
    }
}

// Longest command name, for column alignment.
@ __cli_cmd_width *Cli c → i {
    : i n ( vec_len [CliCmd] . c cmds )
    : ~ i w 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliCmd] . c cmds k ) {
            T cm → { : i l ( string_len . cm name ) ? > l w { = w l } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ w
}

@ __cli_print_help *Cli c → v {
    : String out ( string_new )
    // header
    : String prog ( __sgr 1 ( string_data . c prog ) )
    ( string_push_str out ( string_data prog ) )
    ( string_free prog )
    ( string_push_char out 32 )
    : String ver ( __fg 6 ( string_data . c version ) )
    ( string_push_str out ( string_data ver ) )
    ( string_free ver )
    ( string_push_char out 10 )
    ? > ( string_len . c about ) 0 {
        ( string_push_str out ( string_data . c about ) )
        ( string_push_char out 10 )
    } {}
    ( string_push_char out 10 )
    // usage
    : String uh ( __sgr 1 `USAGE` )
    ( string_push_str out ( string_data uh ) )
    ( string_free uh )
    ( string_push_str out `\n  ` )
    ( string_push_str out ( string_data . c prog ) )
    ( string_push_str out ` [OPTIONS] <COMMAND> [ARGS]\n\n` )
    // commands
    : i nc ( vec_len [CliCmd] . c cmds )
    ? > nc 0 {
        : String ch ( __sgr 1 `COMMANDS` )
        ( string_push_str out ( string_data ch ) )
        ( string_push_char out 10 )
        ( string_free ch )
        : i w + ( __cli_cmd_width c ) 2
        : ~ i k 0
        ~ < k nc {
            ?? ( vec_get [CliCmd] . c cmds k ) {
                T cm → {
                    : String nm ( __fg 6 ( string_data . cm name ) )
                    ( string_push_str out `  ` )
                    ( string_push_str out ( string_data nm ) )
                    : i raw ( string_len . cm name )
                    : ~ i pw raw
                    ~ < pw w { ( string_push_char out 32 ) = pw + pw 1 }
                    ( string_push_str out ( string_data . cm help ) )
                    ( string_push_char out 10 )
                    ( string_free nm )
                }
                F _ → {}
            }
            = k + k 1
        }
        ( string_push_char out 10 )
    } {}
    // options
    ( __cli_render_options c out )
    ( string_push_char out 10 )
    : String tip ( __fg 8 `Run a command with --help for its details.` )
    ( string_push_str out ( string_data tip ) )
    ( string_push_char out 10 )
    ( string_free tip )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

@ __cli_print_cmd_help *Cli c i idx → v {
    : String out ( string_new )
    ?? ( vec_get [CliCmd] . c cmds idx ) {
        T cm → {
            : String nm ( __sgr 1 ( string_data . cm name ) )
            ( string_push_str out ( string_data . c prog ) )
            ( string_push_char out 32 )
            ( string_push_str out ( string_data nm ) )
            ( string_free nm )
            ? > ( string_len . cm help ) 0 {
                ( string_push_str out ` — ` )
                ( string_push_str out ( string_data . cm help ) )
            } {}
            ( string_push_str out `\n\n` )
            : String uh ( __sgr 1 `USAGE` )
            ( string_push_str out ( string_data uh ) )
            ( string_free uh )
            ( string_push_str out `\n  ` )
            ( string_push_str out ( string_data . c prog ) )
            ( string_push_char out 32 )
            ( string_push_str out ( string_data . cm name ) )
            ( string_push_str out ` [OPTIONS] [ARGS]\n\n` )
        }
        F _ → {}
    }
    ( __cli_render_options c out )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// A styled "error: <msg>" line + usage hint on stderr.
@ __cli_err *Cli c s msg → v {
    : String pre ( __fg 1 `error:` )
    ( nurl_eprint ( string_data pre ) )
    ( string_free pre )
    ( nurl_eprint ` ` )
    ( nurl_eprintln msg )
    ( nurl_eprint `Run '` )
    ( nurl_eprint ( string_data . c prog ) )
    ( nurl_eprintln ` --help' for usage.` )
}

// ── Run ───────────────────────────────────────────────────────────────

@ __cli_register_flags *Cli c ArgParser p → v {
    : i n ( vec_len [CliFlag] . c globals )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CliFlag] . c globals k ) {
            T f → {
                ? == . f kind 2 {
                    ( args_flag p ( string_data . f long ) . f short ( string_data . f help ) )
                } {
                    ( args_opt p ( string_data . f long ) . f short ( string_data . f metavar ) ( string_data . f help ) )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
}

@ __cli_dispatch *Cli c i idx CliCtx ctx → i {
    ?? ( vec_get [CliCmd] . c cmds idx ) {
        T cm → {
            : ( @ i CliCtx ) f . cm handler
            ^ ( f ctx )
        }
        F _ → { ^ 70 }
    }
}

@ __cli_print_version *Cli c → v {
    ( nurl_print ( string_data . c prog ) )
    ( nurl_print ` ` )
    ( nurl_print ( string_data . c version ) )
    ( nurl_print `\n` )
}

// Parse the real argv, route to a subcommand, and return its exit code.
// Handles `--help` / `--version`, unknown commands, and parse errors.
@ cli_run *Cli c → i {
    ( __cli_detect_color )

    : ( Vec String ) argv ( env_args_list )
    : i argc ( vec_len [String] argv )
    : ( Vec String ) toks ( vec_new [String] )
    : ~ i k 1
    ~ < k argc {
        ?? ( vec_get [String] argv k ) {
            T t → { ( vec_push [String] toks ( string_from ( string_data t ) ) ) }
            F _ → {}
        }
        = k + k 1
    }

    // Command = first token that is not an option.
    : ~ s cmdname ``
    : ~ b found F
    : i tn ( vec_len [String] toks )
    : ~ i j 0
    ~ & ! found < j tn {
        ?? ( vec_get [String] toks j ) {
            T t → {
                : s ts ( string_data t )
                ? & > ( nurl_str_len ts ) 0 != ( nurl_str_get ts 0 ) 45 {
                    = cmdname ts
                    = found T
                } {}
            }
            F _ → {}
        }
        = j + j 1
    }

    : ArgParser p ( args_new ( string_data . c prog ) ( string_data . c about ) )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )
    ( __cli_register_flags c p )
    : b okp ( args_parse p toks )

    : ~ i rc 0
    ? ! okp {
        ( __cli_err c ( args_error p ) )
        = rc 2
    } {
    ? & ! found ( args_present p `version` ) {
        ( __cli_print_version c )
    } {
    ? found {
        ?? ( __cli_find_cmd c cmdname ) {
            T idx → {
                ? ( args_present p `help` ) {
                    ( __cli_print_cmd_help c idx )
                } {
                    : CliCtx ctx @ CliCtx { p c ( string_from cmdname ) }
                    = rc ( __cli_dispatch c idx ctx )
                    ( string_free . ctx cmdname )
                }
            }
            F _ → {
                : String m ( string_from `unknown command: ` )
                ( string_push_str m cmdname )
                ( __cli_err c ( string_data m ) )
                ( string_free m )
                = rc 2
            }
        }
    } {
        // No command. `--help` (or bare invocation) prints help; the bare
        // case is a usage error (exit 1), an explicit --help is success.
        ( __cli_print_help c )
        ? ( args_present p `help` ) {} { = rc 1 }
    } } }

    ( args_free p )
    ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] argv \ String s → v { ( string_free s ) } )
    ^ rc
}
