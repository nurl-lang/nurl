// http_server_pool.nu — Phase 5.3 acceptance test for
// stdlib/ext/http_server.nu's server_run_pool.
//
// Live test (NURL_NET_TESTS=1) verifies the spawn / accept-loop /
// shutdown / join lifecycle on the loopback. We don't shell out to
// curl here — http_server_seq.nu already covers the end-to-end
// request/response round-trip on the single-threaded path; this test
// focuses on the threading harness:
//
//   1. Listen on 127.0.0.1:18799.
//   2. Spawn a "shutdown" thread that sleeps 200 ms then SOFT-closes
//      the listener (`tcp_shutdown_listener` — closes the socket but
//      keeps the runtime struct alive so workers waking from accept
//      don't use-after-free on `h->err_kind`).
//   3. Call server_run_pool with 4 workers. It blocks until every
//      worker thread joins, then returns Ok(0).
//   4. Print the outcome, then `server_stop` actually frees the
//      listener struct (no thread is still reading it by this point).
//
// Known limitation (Phase 8 follow-up): on Windows the
// closesocket-from-one-thread + accept-blocked-on-another race can
// occasionally trigger an at-exit SIGSEGV inside the C runtime's
// final cleanup (~10–40% of runs in stress loops). The pool itself
// exits cleanly — "pool: clean shutdown" always prints first. A
// proper barrier-based graceful shutdown lives in Phase 8.
//
// Default (NURL_NET_TESTS unset): just prints the skip notice — the
// pool function is exercised purely at compile + link time, so the
// fact that this file appears in run_tests' baseline at all proves
// the compiler accepted the closure-capture-of-HttpServer pattern
// and the runtime symbols all link.

$ `stdlib/ext/http_server.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

@ run_live_pool_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18799 16 )
    ?? lr {
        F e → {
            ( nurl_print `listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
        T listener → {
            // Capture the listener by VALUE so the shutdown thread can
            // soft-close the kernel FD while the runtime struct stays
            // alive for worker threads to safely return from accept.
            : TcpListener lst @ TcpListener { . listener raw }
            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse {
                ^ ( response_text 200 `ok\n` )
            }
            : HttpServer srv ( server_new listener handler )

            : ( @ v ) shutdown \ → v {
                ( sleep_ms 200 )
                ( tcp_shutdown_listener lst )
            }
            : !Thread ThreadErr st ( thread_spawn shutdown )
            ?? st {
                T t → {
                    : !v NetErr rp ( server_run_pool srv 4 )
                    ?? rp {
                        T _ → { ( nurl_print `pool: clean shutdown\n` ) }
                        F e → {
                            ( nurl_print `pool: ` )
                            ( nurl_print ( net_err_name e ) )
                            ( nurl_print `\n` )
                        }
                    }
                    ( thread_join t )
                    ( server_stop srv )  // Final free — no thread is still reading h.
                    // Release the shutdown closure's heap-captured env now
                    // that its thread has joined (thread_spawn borrows it).
                    : *u shutdown_env # *u shutdown 1
                    ( nurl_free # s shutdown_env )
                }
                F e → {
                    ( nurl_print `shutdown thread spawn failed: ` )
                    ( nurl_print ( thread_err_name e ) )
                    ( nurl_print `\n` )
                    ( server_stop srv )
                }
            }
        }
    }
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_live_pool_test )
        }
        F → { ( nurl_print `live pool test skipped (set NURL_NET_TESTS=1 to enable)\n` ) }
    }
    ^ 0
}
