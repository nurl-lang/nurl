// async_http_server.nu — Phase 7 fiber-driven HTTP server smoke test.
//
// One `server_run_async` listens on loopback; a separate pthread
// connects with the existing blocking client API, sends a GET, reads
// the response, then triggers `server_stop` so the accept fiber
// exits cleanly. Validates:
//   * `server_run_async` is a drop-in replacement for `server_run` /
//     `server_run_pool` — same `HttpServer` handle, same async_test_handler
//     contract
//   * `tcp_accept` / `tcp_read_chunk` / `tcp_write_all` transparently
//     park on the reactor when called from inside the fiber-driven
//     accept + async_test_handler fibers (no `tcp_*_async` changes in the
//     async_test_handler-layer code)
//   * `server_stop` propagates through the listener → NetClosed →
//     accept-fiber exit → runtime drains pending conn fibers →
//     `server_run_async` returns
//   * Opens a loopback socket and pairs a fiber-side server with a
//     blocking client, hence `requires: live fibers` — on a platform
//     where `spawn` is stubbed the client waits for a peer that never
//     runs, so this one must not run there at all.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/core/string.nu`

& `libc` @ nurl_tcp_connect s host i port → i

: ~ i client_ok 0

@ async_test_handler HttpRequest r → HttpResponse {
    ^ ( response_text 200 `hello async\n` )
}

@ run_async_http_test → v {
    ( runtime_init 4 )

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18920 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) async_test_handler_cl \ HttpRequest req → HttpResponse { ^ ( async_test_handler req ) }
            : HttpServer srv ( server_new listener async_test_handler_cl )
            : ( Channel i ) done ( chan_new [i] )

            : ( @ v ) client \ → v {
                ( sleep_ms 200 )
                : i craw ( nurl_tcp_connect `127.0.0.1` 18920 )
                ? != craw 0 {
                    : i ek ( nurl_tcp_err_kind craw )
                    ? == ek 0 {
                        : s req `GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n`
                        : i reqlen ( nurl_str_len req )
                        : i wn ( nurl_tcp_write craw req reqlen )
                        ? == wn reqlen {
                            : s buf ( nurl_alloc 4096 )
                            : i rdn ( nurl_tcp_read craw buf 4095 )
                            ? > rdn 0 {
                                = client_ok 1
                            } {}
                            ( nurl_free buf )
                        } {}
                        ( nurl_tcp_close craw )
                    } {
                        ( nurl_tcp_close craw )
                    }
                } {}
                ( server_stop srv )
                ( chan_send [i] done 1 )
            }
            : !Thread ThreadErr ct ( thread_spawn client )

            : !v NetErr sr ( server_run_async srv )
            ?? sr {
                T _ → { ( nurl_print `server_run=ok\n` ) }
                F e → {
                    ( nurl_print `server_run=` )
                    ( nurl_print ( net_err_name e ) )
                    ( nurl_print `\n` )
                }
            }

            : ?i d ( chan_recv [i] done )
            ?? d { T _ → {} F → {} }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }

            // The client thread has joined and server_run_async has
            // returned (all fibers drained), so both closures' heap-
            // captured envs are now dead — release them (spawn /
            // thread_spawn borrow the env; they never free it).
            : *u client_env # *u client 1
            ( nurl_free # s client_env )
            : *u handler_env # *u async_test_handler_cl 1
            ( nurl_free # s handler_env )

            ( nurl_print `client_ok=` )
            ( nurl_print ( nurl_str_int client_ok ) )
            ( nurl_print `\n` )

            ( runtime_shutdown )
            ( chan_close [i] done )
            ( chan_free [i] done )
        }
        F e → {
            ( nurl_print `listen fail: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    ( run_async_http_test )
    ^ 0
}
