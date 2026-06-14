// examples/supervisor_strategy.nu — OTP restart strategies (TODO §7.2).
//
// A supervisor brings up three init tasks. "config" fails the first time
// it runs; under the one-for-all strategy that crash restarts the WHOLE
// group, so "db" and "cache" run again too. (Under one-for-one only
// "config" would re-run; under rest-for-one, "config" and everything
// started after it.) Switch the strategy below to watch the difference.
//
//   ./nurl.sh examples/supervisor_strategy.nu

$ `stdlib/core/string.nu`
$ `stdlib/std/supervisor.nu`

@ mk0 → *i {
    : *i p # *i ( nurl_alloc Z i )
    ( nurl_poke p 0 0 )
    ^ p
}

@ say s who → v {
    : String l ( string_from `  starting ` )
    ( string_push_str l who )
    ( string_push_char l 10 )
    ( nurl_print ( string_data l ) )
    ( string_free l )
}

@ main → i {
    : *i fails ( mk0 )
    : Supervisor sup ( supervisor_new 5 100000 )
    ( supervisor_set_strategy sup @ SupStrategy { OneForAll } )

    ( supervisor_add sup `db` @ RestartPolicy { RTransient }
        \ → v { ( say `db` ) } )
    ( supervisor_add sup `config` @ RestartPolicy { RTransient }
        \ → v {
            : i n + 1 ( nurl_peek fails 0 )
            ( nurl_poke fails 0 n )
            ? == n 1 { ( nurl_print `  config CRASHED — one-for-all restarts the group\n` ) ( panic `config` ) }
            { ( say `config` ) }
        } )
    ( supervisor_add sup `cache` @ RestartPolicy { RTransient }
        \ → v { ( say `cache` ) } )

    ( nurl_print `bringing up the group (one-for-all)…\n` )
    : b stable ( supervisor_start sup )
    ( nurl_print ? stable `group is up.\n` `gave up (restart intensity exceeded).\n` )

    ( supervisor_free sup )
    ( nurl_free # s fails )
    ^ 0
}
