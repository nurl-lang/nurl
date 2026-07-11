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

            // Client uses std/net.nu's tcp_connect — the public
            // plain-TCP client connect this test also serves to pin.
            : ( @ v ) client \ → v {
                ( sleep_ms 50 )
                ?? ( tcp_connect `127.0.0.1` 18910 ) {
                    F e → ( chan_send [i] done 0 )
                    T c → {
                        : ( Vec u ) msg ( vec_new [u] )
                        ( vec_push [u] msg # u 104 )
                        ( vec_push [u] msg # u 105 )
                        : !v NetErr wr ( tcp_write_all c msg )
                        ( vec_free [u] msg )
                        ?? wr {
                            F e2 → {
                                ( tcp_close_conn c )
                                ( chan_send [i] done 0 )
                            }
                            T _ → {
                                : !( Vec u ) NetErr rd ( tcp_read_chunk c 16 )
                                ?? rd {
                                    T v → {
                                        ? == ( vec_len [u] v ) 2 {
                                            : i b0 ?? ( vec_get [u] v 0 ) { T x → # i x F → 0 }
                                            : i b1 ?? ( vec_get [u] v 1 ) { T x → # i x F → 0 }
                                            ? & == b0 104 == b1 105 { = client_match 1 } {}
                                        } {}
                                        ( vec_free [u] v )
                                    }
                                    F e3 → {}
                                }
                                ( tcp_close_conn c )
                                ( chan_send [i] done 1 )
                            }
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
