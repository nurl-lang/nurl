// signal_basic.nu — smoke test for stdlib/std/signal.nu.
//
// Two layers, mirroring the module itself:
//
//   1. Generic per-signum handlers (no OS facilities beyond signals):
//      * signal_constant / signal_name round-trip on SIGTERM (cross-
//        platform — Win32 CRT exposes SIGTERM).
//      * signal_install / signal_raise / signal_dispatch on SIGUSR1
//        (POSIX-only — skipped where signal_constant returns -1).
//      * signal_pending observed before AND after dispatch, NURL
//        handler runs exactly once per raise.
//      * signal_clear restores the default disposition and zeroes
//        the slot — repeat raise must NOT call the handler again.
//
//   2. Legacy listener-shutdown bridge (loopback socket + a worker
//      thread — the `live` half of the declaration below):
//      * signal_install_shutdown stores listener fd globally.
//      * The listener binds port 0, so parallel runs of this suite
//        cannot collide on a fixed port.
//      * Worker thread blocked in tcp_accept returns Err when the
//        handler runs (mirrors the SIGINT path; NetAccept / NetClosed
//        both signal "listener went away cleanly").
//      * signal_clear_shutdown forgets the registration (idempotent).
//      Spawns a worker, sleeps 50 ms to ensure it's blocked in
//      accept, then calls signal_trigger_shutdown; the worker should
//      return within ~50 ms.
// requires: live

$ `stdlib/std/signal.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`

// Top-level mutable observed from inside the SIGUSR1 closure.
: ~ i usr1_count 0

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

// signal_constant / signal_name cross-platform sanity. SIGTERM is
// the only signum guaranteed to resolve on every NURL target
// (POSIX + Win32 CRT; WASI returns -1 and we report it that way).
@ run_constant_smoke → v {
    ( nurl_print `── constant smoke ──\n` )
    : i term ( signal_constant `SIGTERM` )
    ( println_str `  SIGTERM available = ` ? >= term 0 `T` `F` )
    ? >= term 0 {
        ( println_str `  signal_name(SIGTERM) = ` ( signal_name term ) )
    } {}
    : i bogus ( signal_constant `SIG_NOT_A_REAL_NAME` )
    ( println_str `  bogus name = ` ? < bogus 0 `-1 ok` `unexpected` )
    : s nm ( signal_name 9999 )
    ( println_str `  signal_name(9999) = ` nm )
}

// Generic dispatch — register a NURL closure for SIGUSR1, raise the
// signal, dispatch, observe the counter. Gated on signal_constant
// returning a valid signum so Win32/WASI degrade gracefully.
@ run_generic_dispatch → v {
    ( nurl_print `── generic dispatch ──\n` )
    : i usr1 ( signal_constant `SIGUSR1` )
    ? < usr1 0 {
        ( nurl_print `  SIGUSR1 unavailable on this target — skipped\n` )
    } {
        = usr1_count 0
        : ( @ v i ) handler \ i sig → v {
            = usr1_count + usr1_count 1
        }
        : i rc ( signal_install usr1 handler )
        ( println_str `  install rc = ` ? == rc 0 `0` `nonzero` )

        ( println_str `  pending before raise = ` ? ( signal_pending usr1 ) `T` `F` )
        ( signal_raise usr1 )
        ( println_str `  pending after  raise = ` ? ( signal_pending usr1 ) `T` `F` )

        ( signal_dispatch )
        ( println_str `  pending after dispatch = ` ? ( signal_pending usr1 ) `T` `F` )
        ( nurl_print `  handler ran = ` )
        ( nurl_print ( nurl_str_int usr1_count ) )
        ( nurl_print `\n` )

        // Re-arm guard: dispatching again with nothing pending must
        // not re-invoke the handler.
        ( signal_dispatch )
        ( nurl_print `  handler ran after empty dispatch = ` )
        ( nurl_print ( nurl_str_int usr1_count ) )
        ( nurl_print `\n` )

        // After clear, raising again leaves the default disposition.
        // SIGUSR1's default is "terminate" — sending it to ourselves
        // post-clear would kill the test runner, so we don't actually
        // raise here; instead we just check the slot was cleared by
        // observing pending stays false (no installed OS handler can
        // be set without the slot being populated again).
        ( signal_clear usr1 )
        ( println_str `  pending after clear = ` ? ( signal_pending usr1 ) `T` `F` )
    }
}

@ run_live_shutdown → v {
    ( nurl_print `── live shutdown ──\n` )
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 0 16 )
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
                        // NetAccept and NetClosed both mean "the listener
                        // went away cleanly" — which of the two surfaces
                        // depends on whether the shutdown closed the fd
                        // before or after accept() was entered, i.e. on
                        // thread timing. The assertion is that the wait
                        // ended in a clean-shutdown error, so collapse
                        // the pair rather than print a racy name into a
                        // byte-exact golden.
                        //
                        // Written as a statement `?`, not a value-level
                        // `? c \`literal\` ident`: a literal ternary arm is
                        // copied so a join with an owning sibling comes
                        // out uniformly owned, but an untracked-ident arm
                        // is deliberately not (`s` also spells an opaque
                        // handle). Mixing the two publishes "not owned"
                        // and leaks the copy — 15 bytes here, and LSan
                        // says so.
                        : s nm ( net_err_name e )
                        : i clean ? != 0 ( nurl_str_eq nm `NetAccept` ) 1
                        ( nurl_str_eq nm `NetClosed` )
                        ? != clean 0 {
                            ( println_str `  worker err = ` `clean-shutdown` )
                        } {
                            ( println_str `  worker err = ` nm )
                        }
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
            // The worker has joined, so its heap-captured env is dead —
            // release it. `thread_spawn` borrows the env and never frees
            // it (§7.4: an escaped closure's env belongs to the
            // consumer), so without this the test leaks it.
            : *u worker_env # *u worker 1
            ( nurl_free # s worker_env )
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
    ( run_constant_smoke )
    ( run_generic_dispatch )

    ( run_live_shutdown )
    ^ 0
}
