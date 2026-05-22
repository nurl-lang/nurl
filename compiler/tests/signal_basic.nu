// signal_basic.nu — smoke test for stdlib/std/signal.nu.
// Verifies the runtime entry points link and that
// signal_trigger_shutdown wakes a thread blocked in tcp_accept by
// soft-shutting the listener fd. Live socket required → gated by
// NURL_NET_TESTS=1.
//
// Coverage:
//   * signal_install_shutdown stores listener fd globally.
//   * Worker thread blocked in tcp_accept returns Err when the
//     handler runs (mirrors the SIGINT path; NetAccept / NetClosed
//     both signal "listener went away cleanly").
//   * signal_clear_shutdown forgets the registration (idempotent).
//
// The "live" half (NURL_NET_TESTS=1) spawns a worker, sleeps 50 ms
// to ensure it's blocked in accept, then calls
// signal_trigger_shutdown; the worker should return within ~50 ms.

$ `stdlib/std/signal.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

// Always-on smoke check: register / clear does not crash.
@ run_register_smoke → v {
    ( nurl_print `── register smoke ──\n` )
    ( signal_clear_shutdown )
    ( signal_clear_shutdown )
    ( nurl_print `  cleared twice = ok\n` )
}

@ run_live_shutdown → v {
    ( nurl_print `── live shutdown ──\n` )
    // Port 0 is rejected by the runtime's TCP listen path, so use a
    // fixed loopback-only port for the live shutdown smoke.
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18767 16 )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )

            // Worker blocks in accept. The captured listener handle stays
            // alive because the main thread holds `listener` until join.
            : ( @ v ) worker \ → v {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        ( nurl_print `  worker UNEXPECTED conn\n` )
                        ( tcp_close_conn conn )
                    }
                    F e → {
                        : s nm ( net_err_name e )
                        ( println_str `  worker err = ` nm )
                    }
                }
            }

            : !Thread ThreadErr tr ( thread_spawn worker )
            ?? tr {
                T t → {
                    // Give the worker a moment to enter accept.
                    ( sleep_ms 50 )
                    ( signal_trigger_shutdown )
                    ( thread_join t )
                    ( nurl_print `  joined\n` )
                }
                F _ → ( nurl_print `  spawn failed\n` )
            }
            ( signal_clear_shutdown )
            ( tcp_close_listener listener )
        }
        F e → {
            : s nm ( net_err_name e )
            ( println_str `  listen err = ` nm )
        }
    }
}

@ main → i {
    ( run_register_smoke )

    : ?String live ( env_get `NURL_NET_TESTS` )
    ?? live {
        T v → {
            ? != 0 ( nurl_str_eq ( string_data v ) `1` ) {
                ( run_live_shutdown )
            } { ( nurl_print `live signal tests skipped (NURL_NET_TESTS != 1)\n` ) }
            ( string_free v )
        }
        F → {
            // Option's F arm carries no payload — DON'T bind `e` here.
            // The previous `F e → ( string_free e ) ...` shape passed
            // the F-tag's undef payload slot to string_free, which
            // triggered UBSan's "applying zero offset to null pointer"
            // inside nurl_peek. Runtime is now defensive against this
            // (see runtime.c §9), but the cleanest fix is to not bind.
            ( nurl_print `live signal tests skipped (set NURL_NET_TESTS=1 to enable)\n` )
        }
    }
    ^ 0
}
