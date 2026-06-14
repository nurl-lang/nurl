// examples/supervisor.nu — OTP-style fiber supervision (TODO §7.2).
//
// Two worker fibers run under a one-for-one supervisor. "beta" panics on
// its first attempt; the supervisor catches the crash and restarts it
// (Transient policy), and the restarted run completes. "alpha" just runs
// to completion. When both children have stopped, we print how many times
// each was restarted.
//
//   ./nurl.sh examples/supervisor.nu

$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/supervisor.nu`

@ make_counter → *i {
    : *i p # *i ( nurl_alloc Z i )
    ( nurl_poke p 0 0 )
    ^ p
}

@ say s who s msg → v {
    : String line ( string_from `  [` )
    ( string_push_str line who )
    ( string_push_str line `] ` )
    ( string_push_str line msg )
    ( string_push_char line 10 )
    ( nurl_print ( string_data line ) )
    ( string_free line )
}

@ main → i {
    ( runtime_init 0 )
    : Supervisor sup ( supervisor_new 5 100000 )

    // alpha: runs once, cleanly.
    ( supervisor_add sup `alpha` @ RestartPolicy { RTransient }
        \ → v { ( say `alpha` `working… done` ) } )

    // beta: crashes the first time, succeeds when restarted.
    : *i bc ( make_counter )
    ( supervisor_add sup `beta` @ RestartPolicy { RTransient }
        \ → v {
            : i n + 1 ( nurl_peek bc 0 )
            ( nurl_poke bc 0 n )
            ? == n 1 {
                ( say `beta` `crashing on first attempt!` )
                ( panic `beta failed` )
            } {
                ( say `beta` `recovered, working… done` )
            }
        } )

    ( nurl_print `supervisor starting children…\n` )
    ( supervisor_run sup )
    ( runtime_run )

    : String summary ( string_from `restarts — alpha: ` )
    ( string_push_int summary ( child_restarts sup 0 ) )
    ( string_push_str summary `, beta: ` )
    ( string_push_int summary ( child_restarts sup 1 ) )
    ( string_push_char summary 10 )
    ( nurl_print ( string_data summary ) )

    ( supervisor_free sup )
    ( nurl_free # s bc )
    ( runtime_shutdown )
    ^ 0
}
