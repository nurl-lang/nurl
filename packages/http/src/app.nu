// http/app.nu — the ergonomic App facade over the stdlib HTTP stack.
//
// The stdlib already ships a complete HTTP toolkit (net sockets + TLS,
// request parser, response builder, keep-alive server with worker pools
// and DoS limits, router, static-file serving, middleware). What every
// server re-invents is the ~40 lines of glue that wire them together:
// bind → build a router → install a shutdown signal → wrap the handler in
// logging / CORS / panic-recovery → run the keep-alive loop.
//
// `HttpApp` collapses that into one object:
//
//     : *HttpApp a ( http_app_new )
//     ( http_app_get a `/health` \ HttpRequest req Params p → HttpResponse {
//         ^ ( response_text 200 `ok` )
//     } )
//     ( http_app_static_dir a `./static` )     // fallback file serving
//     ( http_app_cors a )
//     ( http_app_logging a )
//     : i rc ( http_app_listen a `127.0.0.1` 8080 )    // blocks; returns exit code
//
// Everything below the App is the untouched stdlib implementation, reached
// through the umbrella include in http.nu — so `HttpRequest`, `HttpResponse`,
// `response_json`, `Router`, `Params`, the auth/jwt/multipart helpers, etc.
// are all in scope for the handler bodies.
//
// Memory model: `http_app_new` returns a heap `*HttpApp` (mutable across the
// registration calls); free it with `http_app_free`. The embedded `Router`
// holds a stable Vec handle, so route registrations through `. a router`
// accumulate correctly. `http_app_listen` MOVES the bound listener into the
// server and stops it on return.

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_static.nu`

: HttpApp {
    Router router
    i idle_ms  // keep-alive idle timeout (ms) for the server
    i workers  // 0 → single-threaded server_run; >0 → server_run_pool(n)
    b use_async  // T → fiber-per-connection server_run_async (see http_app_async)
    i async_workers  // worker pthreads for the fiber runtime; 0 = one per core
    b log_requests  // access log (method/path/status) to stderr
    b cors  // permissive CORS + OPTIONS preflight
    b quiet  // suppress the "serving on host:port" banner
    b has_static  // static fallback enabled
    String webroot  // directory served for unmatched GET/HEAD when has_static
    i body_max  // request body byte cap; -1 → stdlib default (10 MiB)
    i head_max  // request head byte cap; -1 → stdlib default (8 KiB)
    i max_keepalive  // per-conn request reuse cap; -1 → server default (0 = close after one)
    i req_timeout_ms  // per-request wall-clock budget; -1 → server default (0 = disabled)
}

// ── Construction / teardown ───────────────────────────────────────────

@ http_app_new → *HttpApp {
    : *HttpApp a # *HttpApp ( nurl_malloc Z HttpApp )
    = . a router ( router_new )
    = . a idle_ms 5000
    = . a workers 0
    = . a use_async F
    = . a async_workers 0
    = . a log_requests F
    = . a cors F
    = . a quiet F
    = . a has_static F
    = . a webroot ( string_new )
    = . a body_max -1
    = . a head_max -1
    = . a max_keepalive -1
    = . a req_timeout_ms -1
    ^ a
}

@ http_app_free * HttpApp a → v {
    ( router_free . a router )
    ( string_free . a webroot )
    ( nurl_free a )
}

// ── Configuration (each returns v; call before http_app_listen) ───────────

// Serve on a worker pool of `n` threads (0 = single-threaded keep-alive).
// Each worker is pinned to one connection for that connection's whole
// keep-alive lifetime, so at most `n` clients are in flight at once —
// prefer http_app_async for servers that must scale past a handful of
// concurrent connections.
@ http_app_workers * HttpApp a i n → v { = . a workers n }

// Serve fiber-per-connection on the M:N async runtime (server_run_async):
// every accepted connection gets its own fiber, and `n` worker pthreads
// (0 = one per core) multiplex all of them — socket waits park the fiber
// on the reactor instead of pinning a thread, for both plaintext and TLS
// listeners. This is the scaling mode; it overrides http_app_workers.
// Handlers must not assume a bounded number of concurrent invocations.
@ http_app_async * HttpApp a i n → v {
    = . a use_async T
    = . a async_workers n
}

// Keep-alive idle timeout in milliseconds (0 = server default).
@ http_app_idle_ms * HttpApp a i ms → v { = . a idle_ms ms }

// Request body byte cap (parser rejects larger with 413). The stdlib
// default is 10 MiB — raise it for upload endpoints, lower it for
// API-only servers.
@ http_app_body_max * HttpApp a i bytes → v { = . a body_max bytes }

// Request head byte cap (default 8 KiB).
@ http_app_head_max * HttpApp a i bytes → v { = . a head_max bytes }

// Per-connection keep-alive request cap (0 = close after one request).
@ http_app_max_keepalive * HttpApp a i n → v { = . a max_keepalive n }

// Per-request wall-clock budget in ms; overrun sends a stock 504 and
// closes the connection (0 = disabled).
@ http_app_request_timeout * HttpApp a i ms → v { = . a req_timeout_ms ms }

// DEPRECATED (0.3.2): panic→500 is an unconditional guarantee of the
// stdlib server itself — its keep-alive loop wraps every handler call
// (including this facade's whole dispatch + middleware chain) in
// `recover` and answers 500 on panic. The facade used to duplicate
// that wrapper here, which cost a throwaway 500-response build and a
// second `recover` on EVERY request for zero added safety. The knob
// is kept for API compatibility and is a no-op.
@ http_app_recover * HttpApp a b on → v {}

// Log every request (method path → status) to stderr.
@ http_app_logging * HttpApp a → v { = . a log_requests T }

// Permissive CORS: reflect `*`, answer OPTIONS preflight with 204.
@ http_app_cors * HttpApp a → v { = . a cors T }

// Suppress the startup banner on stderr.
@ http_app_quiet * HttpApp a → v { = . a quiet T }

// Serve files from `dir` for any GET/HEAD the router leaves unmatched
// (404). Path traversal is rejected by the underlying serve_static.
@ http_app_static_dir * HttpApp a s dir → v {
    ( string_free . a webroot )
    = . a webroot ( string_from dir )
    = . a has_static T
}

// ── Route registration (thin over the router) ─────────────────────────

@ http_app_get * HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_get . a router pattern handler )
}

@ http_app_post * HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_post . a router pattern handler )
}

@ http_app_put * HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_put . a router pattern handler )
}

@ http_app_patch * HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_patch . a router pattern handler )
}

@ http_app_delete * HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_delete . a router pattern handler )
}

@ http_app_route * HttpApp a s method s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any . a router method pattern handler )
}

// Streaming routes (SSE / NDJSON / chunked). The handler sees every
// request BEFORE the router — return F to fall through to the normal
// routes, or write the whole response itself (response_begin_chunked /
// response_write_chunk / response_end_chunked on the TcpConn) and
// return T; the server then closes the connection when the handler
// returns (a streamed response is that connection's last — do not
// close the conn inside the handler). One hook per process: dispatch
// on `. req path` / `. req method` inside it.
@ http_app_stream * HttpApp a ( @ b TcpConn HttpRequest ) f → v {
    ( server_set_stream f )
}

// The embedded router, for advanced use (mounting sub-routers, tests).
@ http_app_router * HttpApp a → Router { ^ . a router }

// Adopt a pre-built router as the app's router, freeing the default empty
// one. For servers that assemble their routes elsewhere (e.g. a
// `*_service_router → Router` that stays testable without a socket): build
// the router, hand it to the app, and let the facade own the serving glue.
@ http_app_use_router * HttpApp a Router r → v {
    ( router_free . a router )
    = . a router r
}

// ── Dispatch (top-level fns: keeps `recover` out of a nested closure) ──

@ __httpapp_is_get_or_head HttpRequest req → b {
    : s m ( string_data . req method )
    ? != 0 ( nurl_str_eq m `GET` ) { ^ T } {}
    ? != 0 ( nurl_str_eq m `HEAD` ) { ^ T } {}
    ^ F
}

// Router first; on a 404 for GET/HEAD with static enabled, fall through to
// file serving (which itself returns a clean 404 when the file is absent).
@ __httpapp_route_and_static * HttpApp a HttpRequest req → HttpResponse {
    : HttpResponse resp ( router_handle . a router req )
    ? & . a has_static & == 404 . resp status ( __httpapp_is_get_or_head req ) {
        ( http_response_free resp )
        ^ ( serve_static ( string_data . a webroot ) req )
    } {}
    ^ resp
}

// ── Serving ───────────────────────────────────────────────────────────
//
// Panic safety: the stdlib server's keep-alive loop wraps every handler
// invocation (= this facade's full dispatch + middleware chain) in
// `recover` and turns a panic into a 500, so the facade adds no wrapper
// of its own.

@ __httpapp_banner * HttpApp a s scheme s host i port → v {
    ? . a quiet { ^ v } {}
    ( nurl_eprint `http: serving ` )
    ( nurl_eprint scheme )
    ( nurl_eprint `://` )
    ( nurl_eprint host )
    ( nurl_eprint `:` )
    : String ps ( string_new )
    ( string_push_int ps port )
    ( nurl_eprintln ( string_data ps ) )
    ( string_free ps )
}

