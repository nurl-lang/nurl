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
//     : HttpApp a ( http_app_new )
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
// Memory model: `http_app_new` returns an `HttpApp` handle (mutable across
// the registration calls); every copy of it is the same app, and its last
// owner releases it — nothing to free (`http_app_free` is an optional early
// release). The embedded `Router` holds a stable Vec handle, so route
// registrations through `. a router` accumulate correctly. `http_app_listen`
// MOVES the bound listener into the server and stops it on return.

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_static.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/ext/http3_server.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: HttpAppImpl {
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
    i max_keepalive  // per-conn request reuse cap; -1 → per-mode default (0 = close after one)
    i req_timeout_ms  // per-request wall-clock budget; -1 → server default (0 = disabled)
    i drain_ms  // on SIGTERM/SIGINT: drain deadline in ms (server_drain); 0 = stop at once
    i http3  // 1 → a TLS listener also serves HTTP/3 on the same port over UDP (default)
    String pq_cert  // optional second identity for TLS listeners: ML-DSA chain PEM ("" = none)
    String pq_key  // ...and its PKCS#8 key PEM
    // Zero or one user middleware: a function from the app's own
    // dispatch to the handler actually served. A ( Vec ) so that "none"
    // and "one" stay apart and so `http_app_use` reaches every copy of
    // the handle (see McpMiddleware).
    ( Vec HttpMiddleware ) mw
}

// An HttpApp is a handle on its state in an Rc (stdlib/std/rc.nu), built
// on one thread: every copy is the same state, and the last owner
// releases it — the router, the strings and the middleware are dropped
// with it. A setter checks the state out (rc_take) and back in; serving
// hands the workers a frozen snapshot of what dispatch reads.
: HttpApp { ( Rc HttpAppImpl ) a }

@ HttpApp_share HttpApp h → HttpApp { ^ @ HttpApp { ( rc_clone [HttpAppImpl] . h a ) } }

@ HttpApp_drop sink HttpApp h → v {}

// A user middleware, boxed so it can live in a Vec — a closure is not
// spellable as a generic type argument.
: HttpMiddleware {
    ( @ ( @ HttpResponse HttpRequest ) ( @ HttpResponse HttpRequest ) ) f
}

// ── Construction / teardown ───────────────────────────────────────────

@ http_app_new → HttpApp {
    ^ @ HttpApp { ( rc_new [HttpAppImpl] @ HttpAppImpl {
            ( router_new ) 5000 0 F 0 F F F F ( string_new ) -1 -1 -1 -1 10000 1 ( string_new ) ( string_new )
            ( vec_new [HttpMiddleware] ) } ) }
}

// Let go of `a` now rather than at the end of its owner's scope.
@ http_app_free sink HttpApp a → v {}

// ── Configuration (each returns v; call before http_app_listen) ───────────

// Wrap the app's whole dispatch — routing, static fallback and all — in
// a handler of your own. The facade's built-in layers (CORS, the access
// log, Alt-Svc) go OUTSIDE this one, so a request reaches:
//
//   [alt-svc] → [log] → [cors] → YOUR middleware → route / static
//
// The argument is the app's dispatch; return the handler to serve
// instead, and call the argument wherever you want the app to run:
//
//   ( http_app_use a \ ( @ HttpResponse HttpRequest ) inner
//     → ( @ HttpResponse HttpRequest ) {
//       ^ \ HttpRequest req → HttpResponse {
//           ? ( heavy req ) { ( sem_acquire gate ) } {}
//           : HttpResponse r ( inner req )
//           ? ( heavy req ) { ( sem_release gate ) } {}
//           ^ r
//       }
//   } )
//
// This is the seam the facade was missing. Without it a server that
// needs anything the built-in layers do not do — a concurrency gate in
// front of an expensive route, a per-IP budget, an auth check — has to
// abandon the facade and hand-wire router + server + shutdown itself,
// which is the ~40 lines the facade exists to remove. nurlapi did
// exactly that, for one semaphore.
//
// One middleware. A second call replaces the first: middleware chains
// grow ordering questions faster than they earn them, and a chain is
// already expressible by composing inside the one closure.
//
// The app keeps its own copy of the wrapper (a stored closure is a
// clone), and the handler it RETURNS is the facade's, released with its
// own layers — nothing to free on either side.
@ http_app_use HttpApp a__h ( @ ( @ HttpResponse HttpRequest ) ( @ HttpResponse HttpRequest ) ) f → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( vec_clear [HttpMiddleware] . a mw )
    ( vec_push [HttpMiddleware] . a mw @ HttpMiddleware { f } )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Serve on a worker pool of `n` threads (0 = single-threaded keep-alive).
