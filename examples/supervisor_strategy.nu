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
$ `stdlib/core/vec.nu`
$ `stdlib/std/supervisor.nu`

@ say s who → v {
    : String l ( string_from `  starting ` )
    ( string_push_str l who )
    ( string_push_char l 10 )
    ( nurl_print ( string_data l ) )
}

@ main → i {
    // A one-slot Vec: the closure's copy and this one are the same buffer.
    : ( Vec i ) fails ( vec_zeroed [i] 1 )
    : Supervisor sup ( supervisor_new 5 100000 )
    ( supervisor_set_strategy sup @ SupStrategy { OneForAll } )

    ( supervisor_add sup `db` @ RestartPolicy { RTransient }
    \ → v { ( say `db` ) } )
    ( supervisor_add sup `config` @ RestartPolicy { RTransient }
    \ → v {
        : i n + 1 ?? ( vec_get [i] fails 0 ) { T x → x F → 0 }
        : b _s ( vec_set [i] fails 0 n )
        ? == n 1 { ( nurl_print `  config CRASHED — one-for-all restarts the group\n` ) ( panic `config` ) }
        { ( say `config` ) }
    } )
    ( supervisor_add sup `cache` @ RestartPolicy { RTransient }
    \ → v { ( say `cache` ) } )

    ( nurl_print `bringing up the group (one-for-all)…\n` )
    : b stable ( supervisor_start sup )
    ( nurl_print ? stable `group is up.\n` `gave up (restart intensity exceeded).\n` )

    ^ 0
}
