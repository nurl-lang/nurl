// TEMPORARY diagnostic — delete before merging the macOS tier-1 work.
//
// Round 1 of this probe cleared the whole synchronous child-process
// path on macOS arm64: process_run of an absolute path, of a
// PATH-resolved name, of a missing binary (so the exec-errno pipe
// works), and process_run_shell all returned correct output in half a
// second. That also clears poll(2)-on-a-pipe, since the drain loop
// those calls go through is exactly that.
//
// Ten corpus failures remain, in two groups that do NOT share an API:
//
//   * process_pipes, process_spawn_basic, mcp_stdio_basic use the
//     STREAMING spawn API — process_spawn0 + proc_write/proc_read_line
//     — which round 1 never touched.
//   * async_tcp, net_loopback, http_server_* and tls_large_record all
//     pair a FIBER-side server with a blocking client. The fiber
//     backend fix took this group from crashing to hanging, so the
//     switch itself works; what is left is the reactor.
//
// Phase G walks the streaming API one call at a time. Phase I is
// async_tcp cut down to its skeleton, with a marker before and after
// every step that could block. The last marker printed names the call
// that hangs.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`

: ~ i echoed 0
: ~ i client_match 0

@ mark s m → v { ( nurl_print `[probe] ` ) ( nurl_print m ) ( nurl_print `\n` ) ( flush ) }

@ marki s m i n → v {
    ( nurl_print `[probe] ` ) ( nurl_print m ) ( nurl_print `=` )
    ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) ( flush )
}

// ── Phase G: the streaming spawn API ────────────────────────────────
@ phase_g → v {
    ( mark `G1 spawn cat` )
    : !ProcChild ProcessErr r ( process_spawn0 `cat` )
    ?? r {
        F e → ( marki `G-spawn-ERR` # i e )
        T p → {
            ( mark `G2 spawned, writing line` )
            : i w ( proc_write_line p `hello` )
            ( marki `G3 wrote` w )
            ( mark `G4 read_line (2s timeout)` )
            : ?String l1 ( proc_read_line p 2000 )
            ?? l1 {
                T s → { ( nurl_print `[probe] G5 line=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( flush ) ( string_free s ) }
                F → ( mark `G5 line=NONE` )
            }
            ( mark `G6 close_stdin` )
            ( proc_close_stdin p )
            ( mark `G7 read_line after close (2s)` )
            : ?String l2 ( proc_read_line p 2000 )
            ?? l2 { T s → ( string_free s ) F → {} }
            ( marki `G8 eof` ? ( proc_eof p ) 1 0 )
            ( mark `G9 wait` )
            : i rc ( proc_wait p )
            ( marki `G10 wait_rc` rc )
            ( proc_free p )
            ( mark `G11 done` )
        }
    }
}

// ── Phase I: fiber server + blocking client, the async_tcp skeleton ──
@ phase_i → v {
    ( mark `I1 runtime_init` )
    ( runtime_init 2 )
    ( mark `I2 tcp_listen` )
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18933 )
    ?? lr {
        F e → ( marki `I-listen-ERR` # i e )
        T listener → {
            ( mark `I3 listening` )
            : ( Channel i ) done ( chan_new [i] )
            : ( @ v ) server \ → v {
                ( mark `I-srv accept_async` )
                : !TcpConn NetErr cr ( tcp_accept_async listener )
                ?? cr {
                    F e → ( mark `I-srv accept ERR` )
                    T c → {
                        ( mark `I-srv accepted, read_chunk_async` )
                        : !( Vec u ) NetErr rd ( tcp_read_chunk_async c 64 )
                        ?? rd {
                            F e → ( mark `I-srv read ERR` )
                            T v → {
                                ( mark `I-srv read ok, write_all_async` )
                                : !v NetErr wr ( tcp_write_all_async c v )
                                ?? wr { T u → = echoed 1 F e → ( mark `I-srv write ERR` ) }
                                ( vec_free [u] v )
                            }
                        }
                        ( tcp_close_conn c )
                        ( mark `I-srv closed` )
                    }
                }
            }
            : ( @ v ) client \ → v {
                ( sleep_ms 50 )
                ( mark `I-cli connect` )
                ?? ( tcp_connect `127.0.0.1` 18933 ) {
                    F e → { ( mark `I-cli connect ERR` ) ( chan_send [i] done 0 ) }
                    T c → {
                        ( mark `I-cli connected, write` )
                        : ( Vec u ) msg ( vec_new [u] )
                        ( vec_push [u] msg # u 104 )
                        ( vec_push [u] msg # u 105 )
                        : !v NetErr wr ( tcp_write_all c msg )
                        ( vec_free [u] msg )
                        ?? wr {
                            F e2 → { ( mark `I-cli write ERR` ) ( tcp_close_conn c ) ( chan_send [i] done 0 ) }
                            T _ → {
                                ( mark `I-cli wrote, read_chunk` )
                                : !( Vec u ) NetErr rd ( tcp_read_chunk c 16 )
                                ?? rd {
                                    T v → {
                                        ( marki `I-cli read_len` ( vec_len [u] v ) )
                                        ? == ( vec_len [u] v ) 2 { = client_match 1 } {}
                                        ( vec_free [u] v )
                                    }
                                    F e3 → ( mark `I-cli read ERR` )
                                }
                                ( tcp_close_conn c )
                                ( chan_send [i] done 1 )
                            }
                        }
                    }
                }
            }
            ( mark `I4 spawn server fiber` )
            ( spawn server )
            ( mark `I5 thread_spawn client` )
            : !Thread ThreadErr ct ( thread_spawn client )
            ( mark `I6 chan_recv (blocks here if the server never serves)` )
            : ?i res ( chan_recv [i] done )
            ?? res { T v → ( marki `I7 client_result` v ) F → ( mark `I7 client_result=closed` ) }
            ( mark `I8 thread_join` )
            ?? ct { T t → ( thread_join t ) F e → {} }
            ( mark `I9 runtime_run` )
            ( runtime_run )
            ( mark `I10 runtime_shutdown` )
            ( runtime_shutdown )
            ( marki `I11 echoed` echoed )
            ( marki `I12 client_match` client_match )
            ( chan_close [i] done )
            ( chan_free [i] done )
            ( tcp_close_listener listener )
            ( mark `I13 done` )
        }
    }
}

@ main → i {
    ( phase_g )
    ( phase_i )
    ( mark `ALL DONE` )
    ^ 0
}