// Each worker is pinned to one connection for that connection's whole
// keep-alive lifetime, so at most `n` clients are in flight at once —
// prefer http_app_async for servers that must scale past a handful of
// concurrent connections.
@ http_app_workers HttpApp a__h i n → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a workers n
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// HTTP/3 on TLS listeners: on by default. `http_app_set_http3 a 0` keeps
// a TLS listener TCP-only (no UDP socket, no Alt-Svc).
@ http_app_set_http3 HttpApp a__h i on → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a http3 on
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// A second, post-quantum identity for `http_app_listen_tls`: an ML-DSA
// (44 / 65 / 87) certificate chain and PKCS#8 key, served BESIDE the
// classical pair the listen call takes. Which one a connection is shown
// is decided per ClientHello from the client's signature_algorithms
// (RFC 8446 §4.4.2.2): the ML-DSA leaf for every client that lists its
// scheme, the classical leaf for the rest — so deploying a post-quantum
// certificate never turns a client away. Applies to HTTP/1.1, HTTP/2 and
// HTTP/3 alike (the QUIC handshake is the same TLS 1.3 code). Mint a
// self-signed pair with `x509_selfsigned_mldsa` (std/x509_gen.nu) or the
// pki-server package; no public CA issues ML-DSA certificates yet.
//
// To serve ONLY an ML-DSA certificate, hand it to `http_app_listen_tls`
// directly — the key form is auto-detected.
@ http_app_set_pq_cert HttpApp a__h s cert s key → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a pq_cert ( string_from cert )
    = . a pq_key ( string_from key )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Serve fiber-per-connection on the M:N async runtime (server_run_async):
// every accepted connection gets its own fiber, and `n` worker pthreads
// (0 = one per core) multiplex all of them — socket waits park the fiber
// on the reactor instead of pinning a thread, for both plaintext and TLS
// listeners. This is the scaling mode; it overrides http_app_workers.
// Handlers must not assume a bounded number of concurrent invocations.
@ http_app_async HttpApp a__h i n → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a use_async T
    = . a async_workers n
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Keep-alive idle timeout in milliseconds (0 = server default).
@ http_app_idle_ms HttpApp a__h i ms → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a idle_ms ms
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Request body byte cap (parser rejects larger with 413). The stdlib
// default is 10 MiB — raise it for upload endpoints, lower it for
// API-only servers.
@ http_app_body_max HttpApp a__h i bytes → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a body_max bytes
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Request head byte cap (default 8 KiB).
@ http_app_head_max HttpApp a__h i bytes → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a head_max bytes
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Per-connection keep-alive request cap (0 = close after one request).
// Unset, the cap depends on how the app serves: 1000 for the thread
// servers (single-threaded and http_app_workers), where a connection
// holds a whole worker; none for http_app_async, where it holds only a
// fiber and the idle timeout (http_app_idle_ms) is the bound.
@ http_app_max_keepalive HttpApp a__h i n → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a max_keepalive n
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Graceful shutdown on SIGTERM / SIGINT (stdlib server_drain): the
// listener closes, idle keep-alive connections close at once, requests in
// flight finish and go out with `Connection: close` (HTTP/2: GOAWAY), and
// the app waits up to `ms` for the last of them before closing the rest.
// Default 10000; 0 stops at once, dropping requests in flight.
@ http_app_drain_ms HttpApp a__h i ms → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a drain_ms ? < ms 0 0 ms
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Per-request wall-clock budget in ms; overrun sends a stock 504 and
// closes the connection (0 = disabled).
@ http_app_request_timeout HttpApp a__h i ms → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a req_timeout_ms ms
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// DEPRECATED (0.3.2): panic→500 is an unconditional guarantee of the
// stdlib server itself — its keep-alive loop wraps every handler call
// (including this facade's whole dispatch + middleware chain) in
// `recover` and answers 500 on panic. The facade used to duplicate
// that wrapper here, which cost a throwaway 500-response build and a
// second `recover` on EVERY request for zero added safety. The knob
// is kept for API compatibility and is a no-op.
@ http_app_recover HttpApp a b on → v {}