@ __httpapp_run_result ! v NetErr rr → i {
    ?? rr {
        T _ → { ^ 0 }
        F e → {
            ( nurl_eprint `http: server error: ` )
            ( nurl_eprintln ( net_err_name e ) )
            ^ 1
        }
    }
}

// Resolve the app's limit knobs (-1 = keep the stdlib default) into a
// concrete HttpLimits for the server.
@ __httpapp_limits * HttpApp a → HttpLimits {
    : ~ i bm . a body_max
    ? < bm 0 { = bm ( http_req_body_default_max ) } {}
    : ~ i hm . a head_max
    ? < hm 0 { = hm ( http_req_head_max_bytes ) } {}
    ^ @ HttpLimits { hm ( http_req_header_max_count ) bm }
}

// Drive a bound listener: shutdown signal + composed handler + keep-alive
// loop (pool when workers>0). MOVES `listener`; stops the server on return.
@ __httpapp_serve * HttpApp a TcpListener listener s scheme s host i port → i {
    ( signal_install_shutdown listener )
    // Each middleware layer is held in its own binding so every closure
    // env can be released after the server returns (closures have no
    // drop-glue — envs are manual).
    : ( @ HttpResponse HttpRequest ) disp \ HttpRequest req → HttpResponse { ^ ( __httpapp_route_and_static a req ) }
    : ~ ( @ HttpResponse HttpRequest ) base disp
    : ~ ( @ HttpResponse HttpRequest ) corsw disp
    : ~ b has_cors F
    ? . a cors {
        = corsw ( with_cors_default base )
        = base corsw
        = has_cors T
    } {}
    : ~ ( @ HttpResponse HttpRequest ) logw disp
    : ~ b has_log F
    ? . a log_requests {
        = logw ( with_log_requests base )
        = base logw
        = has_log T
    } {}
    : ~ i ka . a max_keepalive
    ? < ka 0 { = ka ( server_default_max_keepalive_requests ) } {}
    : ~ i rt . a req_timeout_ms
    ? < rt 0 { = rt ( server_default_request_total_timeout_ms ) } {}
    : HttpServer srv ( server_new_complete listener base . a idle_ms ka ( __httpapp_limits a ) rt )
    ( __httpapp_banner a scheme host port )
    : ~ i rc 0
    ? . a use_async {
        ( runtime_init . a async_workers )
        = rc ( __httpapp_run_result ( server_run_async srv ) )
        ( runtime_shutdown )
    } {
        ? > . a workers 0 {
            = rc ( __httpapp_run_result ( server_run_pool srv . a workers ) )
        } {
            = rc ( __httpapp_run_result ( server_run srv ) )
        }
    }
    ( server_stop srv )
    ? has_log { ( nurl_free # s # *u logw 1 ) } {}
    ? has_cors { ( nurl_free # s # *u corsw 1 ) } {}
    ( nurl_free # s # *u disp 1 )
    ^ rc
}

// Bind host:port and serve until the listener is closed (SIGINT/SIGTERM or
// error). Returns a process exit code (0 clean, 1 on bind/serve error).
@ http_app_listen * HttpApp a s host i port → i {
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → { ^ ( __httpapp_serve a listener `http` host port ) }
        F e → {
            ( nurl_eprint `http: cannot bind ` )
            ( nurl_eprint host )
            ( nurl_eprint `:` )
            : String ps ( string_new )
            ( string_push_int ps port )
            ( nurl_eprint ( string_data ps ) )
            ( nurl_eprint ` — ` )
            ( nurl_eprintln ( net_err_name e ) )
            ( string_free ps )
            ^ 1
        }
    }
}

// Same, over TLS. `cert`/`key` are PEM paths (EC or RSA leaf; a fullchain
// PEM is accepted for `cert`).
@ http_app_listen_tls * HttpApp a s host i port s cert s key → i {
    // Advertise HTTP/2 and HTTP/1.1 over ALPN (RFC 7301), h2 preferred:
    // an HTTP/2-capable client (browsers, curl, oha) gets HTTP/2, anything
    // else HTTP/1.1, over the same listener and the same routes. The
    // server itself tells the protocols apart by the connection preface,
    // so this is the only HTTP/2-specific line in the facade.
    : !TcpListener NetErr lr ( tcp_listen_tls_with_alpn host port 128 cert key `h2 http/1.1` )
    ?? lr {
        T listener → { ^ ( __httpapp_serve a listener `https` host port ) }
        F e → {
            ( nurl_eprint `http: cannot bind TLS ` )
            ( nurl_eprint host )
            ( nurl_eprint `:` )
            : String ps ( string_new )
            ( string_push_int ps port )
            ( nurl_eprint ( string_data ps ) )
            ( nurl_eprint ` — ` )
            ( nurl_eprintln ( net_err_name e ) )
            ( string_free ps )
            ^ 1
        }
    }
}
