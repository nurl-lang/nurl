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
    i idle_ms          // keep-alive idle timeout (ms) for server_new_with_timeout
    i workers          // 0 → single-threaded server_run; >0 → server_run_pool(n)
    b recover_panics   // wrap dispatch in `recover`, turning a panic into 500
    b log_requests     // access log (method/path/status) to stderr
    b cors             // permissive CORS + OPTIONS preflight
    b quiet            // suppress the "serving on host:port" banner
    b has_static       // static fallback enabled
    String webroot     // directory served for unmatched GET/HEAD when has_static
}

// ── Construction / teardown ───────────────────────────────────────────

@ http_app_new → *HttpApp {
    : *HttpApp a # *HttpApp ( nurl_malloc Z HttpApp )
    = . a router ( router_new )
    = . a idle_ms 5000
    = . a workers 0
    = . a recover_panics T
    = . a log_requests F
    = . a cors F
    = . a quiet F
    = . a has_static F
    = . a webroot ( string_new )
    ^ a
}

@ http_app_free *HttpApp a → v {
    ( router_free . a router )
    ( string_free . a webroot )
    ( nurl_free a )
}

// ── Configuration (each returns v; call before http_app_listen) ───────────

// Serve on a worker pool of `n` threads (0 = single-threaded keep-alive).
@ http_app_workers *HttpApp a i n → v { = . a workers n }

// Keep-alive idle timeout in milliseconds (0 = server default).
@ http_app_idle_ms *HttpApp a i ms → v { = . a idle_ms ms }

// Toggle panic→500 recovery (on by default). A handler that panics then
// yields a 500 instead of tearing down the connection loop.
@ http_app_recover *HttpApp a b on → v { = . a recover_panics on }

// Log every request (method path → status) to stderr.
@ http_app_logging *HttpApp a → v { = . a log_requests T }

// Permissive CORS: reflect `*`, answer OPTIONS preflight with 204.
@ http_app_cors *HttpApp a → v { = . a cors T }

// Suppress the startup banner on stderr.
@ http_app_quiet *HttpApp a → v { = . a quiet T }

// Serve files from `dir` for any GET/HEAD the router leaves unmatched
// (404). Path traversal is rejected by the underlying serve_static.
@ http_app_static_dir *HttpApp a s dir → v {
    ( string_free . a webroot )
    = . a webroot ( string_from dir )
    = . a has_static T
}

// ── Route registration (thin over the router) ─────────────────────────

@ http_app_get *HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_get . a router pattern handler )
}
@ http_app_post *HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_post . a router pattern handler )
}
@ http_app_put *HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_put . a router pattern handler )
}
@ http_app_patch *HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_patch . a router pattern handler )
}
@ http_app_delete *HttpApp a s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_delete . a router pattern handler )
}
@ http_app_route *HttpApp a s method s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any . a router method pattern handler )
}

// The embedded router, for advanced use (mounting sub-routers, tests).
@ http_app_router *HttpApp a → Router { ^ . a router }

// Adopt a pre-built router as the app's router, freeing the default empty
// one. For servers that assemble their routes elsewhere (e.g. a
// `*_service_router → Router` that stays testable without a socket): build
// the router, hand it to the app, and let the facade own the serving glue.
@ http_app_use_router *HttpApp a Router r → v {
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
@ __httpapp_route_and_static *HttpApp a HttpRequest req → HttpResponse {
    : HttpResponse resp ( router_handle . a router req )
    ? & . a has_static & == 404 . resp status ( __httpapp_is_get_or_head req ) {
        ( http_response_free resp )
        ^ ( serve_static ( string_data . a webroot ) req )
    } {}
    ^ resp
}

// Optional panic→500 wrapper. `recover` sits directly in this top-level
// function body (not inside another closure), the shape the runtime wants.
@ __httpapp_dispatch *HttpApp a HttpRequest req → HttpResponse {
    ? . a recover_panics {
        : ~ HttpResponse resp ( response_text 500 `internal error: handler panicked\n` )
        : !v PanicInfo pr ( recover \ → v { = resp ( __httpapp_route_and_static a req ) } )
        ?? pr { T _ → {} F p → { ( panic_info_free p ) } }
        ^ resp
    } {
        ^ ( __httpapp_route_and_static a req )
    }
}

// ── Serving ───────────────────────────────────────────────────────────

@ __httpapp_banner *HttpApp a s scheme s host i port → v {
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

@ __httpapp_run_result !v NetErr rr → i {
    ?? rr {
        T _ → { ^ 0 }
        F e → {
            ( nurl_eprint `http: server error: ` )
            ( nurl_eprintln ( net_err_name e ) )
            ^ 1
        }
    }
}

// Drive a bound listener: shutdown signal + composed handler + keep-alive
// loop (pool when workers>0). MOVES `listener`; stops the server on return.
@ __httpapp_serve *HttpApp a TcpListener listener s scheme s host i port → i {
    ( signal_install_shutdown listener )
    : ~ ( @ HttpResponse HttpRequest ) base \ HttpRequest req → HttpResponse { ^ ( __httpapp_dispatch a req ) }
    ? . a cors { = base ( with_cors_default base ) } {}
    ? . a log_requests { = base ( with_log_requests base ) } {}
    : HttpServer srv ( server_new_with_timeout listener base . a idle_ms )
    ( __httpapp_banner a scheme host port )
    : ~ i rc 0
    ? > . a workers 0 {
        = rc ( __httpapp_run_result ( server_run_pool srv . a workers ) )
    } {
        = rc ( __httpapp_run_result ( server_run srv ) )
    }
    ( server_stop srv )
    ^ rc
}

// Bind host:port and serve until the listener is closed (SIGINT/SIGTERM or
// error). Returns a process exit code (0 clean, 1 on bind/serve error).
@ http_app_listen *HttpApp a s host i port → i {
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
@ http_app_listen_tls *HttpApp a s host i port s cert s key → i {
    : !TcpListener NetErr lr ( tcp_listen_tls host port cert key )
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