// Log every request (method path → status) to stderr.
@ http_app_logging HttpApp a__h → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a log_requests T
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Permissive CORS: reflect `*`, answer OPTIONS preflight with 204.
@ http_app_cors HttpApp a__h → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a cors T
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Suppress the startup banner on stderr.
@ http_app_quiet HttpApp a__h → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a quiet T
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Serve files from `dir` for any GET/HEAD the router leaves unmatched
// (404). Path traversal is rejected by the underlying serve_static.
@ http_app_static_dir HttpApp a__h s dir → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a webroot ( string_from dir )
    = . a has_static T
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// ── Route registration (thin over the router) ─────────────────────────

@ http_app_get HttpApp a__h s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_get . a router pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

@ http_app_post HttpApp a__h s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_post . a router pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

@ http_app_put HttpApp a__h s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_put . a router pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

@ http_app_patch HttpApp a__h s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_patch . a router pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

@ http_app_delete HttpApp a__h s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_delete . a router pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

@ http_app_route HttpApp a__h s method s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    ( router_any . a router method pattern handler )
    ( rc_restore [HttpAppImpl] . a__h a a )
}

// Streaming routes (SSE / NDJSON / chunked). The handler sees every
// request BEFORE the router — return F to fall through to the normal
// routes, or write the whole response itself (response_begin_chunked /
// response_write_chunk / response_end_chunked on the TcpConn) and
// return T; the server then closes the connection when the handler
// returns (a streamed response is that connection's last — do not
// close the conn inside the handler). One hook per process: dispatch
// on `. req path` / `. req method` inside it.
@ http_app_stream HttpApp a ( @ b TcpConn HttpRequest ) f → v {
    ( server_set_stream f )
}

// The embedded router, for advanced use (mounting sub-routers, tests):
// another handle on the same routes.
@ http_app_router HttpApp a__h → Router {
    ^ ( mem_dup . ( rc_get [HttpAppImpl] . a__h a ) router )
}

