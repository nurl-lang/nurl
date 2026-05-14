// examples/static_server.nu — production-style static file server.
//
// One-file demo that exercises the full HTTP server stack shipped
// through Phases 1, 4, 6, 7 and 8 of HTTP_SERVER_PLAN.md:
//
//     tcp_listen / server_new / server_run         (Phase 1 + 4)
//     router_get + named/wildcard captures         (Phase 6)
//     serve_static + mime_for_ext                  (Phase 7)
//     with_cors_default                            (Phase 6 helper)
//     with_metrics + metrics_handler               (Phase 8)
//     with_access_log                              (Phase 8)
//     signal_install_shutdown (Ctrl+C / SIGTERM)   (Phase 8)
//
// Build & run:
//
//     ./build.sh                # or .\build.bat on Windows
//     ./nurl.sh examples/static_server.nu
//
// Probe from another terminal:
//
//     curl -i http://127.0.0.1:18080/                 # public/index.html
//     curl -i http://127.0.0.1:18080/api/health       # JSON
//     curl -i http://127.0.0.1:18080/metrics          # Prometheus text
//     curl -i http://127.0.0.1:18080/../etc/passwd    # 403 (path traversal)
//     curl -i http://127.0.0.1:18080/no-such-file     # 404
//
//     # Then Ctrl+C in the server's terminal — server prints
//     # "static server: clean shutdown" and exits with status 0.
//
// On first run the server creates `./public/index.html` so a fresh
// checkout has something to serve. Drop your own files into `./public/`
// (CSS, images, etc.) — `serve_static` figures the Content-Type out
// from the extension and reads the file off disk per request.

// One-line batteries-included pull-in. `http_full.nu` aggregates the
// whole HTTP stack — request parser, response builder, server,
// router, static, auth, cookies, middleware, multipart, signals,
// HTTP client. Per-module includes like `$ \`stdlib/ext/http_server.nu\``
// still work for callers who want a leaner include surface.
$ `stdlib/ext/http_full.nu`
$ `stdlib/std/fs.nu`

// ── Boot-time setup ──────────────────────────────────────────────────
//
// Plant a tiny index.html under ./public on first run so the example
// has something to demonstrate without checking files into the repo.
// Errors are tolerated — if the directory already exists or can't be
// written, we proceed and let serve_static's 404 path handle it.

@ setup_public_dir → v {
    ? ! ( file_exists `public/index.html` ) {
        : !v IoErr dr ( dir_create `public` )
        ?? dr { T → {} F _ → {} }
        : s body `<!doctype html>\n<html><head><meta charset="utf-8"><title>NURL static server</title></head>\n<body>\n<h1>NURL static server is running.</h1>\n<p>Try <a href="/api/health">/api/health</a> or <a href="/metrics">/metrics</a>.</p>\n<p>Drop more files into <code>./public/</code> and refresh.</p>\n</body></html>\n`
        : !v IoErr wr ( write_file `public/index.html` body )
        ?? wr {
            T → { ( nurl_eprint `[boot] wrote public/index.html\n` ) }
            F _ → { ( nurl_eprint `[boot] could not write public/index.html (continuing)\n` ) }
        }
    } {}
}

// ── Route handlers ───────────────────────────────────────────────────

@ h_health HttpRequest req Params params → HttpResponse {
    // Start from the text-response shape, then override Content-Type.
    // `response_set_header` deduplicates by name (case-insensitive), so
    // the second call REPLACES the `text/plain` default rather than
    // appending a duplicate header.
    : HttpResponse r ( response_text 200 `{"ok":true,"server":"nurl-static-demo"}\n` )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ^ r
}

// `/` and `/*path` both fall through to serve_static. The router only
// passes the request along — serve_static reads `req.path` itself,
// strips the leading '/', joins under `public/`, rejects `..`
// segments, picks Content-Type from the extension, returns 404 if the
// file is missing.
@ h_static HttpRequest req Params params → HttpResponse {
    ^ ( serve_static `public` req )
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
    ( setup_public_dir )

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18080 )
    ?? lr {
        T listener → {
            // Counter bag — captured by `with_metrics` AND by the
            // `/metrics` route handler. Both keep the same handle alive.
            : Metrics m ( metrics_new )

            // Router build-up.
            : Router r ( router_new )

            ( router_get r `/metrics`
            \ HttpRequest req Params params → HttpResponse { ^ ( metrics_handler m req ) } )

            ( router_get r `/api/health`
            \ HttpRequest req Params params → HttpResponse { ^ ( h_health req params ) } )

            // Static fallback — `/` first so it picks up index.html, then
            // `/*path` for any deeper file under public/.
            ( router_get r `/`
            \ HttpRequest req Params params → HttpResponse { ^ ( h_static req params ) } )
            ( router_get r `/*path`
            \ HttpRequest req Params params → HttpResponse { ^ ( h_static req params ) } )

            // Middleware compose, innermost-first:
            //     base    →  router_handle (dispatch)
            //     cors    →  CORS headers + OPTIONS preflight
            //     metered →  Prometheus counters update
            //     logged  →  one stderr line per request
            // The OUTERMOST wrapper (`logged`) is what the server sees.
            : ( @ HttpResponse HttpRequest ) base
            \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }
            : ( @ HttpResponse HttpRequest ) cors ( with_cors_default base )
            : ( @ HttpResponse HttpRequest ) metered ( with_metrics m cors )
            : ( @ HttpResponse HttpRequest ) logged ( with_access_log metered )

            // Wire Ctrl+C / SIGTERM to a clean listener shutdown. Must come
            // AFTER tcp_listen so the runtime sees a valid handle.
            ( signal_install_shutdown listener )

            ( nurl_print `static server listening on http://127.0.0.1:18080/\n` )
            ( nurl_print `  • /                  → public/index.html\n` )
            ( nurl_print `  • /<path>            → public/<path>\n` )
            ( nurl_print `  • /api/health        → JSON\n` )
            ( nurl_print `  • /metrics           → Prometheus text-exposition\n` )
            ( nurl_print `Ctrl+C to shut down cleanly.\n` )

            : HttpServer srv ( server_new listener logged )
            : !v NetErr rr ( server_run srv )

            // Cleanup. Order matters — clear the signal slot first so a
            // late signal doesn't dereference a freed listener handle, then
            // free everything else.
            ( signal_clear_shutdown )
            ( server_stop srv )
            ( router_free r )
            ( metrics_free m )

            ?? rr {
                T _ → {
                    ( nurl_print `static server: clean shutdown\n` )
                    ^ 0
                }
                F e → {
                    ( nurl_eprint `[srv] runtime error: ` )
                    ( nurl_eprint ( net_err_name e ) )
                    ( nurl_eprint `\n` )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `[boot] could not bind 127.0.0.1:18080: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
