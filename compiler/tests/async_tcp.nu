// async_tcp.nu — Phase 6 async TCP echo smoke test.
//
// Runs a fiber-driven echo server (`tcp_accept_async` →
// `tcp_read_chunk_async` → `tcp_write_all_async`) and a sync-blocking
// client on a separate pthread; the client sends "hello\n" to the
// server, the server echoes it back, the client verifies. Validates:
//   * tcp_accept_async / read_async / write_async park on the
//     reactor instead of blocking the worker pthread
//   * O_NONBLOCK applied transparently via the wrapper's
//     `tcp_set_nonblock` call (no NURL change needed in the user
//     program)
//   * Mixing fibers (server) and OS threads (client) works on the
//     same Channel-coordinated runtime
//   * Live socket exercise gated behind NURL_NET_TESTS=1 — same
//     convention as net_loopback / channel_basic / thread_basic.

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

// Client-side FFI: blocking TCP connect (runtime §18b — landed via
// the MQTT work but not exposed in std/net.nu yet). Declared
// locally; same C symbol as mqtt.nu's binding.
& `libc` @ nurl_tcp_connect s host i port → i

: ~ i echoed 0
: ~ i client_match 0

@ run_async_tcp_test → v {
    ( runtime_init 2 )

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18910 )
    ?? lr {
        T listener → {
            : ( Channel i ) done ( chan_new [i] )

            : ( @ v ) server \ → v {
                : !TcpConn NetErr cr ( tcp_accept_async listener )
                ?? cr {
                    T c → {
                        : !( Vec u ) NetErr rd ( tcp_read_chunk_async c 64 )
                        ?? rd {
                            T v → {
                                : !v NetErr wr ( tcp_write_all_async c v )
                                ?? wr {
                                    T u → { = echoed 1 }
                                    F e → {}
                                }
                                ( vec_free [u] v )
                            }
                            F e → {}
                        }
                        ( tcp_close_conn c )
                    }
                    F e → {}
                }
            }

            : ( @ v ) client \ → v {
                ( sleep_ms 50 )
                : i craw ( nurl_tcp_connect `127.0.0.1` 18910 )
                ? == craw 0 {
                    ( chan_send [i] done 0 )
                } {
                    : i ek ( nurl_tcp_err_kind craw )
                    ? != ek 0 {
                        ( nurl_tcp_close craw )
                        ( chan_send [i] done 0 )
                    } {
                        : s msg `hi`
                        : i wn ( nurl_tcp_write craw msg 2 )
                        ? != wn 2 {
                            ( nurl_tcp_close craw )
                            ( chan_send [i] done 0 )
                        } {
                            : s buf ( nurl_alloc 16 )
                            ( nurl_poke buf 0 0 )
                            ( nurl_poke buf 1 0 )
                            : i rdn ( nurl_tcp_read craw buf 16 )
                            ? == rdn 2 {
                                : i b0 ( nurl_peek buf 0 )
                                : i lo & b0 255
                                ? == lo 104 {
                                    : i hi & / b0 256 255
                                    ? == hi 105 {
                                        = client_match 1
                                    } {}
                                } {}
                            } {}
                            ( nurl_free buf )
                            ( nurl_tcp_close craw )
                            ( chan_send [i] done 1 )
                        }
                    }
                }
            }

            ( spawn server )
            : !Thread ThreadErr ct ( thread_spawn client )

            : ?i res ( chan_recv [i] done )
            ?? res {
                T v → {
                    ( nurl_print `client_result=` )
                    ( nurl_print ( nurl_str_int v ) )
                    ( nurl_print `\n` )
                }
                F → { ( nurl_print `client_result=closed\n` ) }
            }

            ?? ct {
                T t → { ( thread_join t ) }
                F e → {}
            }

            ( runtime_run )
            ( runtime_shutdown )

            ( nurl_print `echoed=` )
            ( nurl_print ( nurl_str_int echoed ) )
            ( nurl_print `\n` )
            ( nurl_print `client_match=` )
            ( nurl_print ( nurl_str_int client_match ) )
            ( nurl_print `\n` )

            ( chan_close [i] done )
            ( chan_free [i] done )
            ( tcp_close_listener listener )
        }
        F e → {
            ( nurl_print `listen fail: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → { ( string_free s ) ( run_async_tcp_test ) }
        F → { ( nurl_print `async TCP test skipped (set NURL_NET_TESTS=1)\n` ) }
    }
    ^ 0
}
