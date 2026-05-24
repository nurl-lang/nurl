// Argv — command line arguments

$ `stdlib/core/string.nu`

@ main → i {
    : i argc ( nurl_argv_count )
    : s prog ( nurl_argv_get 0 )

    ( nurl_print `Argv test...\n` )

    ( nurl_print `argc: ` )
    ( nurl_print ( nurl_str_int argc ) )
    ( nurl_print `\n` )

    ( nurl_print `program: ` )
    ( nurl_print prog )
    ( nurl_print `\n` )

    // Print all args
    : i idx 0
    ~ < idx argc {
        ( nurl_print `  arg[` )
        ( nurl_print ( nurl_str_int idx ) )
        ( nurl_print `]: ` )
        ( nurl_print ( nurl_argv_get idx ) )
        ( nurl_print `\n` )
        = idx + idx 1
    }

    // Typical usage: check for flags
    ? > argc 1 {
        : s cmd ( nurl_argv_get 1 )
        ( nurl_print `command: ` )
        ( nurl_print cmd )
        ( nurl_print `\n` )

        ? != 0 ( nurl_str_eq cmd `--help` ) {
            ( nurl_print `Usage: argv_test [options] [file]\n` )
            ( nurl_print `  --help    show this message\n` )
            ( nurl_print `  --version show version\n` )
            ^ 0
        } {}

        ? != 0 ( nurl_str_eq cmd `--version` ) {
            ( nurl_print `v0.5\n` )
            ^ 0
        } {}
    } {}

    ( nurl_print `done\n` )
    ^ 0
}
