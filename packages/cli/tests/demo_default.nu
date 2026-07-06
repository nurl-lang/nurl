// tests/demo_default.nu — a psql-style CLI: no subcommands, -h is HOST
// (not help), bare invocation acts, a positional URL is an argument.
// Exercises cli_default + the automatic help-short yield.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/cli.nu`

@ main → i {
    : *Cli c ( cli_new `demodef` `default-command demo` `1.0.0` )
    ( cli_flag_str c `host` 104 `HOST` `server host` `localhost` `DEMO_HOST` )
    ( cli_flag_int c `port` 112 `N` `server port` 5432 `` )
    ( cli_flag_bool c `verbose` 0 `chatty` )
    ( cli_cmd c `ping` `just say pong` \ CliCtx x → i { ( nurl_print `pong\n` ) ^ 0 } )
    ( cli_default c \ CliCtx x → i {
        : String h ( ctx_str x `host` )
        : i po ( ctx_int x `port` )
        ( nurl_print `connect ` )
        ( nurl_print ( string_data h ) )
        ( nurl_print `:` )
        ( nurl_print ( nurl_str_int po ) )
        ? > ( ctx_nargs x ) 0 {
            : String u ( ctx_arg x 0 )
            ( nurl_print ` url=` )
            ( nurl_print ( string_data u ) )
            ( string_free u )
        } {}
        ( nurl_print `\n` )
        ( string_free h )
        ^ 0
    } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
