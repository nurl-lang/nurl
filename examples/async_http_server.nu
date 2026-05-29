// examples/async_http_server.nu — fiber-driven HTTP server demo.
//
// Same handler contract as `examples/static_server.nu`, but runs the
// accept loop and every per-connection keep-alive loop on stackful
// fibers via the Phase 7 async runtime. Each accepted connection
// becomes a fiber; the M:N work-stealing scheduler distributes them
// across N worker pthreads (default = sysconf(_SC_NPROCESSORS_ONLN),
// override with NURL_WORKERS env). Slow handlers no longer pin a
// worker — `tcp_read_chunk` and `tcp_write_all` park the fiber on
// the reactor when the kernel returns EAGAIN, and a different
// fiber's work runs in the meantime.
//
// Build:
//   ./nurl.sh examples/async_http_server.nu
//
// Test:
//   curl -i http://localhost:8082/
//   curl -i http://localhost:8082/api/health
//   ab -c 100 -n 10000 http://localhost:8082/api/health    # benchmark
//
// Shutdown: send SIGINT (Ctrl+C) or SIGTERM — the signal handler
// closes the listener; the accept fiber exits; `runtime_run` drains
// every in-flight connection fiber; `runtime_shutdown` joins the
// worker pool cleanly. No connection is dropped mid-flight.

$ `stdlib/std/async.nu`
$ `stdlib/ext/http_full.nu`
$ `stdlib/std/fs.nu`

@ health_handler HttpRequest req Params params → HttpResponse {
    ^ ( response_text 200 `{"status":"ok"}\n` )
}

@ root_handler HttpRequest req Params params → HttpResponse {
    ^ ( response_text 200 `nurl async server — stackful fibers + M:N work-stealing\n` )
}

@ main → i {
    // 1. Initialise the async runtime. 0 = pick a sensible default
    //    worker count from NURL_WORKERS / sysconf.
    ( runtime_init 0 )

    // 2. Bind a listener on loopback:8082.
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 8082 )
    ?? lr {
        T listener → {
            // 3. Router — two routes, both wrapped as closure literals
            //    (bare `@`-fn names don't auto-coerce to `( @ R P P )`).
            : Router r ( router_new )
            ( router_get r `/`
            \ HttpRequest req Params params → HttpResponse { ^ ( root_handler req params ) } )
            ( router_get r `/api/health`
            \ HttpRequest req Params params → HttpResponse { ^ ( health_handler req params ) } )

            // Middleware compose, innermost-first — same shape as the
            // sync `examples/static_server.nu`.
            : Metrics mtr ( metrics_new )
            : ( @ HttpResponse HttpRequest ) base
            \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }
            : ( @ HttpResponse HttpRequest ) metered ( with_metrics mtr base )
            : ( @ HttpResponse HttpRequest ) logged ( with_access_log metered )

            : HttpServer srv ( server_new listener logged )

            // 4. SIGINT/SIGTERM/Ctrl+C: close the listener, which
            //    makes the accept fiber exit naturally.
            ( signal_install_shutdown listener )

            ( nurl_print `nurl async HTTP server listening on http://127.0.0.1:8082/\n` )
            ( nurl_print `  routes: / and /api/health\n` )
            ( nurl_print `  workers: ` )
            ( nurl_print ( nurl_str_int ( nurl_fiber_worker_id ) ) )
            ( nurl_print ` (id from main; -1 = not on a fiber)\n` )

            // 5. Hand off to the async runtime. Returns when the
            //    accept loop exits AND every conn fiber drains.
            : !v NetErr rr ( server_run_async srv )
            ?? rr {
                T _ → { ( nurl_print `server exited cleanly\n` ) }
                F e → {
                    ( nurl_print `server exit: ` )
                    ( nurl_print ( net_err_name e ) )
                    ( nurl_print `\n` )
                }
            }

            ( runtime_shutdown )
            ( tcp_close_listener listener )
            ( metrics_free mtr )
            ( router_free r )
        }
        F e → {
            ( nurl_print `bind failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
    }
    ^ 0
}
