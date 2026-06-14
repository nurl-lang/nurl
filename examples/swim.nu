// examples/swim.nu — self-maintaining cluster membership via SWIM
// (TODO §7.2). Each node gossips its view over UDP; failures are detected
// by periodic pings and disseminated epidemically. No static peer list —
// a node joins by contacting any one seed.
//
// ── Run it (one machine, several terminals) ──────────────────────────
//
//   ./nurl.sh examples/swim.nu 7001                 # seed
//   ./nurl.sh examples/swim.nu 7002 7001            # join via :7001
//   ./nurl.sh examples/swim.nu 7003 7001            # join via :7001
//
// Each node prints its membership view every second. Kill one node
// (Ctrl+C) and within a few seconds the survivors show it `suspect`
// then `dead` — the failure propagates by gossip even to nodes that
// never pinged it directly.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/swim.nu`

@ print_view *SwimNode n i port → v {
    : *MemberTable t ( swim_table n )
    : ( Vec Member ) ms ( mtable_snapshot t )
    : String line ( string_from `[:` )
    ( string_push_int line port )
    ( string_push_str line `] members(` )
    ( string_push_int line ( vec_len [Member] ms ) )
    ( string_push_str line `):` )
    : i k 0
    : ~ i j 0
    ~ < j ( vec_len [Member] ms ) {
        ?? ( vec_get [Member] ms j ) {
            T mm → {
                ( string_push_str line ` ` )
                ( string_push_str line ( string_data . mm host ) )
                ( string_push_char line 58 )
                ( string_push_int line . mm port )
                ( string_push_char line 61 )
                ( string_push_str line ( member_state_name . mm state ) )
            }
            F → {}
        }
        = j + j 1
    }
    ( string_push_char line 10 )
    ( nurl_print ( string_data line ) )
    ( string_free line )
    ( vec_free_with [Member] ms \ Member mm → v { ( member_free mm ) } )
}

@ printer_loop *SwimNode n i port → v {
    ~ 1 {
        ( sleep_ms 1000 )
        ( print_view n port )
    }
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( nurl_print `usage: swim <port> [seed_port]\n` )
        ^ 1
    } {}

    : String ps ( env_arg 1 )
    : i port ( nurl_str_to_int ( string_data ps ) )
    ( string_free ps )

    ( runtime_init 0 )

    // period 500ms, ping-timeout 300ms, suspect→dead after 2s.
    : !*SwimNode NetErr nr ( swim_node_new `127.0.0.1` port 500 300 2000 )
    ?? nr {
        T n → {
            ? > argc 2 {
                : String ss ( env_arg 2 )
                : i seed ( nurl_str_to_int ( string_data ss ) )
                ( string_free ss )
                ( swim_join n `127.0.0.1` seed )
                : String b ( string_from `joined seed :` )
                ( string_push_int b seed )
                ( string_push_char b 10 )
                ( nurl_print ( string_data b ) )
                ( string_free b )
            } {
                ( nurl_print `seed node (no join)\n` )
            }
            ( swim_run n )
            ( spawn \ → v { ( printer_loop n port ) } )
            ( runtime_run )
            ( swim_node_free n )
        }
        F e → {
            ( nurl_print `bind failed\n` )
        }
    }
    ( runtime_shutdown )
    ^ 0
}
