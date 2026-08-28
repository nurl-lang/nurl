// supervisor_strategy.nu — offline tests for the OTP restart strategies
// (stdlib/std/supervisor.nu supervisor_start). Three children A, B, C;
// B crashes on its first run then succeeds, A and C always succeed. Each
// child counts its own runs, so the run counts after the group stabilises
// distinguish the strategies:
//
//   one-for-all : B's crash restarts the WHOLE group → A=2 B=2 C=2
//   one-for-one : only B restarts                    → A=1 B=2 C=1
//   rest-for-one: B and everything after it restart  → A=1 B=2 C=2

$ `stdlib/core/string.nu`
$ `stdlib/std/supervisor.nu`

@ mk0 → *i {
    : *i p # *i ( nurl_alloc Z i )
    ( nurl_poke p 0 0 )
    ^ p
}

@ run_strategy s label SupStrategy st → v {
    : *i ca ( mk0 )
    : *i cb ( mk0 )
    : *i cc ( mk0 )
    : Supervisor sup ( supervisor_new 10 100000 )
    ( supervisor_set_strategy sup st )
    ( supervisor_add sup `a` @ RestartPolicy { RTransient }
    \ → v { ( nurl_poke ca 0 + 1 ( nurl_peek ca 0 ) ) } )
    ( supervisor_add sup `b` @ RestartPolicy { RTransient }
    \ → v {
        : i n + 1 ( nurl_peek cb 0 )
        ( nurl_poke cb 0 n )
        ? == n 1 { ( panic `b first run` ) } {}
    } )
    ( supervisor_add sup `c` @ RestartPolicy { RTransient }
    \ → v { ( nurl_poke cc 0 + 1 ( nurl_peek cc 0 ) ) } )

    : b stable ( supervisor_start sup )

    ( nurl_print label )
    ( nurl_print `: a=` ) ( nurl_print_int ( nurl_peek ca 0 ) )
    ( nurl_print ` b=` ) ( nurl_print_int ( nurl_peek cb 0 ) )
    ( nurl_print ` c=` ) ( nurl_print_int ( nurl_peek cc 0 ) )
    ( nurl_print ` stable=` ) ( nurl_print ? stable `T` `F` )
    ( nurl_print `\n` )

    ( supervisor_free sup )
    ( nurl_free # s ca )
    ( nurl_free # s cb )
    ( nurl_free # s cc )
}

@ main → i {
    ( run_strategy `one-for-all ` @ SupStrategy { OneForAll } )
    ( run_strategy `one-for-one ` @ SupStrategy { OneForOne } )
    ( run_strategy `rest-for-one` @ SupStrategy { RestForOne } )

    ( nurl_println ( sup_strategy_name # SupStrategy OneForOne ) )
    ( nurl_println ( sup_strategy_name # SupStrategy OneForAll ) )
    ( nurl_println ( sup_strategy_name # SupStrategy RestForOne ) )
    ^ 0
}