// Adopt a pre-built router as the app's router, releasing the default
// empty one. For servers that assemble their routes elsewhere (e.g. a
// `*_service_router → Router` that stays testable without a socket): build
// the router, hand it to the app, and let the facade own the serving glue.
@ http_app_use_router HttpApp a__h Router r → v {
    : ~ HttpAppImpl a ( rc_take [HttpAppImpl] . a__h a )
    = . a router r
    ( rc_restore [HttpAppImpl] . a__h a a )
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
// What dispatch reads while the app serves: a snapshot, frozen in an Arc
// the workers share (the routes are handles on the app's own).
: HttpDispatch { Router router b has_static String webroot }

@ __httpapp_route_and_static ( Arc HttpDispatch ) d HttpRequest req → HttpResponse {
    : HttpDispatch c ( arc_get [HttpDispatch] d )
    : HttpResponse resp ( router_handle . c router req )
    ? & . c has_static & == 404 . resp status ( __httpapp_is_get_or_head req ) {
        ( http_response_free resp )
        ^ ( serve_static ( string_data . c webroot ) req )
    } {}
    ^ resp
}

// ── Serving ───────────────────────────────────────────────────────────
//
// Panic safety: the stdlib server's keep-alive loop wraps every handler
// invocation (= this facade's full dispatch + middleware chain) in
// `recover` and turns a panic into a 500, so the facade adds no wrapper
// of its own.

@ __httpapp_banner HttpAppImpl a s scheme s host i port → v {
    ? . a quiet { ^ v } {}
    ( nurl_eprint `http: serving ` )
    ( nurl_eprint scheme )
    ( nurl_eprint `://` )
    ( nurl_eprint host )
    ( nurl_eprint `:` )
    : String ps ( string_new )
    ( string_push_int ps port )
    ( nurl_eprintln ( string_data ps ) )
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
@ __httpapp_limits HttpAppImpl a → HttpLimits {
    : ~ i bm . a body_max
    ? < bm 0 { = bm ( http_req_body_default_max ) } {}
    : ~ i hm . a head_max
    ? < hm 0 { = hm ( http_req_head_max_bytes ) } {}
    ^ @ HttpLimits { hm ( http_req_header_max_count ) bm }
}

// Every HTTP/1.1 and HTTP/2 response from a listener that also speaks
// HTTP/3 carries `Alt-Svc: h3=":port"; ma=86400` (RFC 7838 / RFC 9114
// §3.1.1) so a client that started over TCP can move to QUIC.
@ __httpapp_with_alt_svc i port ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
    : String v ( string_from `h3=":` )
    ( string_push_int v port )
    ( string_push_str v `"; ma=86400` )
    ^ \ HttpRequest req → HttpResponse {
        : HttpResponse resp ( inner req )
        ( response_set_header resp `Alt-Svc` ( string_data v ) )
        ^ resp
    }
}

// Drive a bound listener: shutdown signal + composed handler + keep-alive
// loop (pool when workers>0). MOVES `listener`; stops the server on return.
// `cert` / `key` are the TLS listener's PEM paths ("" for plaintext): with
// them, and `http3` on, the same host:port is bound over UDP and served as
// HTTP/3 by the same handler on its own thread.
@ __httpapp_serve HttpAppImpl a TcpListener listener s scheme s host i port s cert s key → i {
    ( signal_install_shutdown listener )
    : ( Arc HttpDispatch ) dctl ( arc_new [HttpDispatch] @ HttpDispatch { ( mem_dup . a router ) . a has_static ( string_clone . a webroot ) } )
    : ( @ HttpResponse HttpRequest ) disp \ HttpRequest req → HttpResponse { ^ ( __httpapp_route_and_static dctl req ) }
    : ~ ( @ HttpResponse HttpRequest ) base disp
    // User middleware sits innermost: CORS preflights and the access
    // log see every request, including the ones a gate would hold.
    ? > ( vec_len [HttpMiddleware] . a mw ) 0 {
        : HttpMiddleware m ( vec_at [HttpMiddleware] . a mw 0 )
        : ( @ ( @ HttpResponse HttpRequest ) ( @ HttpResponse HttpRequest ) ) f . m f
        = base ( f base )
    } {}
    ? . a cors { = base ( with_cors_default base ) } {}
    ? . a log_requests { = base ( with_log_requests base ) } {}
    // ── HTTP/3 beside a TLS listener ──
    : ~ ? H3Server h3 @ ?H3Server { F }
    : ~ ? UdpSocket h3_sock @ ?UdpSocket { F }
    : ~ ? Thread h3_thread @ ?Thread { F }
    ? & & != . a http3 0 > ( nurl_str_len cert ) 0 != 0 ( nurl_str_eq scheme `https` ) {
        : QuicCreds h3_creds ( http3_creds_load cert key )
        // The second identity, when configured: the TCP listener has
        // already loaded the same files, so a failure here is a
        // filesystem race, and it is reported the same way as the
        // primary pair rather than served half-configured.
        : ~ b creds_ok ( http3_creds_ok h3_creds )
        ? & creds_ok > ( string_len . a pq_cert ) 0 {
            = creds_ok ( http3_creds_add_pq h3_creds ( string_data . a pq_cert ) ( string_data . a pq_key ) )
        } {}
        ? ! creds_ok { ( nurl_eprintln `http: HTTP/3 off — certificate or key could not be loaded for QUIC` ) } {
            ?? ( udp_bind host port ) {
                F e → {
                    ( nurl_eprint `http: HTTP/3 off — cannot bind UDP ` )
                    ( nurl_eprint host ) ( nurl_eprint `:` )
                    : String ps ( string_new )
                    ( string_push_int ps port )
                    ( nurl_eprint ( string_data ps ) ) ( nurl_eprint ` — ` )
                    ( nurl_eprintln ( net_err_name e ) )
                }
                T us → {
                    : QuicTp h3_tp ( http3_default_tp )
                    ( quic_tp_set_max_idle_timeout h3_tp . a idle_ms )
                    : ( Vec u ) alpn ( tls_alpn_pack `h3` )
                    : HttpLimits lim ( __httpapp_limits a )
                    : H3Server srv3 ( http3_server_new us h3_creds alpn h3_tp base . lim body_default_max )
                    = h3_sock @ ?UdpSocket { T us }
                    : H3Server h3p ( H3Server_share srv3 )
                    : ( @ v ) h3_thread_body \ → v { ( http3_server_run h3p ) }
                    ?? ( thread_spawn h3_thread_body ) {
                        T t → {
                            = h3_thread @ ?Thread { T t }
                            = base ( __httpapp_with_alt_svc port base )
                        }
                        F _ → { ( nurl_eprintln `http: HTTP/3 off — could not start the QUIC thread` ) }
                    }
                    = h3 @ ?H3Server { T srv3 }
                }
            }
        }
    } {}
    : ~ i ka . a max_keepalive
    ? < ka 0 { = ka ( server_keepalive_auto ) } {}
    : ~ i rt . a req_timeout_ms
    ? < rt 0 { = rt ( server_default_request_total_timeout_ms ) } {}
    : HttpServer srv ( server_new_complete listener base . a idle_ms ka ( __httpapp_limits a ) rt )
    ( __httpapp_banner a scheme host port )
    // SIGTERM / SIGINT → drain. The signal itself already stopped the
    // listener (signal_install_shutdown, async-signal-safe); this thread
    // sees it within 20 ms and runs the drain — idle connections closed,
    // in-flight requests finished, `drain_ms` for the rest — and the HTTP/3
    // side says GOAWAY to its connections.
    : Atomic served_out ( atomic_new 0 )
    : i dms . a drain_ms
    : ?H3Server h3w ( mem_dup h3 )
    : ( @ v ) watcher \ → v {
        : ~ b watching T
        ~ watching {
            ? | ( signal_pending ( signal_constant `SIGTERM` ) ) ( signal_pending ( signal_constant `SIGINT` ) ) {
                ?? h3w { T s3 → { ( http3_server_drain s3 ) } F → {} }
                : b _in_time ( server_drain srv dms )
                = watching F
            } {
                ? != 0 ( atomic_load served_out ) { = watching F } { ( sleep_ms 20 ) }
            }
        }
    }
    : !Thread ThreadErr wt ( thread_spawn watcher )
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
    ( atomic_store served_out 1 )
    ?? wt { T t → { : i _wj ( thread_join t ) } F _ → {} }
    ( server_stop srv )
    ?? h3_thread {
        T t → {
            ?? h3 { T s3 → { ( http3_server_stop s3 ) } F → {} }
            : i _j ( thread_join t )
        }
        F → {}
    }
    // the listener's state goes before its socket does
    = h3 @ ?H3Server { F }
    ?? h3_sock { T sk → { ( udp_close sk ) } F → {} }
    ^ rc
}

// Bind host:port and serve until the listener is closed (SIGINT/SIGTERM or
// error). Returns a process exit code (0 clean, 1 on bind/serve error).
@ http_app_listen HttpApp a__h s host i port → i {
    : HttpAppImpl a ( rc_get [HttpAppImpl] . a__h a )
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → { ^ ( __httpapp_serve a listener `http` host port `` `` ) }
        F e → {
            ( nurl_eprint `http: cannot bind ` )
            ( nurl_eprint host )
            ( nurl_eprint `:` )
            : String ps ( string_new )
            ( string_push_int ps port )
            ( nurl_eprint ( string_data ps ) )
            ( nurl_eprint ` — ` )
            ( nurl_eprintln ( net_err_name e ) )
            ^ 1
        }
    }
}

