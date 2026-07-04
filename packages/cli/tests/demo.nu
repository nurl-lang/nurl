// tests/demo.nu — a multi-command CLI built with the facade. Exercises
// subcommand routing, typed flags with env + defaults, positionals, stdin,
// and an interactive confirm. The harness (cli_test.sh) drives it.

$ `src/cli.nu`

@ cmd_hello CliCtx x → i {
    : String who ( ctx_str x `name` )
    : b loud ( ctx_bool x `loud` )
    : String msg ( string_from `hello, ` )
    ( string_push_str msg ( string_data who ) )
    ? loud { ( string_push_char msg 33 ) } {}
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )
    ( string_free msg )
    ( string_free who )
    ^ 0
}

@ cmd_add CliCtx x → i {
    : i n ( ctx_nargs x )
    : ~ i sum 0
    : ~ i k 0
    ~ < k n {
        : String a ( ctx_arg x k )
        ?? ( string_to_int a ) { T v → { = sum + sum v } F _ → {} }
        ( string_free a )
        = k + k 1
    }
    : String out ( string_new )
    ( string_push_int out sum )
    ( nurl_print ( string_data out ) )
    ( nurl_print `\n` )
    ( string_free out )
    ^ 0
}

@ cmd_port CliCtx x → i {
    : i port ( ctx_int x `port` )
    : String o ( string_new )
    ( string_push_int o port )
    ( nurl_print `port=` )
    ( nurl_print ( string_data o ) )
    ( nurl_print `\n` )
    ( string_free o )
    ^ 0
}

@ cmd_wc CliCtx x → i {
    : String s ( ctx_stdin x )
    : String o ( string_new )
    ( string_push_int o ( string_len s ) )
    ( nurl_print `bytes=` )
    ( nurl_print ( string_data o ) )
    ( nurl_print `\n` )
    ( string_free o )
    ( string_free s )
    ^ 0
}

@ cmd_rm CliCtx x → i {
    : String what ( ctx_arg x 0 )
    ? ( cli_confirm `really delete?` F ) {
        ( nurl_print `deleted ` )
        ( nurl_print ( string_data what ) )
        ( nurl_print `\n` )
    } {
        ( nurl_print `aborted\n` )
    }
    ( string_free what )
    ^ 0
}

@ main → i {
    : *Cli c ( cli_new `demo` `cli facade demo` `1.0.0` )
    ( cli_flag_str  c `name` 110 `NAME` `who to greet` `world` `DEMO_NAME` )
    ( cli_flag_bool c `loud` 108 `shout the greeting` )
    ( cli_flag_int  c `port` 112 `PORT` `a port number` 8080 `DEMO_PORT` )
    ( cli_cmd c `hello` `print a greeting` \ CliCtx x → i { ^ ( cmd_hello x ) } )
    ( cli_cmd c `add`   `sum integer arguments` \ CliCtx x → i { ^ ( cmd_add x ) } )
    ( cli_cmd c `port`  `show the resolved port` \ CliCtx x → i { ^ ( cmd_port x ) } )
    ( cli_cmd c `wc`    `count bytes on stdin` \ CliCtx x → i { ^ ( cmd_wc x ) } )
    ( cli_cmd c `rm`    `delete with confirmation` \ CliCtx x → i { ^ ( cmd_rm x ) } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