// Serve a listener the caller made — any TcpListener, the kernel's or
// one of another transport's (a simulated network's, stdlib/std/net_sim.nu,
// so a test serves the very app main() builds over the simulated wire).
// Same glue and same return as http_app_listen; MOVES `listener`, and
// returns once it is closed (tcp_close_listener on a copy the caller
// kept, or the shutdown signal for a kernel socket) — plaintext only.
@ http_app_serve HttpApp a__h sink TcpListener listener → i {
    : HttpAppImpl a ( rc_get [HttpAppImpl] . a__h a )
    // "ip:port", for the banner: the host before the last ':', the port
    // after it.
    : String where ( tcp_local_addr listener )
    : i n ( string_len where )
    : ~ i colon n
    : ~ i k 0
    ~ < k n {
        ? == 58 ( string_get where k ) { = colon k } {}
        = k + k 1
    }
    : String host ( string_substr where 0 colon )
    : ~ i port 0
    ?? ( string_to_int ( string_substr where + colon 1 - - n colon 1 ) ) { T x → { = port x } F _ → {} }
    ^ ( __httpapp_serve a listener `http` ( string_data host ) port `` `` )
}

// Same, over TLS. `cert`/`key` are PEM paths (EC, RSA or ML-DSA leaf,
// auto-detected; a fullchain PEM is accepted for `cert`). With
// `http_app_set_pq_cert` an ML-DSA pair is served beside this one.
@ http_app_listen_tls HttpApp a__h s host i port s cert s key → i {
    : HttpAppImpl a ( rc_get [HttpAppImpl] . a__h a )
    // Advertise HTTP/2 and HTTP/1.1 over ALPN (RFC 7301), h2 preferred:
    // an HTTP/2-capable client (browsers, curl, oha) gets HTTP/2, anything
    // else HTTP/1.1, over the same listener and the same routes. The
    // server itself tells the protocols apart by the connection preface.
    // HTTP/3 rides beside it: `__httpapp_serve` binds the same port over
    // UDP for QUIC and the TCP responses announce it with Alt-Svc.
    : !TcpListener NetErr lr ? > ( string_len . a pq_cert ) 0
    ( tcp_listen_tls_dual host port ( tcp_listen_default_backlog ) cert key ( string_data . a pq_cert ) ( string_data . a pq_key ) `h2 http/1.1` )
    ( tcp_listen_tls_with_alpn host port ( tcp_listen_default_backlog ) cert key `h2 http/1.1` )
    ?? lr {
        T listener → { ^ ( __httpapp_serve a listener `https` host port cert key ) }
        F e → {
            ( nurl_eprint `http: cannot bind TLS ` )
            ( nurl_eprint host )
            ( nurl_eprint `:` )
            : String ps ( string_new )
            ( string_push_int ps port )
            ( nurl_eprint ( string_data ps ) )
            ( nurl_eprint ` — ` )
            ( nurl_eprintln ( net_err_name e ) )
            ^ 1
        }
    }
}
