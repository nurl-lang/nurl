// stdlib/ext/http_server.nu — HTTP/1.1 (keep-alive) + HTTP/2 server.
//
// Layering:
//
//     Caller code  ─┐
//                   │   ( @ HttpResponse HttpRequest )  handler
//                   │
//                   ▼
//             ( server_run s )           ← blocks until listener errors
//                   │
//                   ▼
//             ( server_run_once s )      ← one accept + serve, returns
//                   │
//                   ▼
//      tcp_accept → _serve_keepalive_loop → close
//                       │
//                       ├─ ALPN "h2", or the HTTP/2 connection preface in
//                       │  the first bytes → __serve_h2 (http2_conn.nu:
//                       │  frames, streams, flow control; same handler)
//                       │
//                       ▼   otherwise HTTP/1.1, loops while connection alive
//      _read_request_head → handler → __write_response
//
// One handler, two protocols: HTTP/2 arrives either negotiated over TLS
// (RFC 9113 §3.3, tcp_listen_tls_with_alpn) or by prior knowledge on any
// listener (§3.4). Everything below the dispatch — DoS gate, idle timeout,
// body limits, server_stop — is shared. HTTP/3 is the same handler on a
// UDP socket beside a TLS listener (`ext/http3_server.nu`; the
// `packages/http` facade wires it up and adds `Alt-Svc` here).
//
// API (this revision):
//
//   ( server_new TcpListener listener
//                ( @ HttpResponse HttpRequest ) handler ) → HttpServer
//   ( server_new_with_timeout    listener handler i idle_ms )                      → HttpServer
//   ( server_new_full            listener handler i idle_ms i max_keepalive_reqs ) → HttpServer
//   ( server_default_idle_timeout_ms )       → i      30000 ms
//   ( server_default_max_keepalive_requests ) → i     1000 (thread-blocking modes)
//   ( server_keepalive_auto )                 → i     -2   per-mode default
//   ( server_keepalive_unlimited )            → i     -1   no reuse cap
//   ( server_run_once HttpServer s )                     → ! v NetErr
//   ( server_run      HttpServer s )                     → ! v NetErr
//   ( server_run_pool HttpServer s i n_workers )         → ! v NetErr
//   ( server_stop     HttpServer s )                     → v      close the listener
//   ( server_drain    HttpServer s i deadline_ms )       → b      graceful stop; T = all in time
//   ( server_drain_begin HttpServer s )                  → v      start one, don't wait
//   ( server_shutdown HttpServer s )                     → v      stop now (drain, no grace)
//   ( server_draining HttpServer s )                     → b
//   ( server_conn_count HttpServer s )                   → i      open connections
//   ( server_set_acceptors HttpServer s i n )            → v      accept fibers (async); 0 = per worker
//
// Memory model:
//
//   * `server_new` MOVES `listener` into the HttpServer. Caller must
//     NOT call `tcp_close_listener` after handing the listener over;
//     the server owns the lifecycle and `server_stop` closes it.
//   * `server_run_once` accepts ONE connection, then serves zero or
//     more HTTP/1.1 requests on it (keep-alive), and closes. Returns
//     Ok(0) on every clean drain, Err(NetClosed) when the listener
//     was stopped, Err(other) on accept-level failures only —
//     per-request write errors close the connection but do not
//     bubble out.
//   * `server_run` repeatedly calls `server_run_once` until any Err.
//     A NetClosed Err (the normal shutdown signal) maps to Ok-return
//     so caller code can distinguish "stopped cleanly" from
//     "infrastructure failed".
//   * Per-request: malformed requests trigger a stock 4xx response
//     and the connection is closed; the listener loop survives.
//   * The handler is lent the HttpRequest (releasing it or its fields
//     there is rejected); the server drops it after the handler
//     returns. The handler's returned HttpResponse is the server's,
//     dropped after serialise+write.
//
// Keep-alive policy (Phase 5.4):
//
//   * HTTP/1.1 + no `Connection: close` → connection is reused.
//   * HTTP/1.1 + `Connection: close` (request OR response)  → close.
//   * HTTP/1.0  → close (we do not honour `Connection: keep-alive`
//     opt-in for HTTP/1.0; clients that need keep-alive must speak
//     HTTP/1.1).
//   * After `max_keepalive_requests` reuses on one connection the
//     server forces close — a defence-in-depth cap against a single
//     client monopolising a worker. The default (`server_keepalive_auto`)
//     depends on the concurrency model: 1000 under server_run /
//     server_run_pool, where a connection holds a whole worker thread,
//     and no cap under server_run_async, where it holds only a fiber —
//     there the idle timeout below is the bound, and a cap would only
//     force the client to reconnect (and the server to re-accept and
//     re-spawn a fiber) every N requests.
//   * The per-conn idle timeout (`tcp_set_timeout`, default 30 s)
//     applies to EVERY recv on the connection — including the wait
//     for the next request between calls. So a connection that
//     idles past the deadline auto-closes, freeing the worker.
//
// Pipelining (HTTP/1.1 §6.3.2):
//
//   * The keep-alive loop owns one connection-level `Vec[u] carry`
//     that survives across requests. `_read_request_head` reads
//     into carry until `parse_request_head` succeeds, then drops
//     the consumed-by-the-head bytes from carry's front — anything
//     past the head (request body + a pipelined successor's bytes)
//     stays in carry. `_finish_body` then drains exactly
//     Content-Length bytes off carry's front into `req.body`,
//     topping up from the socket if short. Any remaining bytes in
//     carry feed the next iteration's `_read_request_head`
//     without a fresh tcp_read.
//   * Net effect: a peer that pipelines two requests in one send()
//     is processed correctly — both reach the handler with the
//     right body, both get a response in order. We do not promise
//     out-of-order pipelined-response delivery (the spec doesn't
//     either) — responses ride the same TCP stream in request
//     order.
//
// Other limitations (Phase 9):
//
//   * Single-threaded per accept loop — concurrency comes from
//     `server_run_pool`'s worker count, which is fixed at startup.
//   * No HTTP/2, no TLS — Phase 9.

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/dos.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_conn.nu`
$ `stdlib/core/slice.nu`

// ── HttpServer struct + lifecycle ─────────────────────────────────────
//
// Six knobs at v2.1+:
//   * idle_timeout_ms          — per-conn recv deadline. 0 = OS default.
//   * max_keepalive_requests   — per-conn request reuse cap. 0 = no keep-alive,
//                                server_keepalive_unlimited (-1) = no cap,
//                                server_keepalive_auto (-2) = the per-mode
//                                default (see server_keepalive_auto).
//   * limits                   — head / header-count / body byte caps
//                                (consulted by parse_request_head_with /
//                                 _finish_body's body-byte loop).
//   * request_total_timeout_ms — wall-clock budget for a single request,
//                                measured from "head parsed" to "response
//                                serialised". On overrun the handler's
//                                response is dropped, a stock 504 is sent
//                                instead, and the connection is closed.
//                                0 = disabled. Cannot interrupt a slow
//                                handler mid-flight (NURL has no thread
//                                cancellation primitives) — enforcement is
//                                post-handler only; the per-conn idle
//                                timeout covers slow reads.
: HttpServerImpl {
    TcpListener listener
    ( @ HttpResponse HttpRequest ) handler
    i idle_timeout_ms
    i max_keepalive_requests
    HttpLimits limits
    i request_total_timeout_ms
    // DoS state — the runtime-side NurlDosState (mutex-protected
    // concurrent + per-IP counters) behind a handle. Empty = DoS
    // protection disabled (the historical default; matches every
    // constructor except `server_new_with_dos`). When set,
    // server_run_once takes the acquire/release path that rejects
    // connections over the configured caps. Multiple workers in
    // server_run_pool share the same state via the shared HttpServer
    // value; the last copy of the server releases it.
    ? DosState dos_state
    // Every open connection, for server_drain (see "Graceful drain").
    ServerDrain drain
    // Accept fibers under server_run_async; 0 = one per runtime worker.
    Atomic acceptors
}

// A server is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same server — a worker thread's, a connection fiber's,
// the one server_stop is handed from another thread — and the last owner
// releases it. A thread or fiber that captures one takes a share of its
// own, so the server outlives whichever side finishes first.
: HttpServer { ( Shared HttpServerImpl ) ctl }

// Its copies are made to be used by several threads at once — the
// workers serving, another thread stopping or draining them. That is an
// assertion, not a proof (stdlib/core/marker.nu). What backs it: the
// configuration fields are written once, by the constructor; the one
// knob set after it (acceptors) is an Atomic; the listener is Sync; the
// connection registry is changed under its Mutex, with Atomic counters;
// the DoS counters live behind the runtime's own lock.
% Sync HttpServer {}

@ HttpServer_share HttpServer h → HttpServer { ^ @ HttpServer { ( shared_clone [HttpServerImpl] . h ctl ) } }

@ HttpServer_drop sink HttpServer h → v {}

@ __srv HttpServer h → *HttpServerImpl { ^ ( shared_ptr [HttpServerImpl] . h ctl ) }

@ __srv_new sink HttpServerImpl impl → HttpServer {
    ^ @ HttpServer { ( shared_new [HttpServerImpl] impl ) }
}

// ── Connection upgrade hook (WebSocket etc.) ─────────────────────
// The keep-alive loop hands each fully-parsed request to an optional
// upgrade handler BEFORE the normal HttpResponse handler. If the hook
// returns T it has TAKEN OVER the connection (e.g. performed the
// WebSocket 101 handshake and run the frame loop to completion,
// synchronously, on this worker); the loop then ends and the server
// closes the now-finished connection as usual — the hook need not close
// it (doing so is harmless: a TcpConn closes once). Returning F means
// "not mine", and the request falls through
// to the normal handler. Process-global (one server per process here);
// default unset = behaviour-neutral.
: __WsUpgrade { ( @ b TcpConn HttpRequest ) fn }
: ~ __WsUpgrade g_ws_upgrade 0
: ~ b g_ws_upgrade_set F

@ server_set_upgrade ( @ b TcpConn HttpRequest ) f → v {
    = g_ws_upgrade @ __WsUpgrade { f }
    = g_ws_upgrade_set T
}

// ── Streaming-response hook (SSE / NDJSON / chunked bodies) ──────
// The write-side sibling of the upgrade hook: it runs on every fully
// parsed request (body included) AFTER the WebSocket hook and BEFORE
// the normal HttpResponse handler. Return T after writing the whole
// response yourself — response_begin_chunked / response_write_chunk /
// response_end_chunked on the TcpConn — and the loop ends so the
// server closes the finished connection (a streamed response is the
// connection's last; the hook leaves the conn open). Return F for
// "not mine" and the request falls through to the router untouched.
// Process-global like the upgrade hook; default unset = neutral.
: __StreamHook { ( @ b TcpConn HttpRequest ) fn }
: ~ __StreamHook g_stream_hook 0
: ~ b g_stream_hook_set F

@ server_set_stream ( @ b TcpConn HttpRequest ) f → v {
    = g_stream_hook @ __StreamHook { f }
    = g_stream_hook_set T
}

// DoS connection caps (server-wide + per-source-IP). All caps are
// "soft" — a request that exceeds them is rejected with an immediate
// close (no canned 503), which is the cheapest possible response and
// keeps the server's per-conn cost down for the next legitimate client.
: DosLimits {
    i max_concurrent_conns  // 0 = unlimited
    i max_conns_per_ip  // 0 = unlimited (per-IP tracking disabled)
}

@ dos_default_limits → DosLimits {
    // Defaults sized for a single mid-tier VM serving public HTTPS.
    // 1024 concurrent ≈ 4-8 cores × 128-256 worker pool. 16 per-IP
    // catches the obvious "one bot, many connections" shape without
    // breaking CG-NAT'd legitimate clients (a typical CG-NAT block
    // multiplexes 10s of users under one public IP).
    ^ @ DosLimits { 1024 16 }
}

// Default 30 s recv/send timeout per accepted connection — slowloris
// defence comes for free (a client that withholds bytes past the
// deadline triggers tcp_read_chunk → NetClosed → server emits its
// canned 400 / closes the connection). Pass 0 to disable.
@ server_default_idle_timeout_ms → i { ^ 30000 }

// Default cap on keep-alive request reuse per connection in the
// thread-blocking modes (server_run, server_run_pool). After this many
// requests on a single conn, the server forces `Connection: close` and
// drops the conn. Defence-in-depth — a single misbehaving client cannot
// monopolise one worker thread forever. Pass 0 to disable keep-alive
// entirely (every connection serves exactly one request, matching
// pre-Phase-5.4 behaviour).
@ server_default_max_keepalive_requests → i { ^ 1000 }

// `max_keepalive_requests` value for "no reuse cap": the connection
// lives until the peer closes it, a request or response says
// `Connection: close`, or the idle timeout fires.
@ server_keepalive_unlimited → i { ^ -1 }

// `max_keepalive_requests` value for "the default of whichever model
// serves the connection" — what every constructor without an explicit
// cap stores. Resolved per connection: on a fiber (server_run_async) a
// connection costs a fiber, not a worker, so it is uncapped and the idle
// timeout bounds it; on a thread it is server_default_max_keepalive_requests.
@ server_keepalive_auto → i { ^ -2 }

// The cap a connection is served under: `auto` resolved for the calling
// context (fiber → unlimited, thread → 1000); every other value as given.
@ __keepalive_cap i configured → i {
    ? != configured ( server_keepalive_auto ) { ^ configured } {}
    ? != ( nurl_fiber_current ) 0 { ^ ( server_keepalive_unlimited ) } {}
    ^ ( server_default_max_keepalive_requests )
}

// Per-request total timeout default. 0 = disabled (matches pre-Phase-8
// behaviour; the per-conn idle timeout still bounds slow reads).
@ server_default_request_total_timeout_ms → i { ^ 0 }

@ server_new TcpListener listener ( @ HttpResponse HttpRequest ) handler → HttpServer {
    ^ ( __srv_new @ HttpServerImpl { listener handler
        ( server_default_idle_timeout_ms )
        ( server_keepalive_auto )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        @ ?DosState { F } ( __drain_new ) ( atomic_new 0 ) } )
}

@ server_new_with_timeout TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms → HttpServer {
    ^ ( __srv_new @ HttpServerImpl { listener handler idle_timeout_ms
        ( server_keepalive_auto )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        @ ?DosState { F } ( __drain_new ) ( atomic_new 0 ) } )
}

@ server_new_full TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms i max_keepalive_requests → HttpServer {
    ^ ( __srv_new @ HttpServerImpl { listener handler idle_timeout_ms max_keepalive_requests
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        @ ?DosState { F } ( __drain_new ) ( atomic_new 0 ) } )
}

// `server_new_complete` — every knob explicit. Use when overriding
// parser limits and/or per-request total timeout. See the struct comment
// for what each field controls.
@ server_new_complete TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms i max_keepalive_requests HttpLimits limits i request_total_timeout_ms → HttpServer {
    ^ ( __srv_new @ HttpServerImpl { listener handler idle_timeout_ms max_keepalive_requests limits request_total_timeout_ms @ ?DosState { F } ( __drain_new ) ( atomic_new 0 ) } )
}

// DoS-aware constructor. Allocates a NurlDosState on the runtime side
// configured with the given caps; the server's last copy disposes it. All other
// knobs use defaults — combine with the keep-alive / timeout knobs
// after construction by directly mutating the returned struct, or
// extend this helper if a uniform full-knob variant is needed later.
@ server_new_with_dos TcpListener listener ( @ HttpResponse HttpRequest ) handler DosLimits dos_limits → HttpServer {
    : DosState st ( dos_state_new . dos_limits max_concurrent_conns
    . dos_limits max_conns_per_ip )
    ^ ( __srv_new @ HttpServerImpl { listener handler
        ( server_default_idle_timeout_ms )
        ( server_keepalive_auto )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        @ ?DosState { T st } ( __drain_new ) ( atomic_new 0 ) } )
}

// Snapshot the current active-connection count — useful for /metrics
// observability endpoints. Returns 0 when DoS protection is disabled.
@ server_active_conn_count HttpServer s → i {
    ?? . ( __srv s ) dos_state {
        T g → { ^ ( dos_state_active g ) }
        F → { ^ 0 }
    }
}

// ── Graceful drain ───────────────────────────────────────────────────
//
// `server_drain s deadline_ms` stops a server the way a deploy wants it
// stopped: no new connections, nothing in flight lost.
//
//   1. The listener closes: accept() fails, so the run loop / accept fiber
//      ends and the kernel refuses new connections. A connection accepted
//      in the same instant is closed before it is served.
//   2. Every keep-alive connection that is IDLE — waiting for its next
//      request — has its read side shut (tcp_conn_shutdown): the wait
//      returns EOF and the connection closes at once, as when a peer
//      closes. An HTTP/2 connection is answered with GOAWAY (NO_ERROR,
//      the last stream it processed) on its way out.
//   3. A connection in the middle of a request finishes it: the response
//      goes out with `Connection: close`, and the connection closes.
//   4. `server_drain` waits for the last connection, up to `deadline_ms`;
//      past it, the stragglers are shut both ways (a blocked read or
//      write fails) and their loops end. T when everything finished in
//      time.
//
// Every connection registers on entry: a slot holding a share of its
// TcpConn and a state word — 0 idle, 1 busy, 2 shut by the drain — which
// the serve loop flips per request with one atomic compare-and-swap (no
// lock on the request path; the registry's mutex is taken only when a
// connection opens or closes, and by the drain). The handshake is
// symmetric: the drain sets the phase, then shuts what is idle; the loop
// marks itself idle, then reads the phase — every operation sequentially
// consistent, so a connection that turns idle as the drain begins is
// either shut by it or sees the phase and closes itself.
//
// A request whose bytes arrive in the instant its idle connection is
// shut is not answered: the client sees the connection close before any
// response — the race every server has when it closes an idle keep-alive
// connection, which RFC 9112 §9.6 obliges a client to handle (it retries
// an idempotent request).

: DrainEntry { TcpConn conn Atomic st }

: DrainImpl {
    Mutex mu
    ( Vec ? DrainEntry ) slots
    ( Vec i ) free
    Atomic phase  // 0 serving, 1 draining, 2 past the deadline
    Atomic active  // registered connections
}

// The registry: a handle on its state (stdlib/core/rcbox.nu) that every
// copy of the server shares.
: ServerDrain { ( Shared DrainImpl ) ctl }

@ ServerDrain_share ServerDrain h → ServerDrain { ^ @ ServerDrain { ( shared_clone [DrainImpl] . h ctl ) } }

@ ServerDrain_drop sink ServerDrain h → v {}

@ __drain_p ServerDrain d → *DrainImpl { ^ ( shared_ptr [DrainImpl] . d ctl ) }

@ __drain_new → ServerDrain {
    ^ @ ServerDrain { ( shared_new [DrainImpl] @ DrainImpl {
            ( mutex_new ) ( vec_new [? DrainEntry] ) ( vec_new [i] ) ( atomic_new 0 ) ( atomic_new 0 ) } ) }
}

// Register `c` with state word `st`; its slot, or -1 when the server is
// draining (the caller closes the connection unserved).
@ __drain_enter ServerDrain d TcpConn c Atomic st → i {
    : *DrainImpl p ( __drain_p d )
    ( mutex_lock . p mu )
    ? != ( atomic_load . p phase ) 0 {
        ( mutex_unlock . p mu )
        ^ -1
    } {}
    : ~ i slot -1
    ?? ( vec_pop [i] . p free ) {
        T k → {
            = slot k
            : b _ok ( vec_set [? DrainEntry] . p slots k @ ?DrainEntry { T @ DrainEntry { ( TcpConn_share c ) ( Atomic_share st ) } } )
        }
        F → {
            = slot ( vec_len [? DrainEntry] . p slots )
            ( vec_push [? DrainEntry] . p slots @ ?DrainEntry { T @ DrainEntry { ( TcpConn_share c ) ( Atomic_share st ) } } )
        }
    }
    : i _n ( atomic_add . p active 1 )
    ( mutex_unlock . p mu )
    ^ slot
}

@ __drain_leave ServerDrain d i slot → v {
    ? < slot 0 { ^ v } {}
    : *DrainImpl p ( __drain_p d )
    ( mutex_lock . p mu )
    : b _ok ( vec_set [? DrainEntry] . p slots slot @ ?DrainEntry { F } )
    ( vec_push [i] . p free slot )
    : i _n ( atomic_sub . p active 1 )
    ( mutex_unlock . p mu )
}

// Shut every registered connection whose state moves `from` → 2 (any
// state when `from` < 0): its read side, or both (`both`).
@ __drain_shut ServerDrain d i from b both → v {
    : *DrainImpl p ( __drain_p d )
    ( mutex_lock . p mu )
    : i n ( vec_len [? DrainEntry] . p slots )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [? DrainEntry] . p slots k ) {
            T oe → {
                ?? oe {
                    T e → {
                        : ~ b go F
                        ? < from 0 { : i _o ( atomic_swap . e st 2 ) = go T } {
                            = go ( atomic_cas . e st from 2 )
                        }
                        ? go { ( tcp_conn_shutdown . e conn both ) } {}
                    }
                    F → {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( mutex_unlock . p mu )
}

// Is the server draining (or past its drain deadline)?
@ server_draining HttpServer s → b {
    ^ != 0 ( atomic_load . ( __drain_p . ( __srv s ) drain ) phase )
}

// Connections the server holds open right now (all serving modes).
@ server_conn_count HttpServer s → i {
    ^ ( atomic_load . ( __drain_p . ( __srv s ) drain ) active )
}

// Begin a drain without waiting for it: stop accepting and close the
// idle connections (steps 1–2 above). The serve loops finish the rest.
// Safe from any thread, any number of times.
@ server_drain_begin HttpServer s → v {
    : *DrainImpl p ( __drain_p . ( __srv s ) drain )
    : b _first ( atomic_cas . p phase 0 1 )
    ( tcp_close_listener . ( __srv s ) listener )
    ( __drain_shut . ( __srv s ) drain 0 F )
}

// Drain the server (see "Graceful drain"): stop accepting, close idle
// connections, let the ones mid-request finish with `Connection: close`,
// and wait up to `deadline_ms` for the last of them; then shut the rest
// and return. T when every connection finished before the deadline. Call
// it from outside the server's own connections — a SIGTERM watcher, an
// admin thread or fiber — since it waits for every connection to end,
// its caller's included. The run call (server_run / server_run_pool /
// server_run_async) returns once the last connection has closed.
@ server_drain HttpServer s i deadline_ms → b {
    ( server_drain_begin s )
    : *DrainImpl p ( __drain_p . ( __srv s ) drain )
    : i until + ( now_ms ) ? > deadline_ms 0 deadline_ms 0
    ~ & > ( atomic_load . p active ) 0 < ( now_ms ) until { ( sleep_ms 5 ) }
    ? == 0 ( atomic_load . p active ) { ^ T } {}
    ( atomic_store . p phase 2 )
    ( __drain_shut . ( __srv s ) drain -1 T )
    // The shut loops end promptly; wait for them, briefly, so a caller
    // that tears the process down next does not cut their last writes.
    : i grace + ( now_ms ) 1000
    ~ & > ( atomic_load . p active ) 0 < ( now_ms ) grace { ( sleep_ms 5 ) }
    ^ F
}

// Stop now: a drain with no grace period — every connection, busy or
// not, is shut at once.
@ server_shutdown HttpServer s → v {
    : b _done ( server_drain s 0 )
}

// How many accept fibers server_run_async runs on the listener: 0 (the
// default) = one per runtime worker; 1 = the single accept loop of old.
// Set before the server runs.
@ server_set_acceptors HttpServer s i n → v {
    ( atomic_store . ( __srv s ) acceptors n )
}

// Close the listener: the run loop ends once its current connections do.
// Connections keep being served until they close on their own — see
// server_drain for a stop that ends idle keep-alive connections and
// bounds the wait.
@ server_stop HttpServer s → v {
    ( tcp_close_listener . ( __srv s ) listener )
}

// ── In-place "drop first N bytes from a Vec[u]" helper ───────────────
//
// Used by the carry-buffer pipeline below. After `parse_request_head`
// reports `.consumed` bytes for the head, we shift the remainder of the
// carry buffer down so a future parse_request_head call on the same
// carry sees the next request's bytes starting at index 0. Implementation
// copies the tail [n..total) into a fresh Vec[u], vec_clears the input,
// and vec_extends the tail back — O(remaining), and `remaining` is zero
// in the non-pipelined common case (single TCP read containing exactly
// one head + body). Public Vec[u] API only — no peek/poke into the
// control block.
@ __vec_drop_front_u ( Vec u ) buf i n → v {
    : i total ( vec_len [u] buf )
    ? <= n 0 {} {
        ? >= n total {
            ( vec_clear [u] buf )
        } {
            : i remaining - total n
            : *u p ( vec_data [u] buf )
            ( nurl_memmove # s p # s # *u + # i p n remaining )
            ( vec_set_len [u] buf remaining )
        }
    }
}

// ── Read the full request head off the socket ─────────────────────────
//
// Operates on a connection-level `carry` buffer owned by the keep-alive
// loop. Loops parse_request_head_with(carry) → top-up-from-socket until
// the parse succeeds or hits a non-Incomplete error.
//
// On success: returns Ok(ParsedHeadOk { head, consumed }). `consumed`
// bytes are dropped off carry's front, leaving any further bytes (this
// request's body + pipelined successor) for `_finish_body` / the next
// iteration to consume. The returned `head.body` is left untouched
// (empty) — the body lives in carry until `_finish_body` drains it.
//
// On socket error: returns Err(HttpReqIo). On unrecoverable parse
// error: returns the matching HttpReqErr (TooLarge / Malformed /
// UnsupportedVersion). Carry's state is unspecified on Err (caller is
// about to close).

@ _read_request_head TcpConn conn ( Vec u ) carry HttpLimits limits → !ParsedHeadOk HttpReqErr {
    : ~ b done F
    : ~ b had_err F
    : ~ HttpReqErr err # HttpReqErr HttpReqIo

    ~ ! done {
        // First try parsing whatever's already in carry (might be the
        // pipelined successor's full head from the previous request's
        // read).
        : !ParsedHeadOk HttpReqErr ph ( parse_request_head_with carry limits )
        ?? ph {
            T pho → {
                : i used . pho consumed
                ( __vec_drop_front_u carry used )
                = done T
                ^ @ !ParsedHeadOk HttpReqErr { T pho }
            }
            F e → {
                : s nm ( http_req_err_name e )
                ? != 0 ( nurl_str_eq nm `HttpReqIncomplete` ) {
                    // Incomplete = keep reading. Top up carry in place —
                    // tcp_read_into appends straight into carry's spare
                    // capacity, skipping tcp_read_chunk's per-read
                    // throwaway Vec (alloc + copy + free per read).
                    : !i NetErr r ( tcp_read_into conn carry 4096 )
                    ?? r {
                        T got → {
                            ? <= got 0 {
                                // 0 bytes can't happen (NetClosed is returned
                                // as Err) but guard against runtime bugs.
                                = had_err T
                                = err # HttpReqErr HttpReqIo
                                = done T
                            } {}
                        }
                        F _ → {
                            // NetClosed mid-head OR transport error.
                            = had_err T
                            = err # HttpReqErr HttpReqIo
                            = done T
                        }
                    }
                } {
                    // Real parse error — surface it and close.
                    = had_err T
                    = err e
                    = done T
                }
            }
        }
    }
    ^ @ !ParsedHeadOk HttpReqErr { F err }
}

// The same loop for the keep-alive path: parses into the connection's
// own HttpRequest (see `request_recycle`), returning the bytes consumed.
@ _read_request_head_into TcpConn conn ( Vec u ) carry HttpLimits limits HttpRequest req ( Vec Header ) spare → !i HttpReqErr {
    : ~ b done F
    : ~ HttpReqErr err # HttpReqErr HttpReqIo
    ~ ! done {
        : !i HttpReqErr ph ( parse_request_head_into carry limits req spare )
        ?? ph {
            T used → {
                ( __vec_drop_front_u carry used )
                = done T
                ^ @ !i HttpReqErr { T used }
            }
            F e → {
                : s nm ( http_req_err_name e )
                ? != 0 ( nurl_str_eq nm `HttpReqIncomplete` ) {
                    : !i NetErr r ( tcp_read_into conn carry 4096 )
                    ?? r {
                        T got → {
                            ? <= got 0 {
                                = err # HttpReqErr HttpReqIo
                                = done T
                            } {}
                        }
                        F _ → {
                            = err # HttpReqErr HttpReqIo
                            = done T
                        }
                    }
                } {
                    = err e
                    = done T
                }
            }
        }
    }
    ^ @ !i HttpReqErr { F err }
}

// ── Top up body from Content-Length, draining carry first ─────────────
//
// `carry` holds whatever bytes arrived past the head (body bytes that
// rode in the same TCP read as the head, plus any pipelined successor's
// bytes). We take up to Content-Length bytes off carry's front into
// req.body, then top up from the socket if short. Excess bytes (a
// pipelined successor) stay in carry for the next iteration.
//
// Returns T on success, F on transport / format error.

// Ensure `carry` holds at least `n` bytes, topping up from the socket.
// Returns F on EOF / IO before reaching `n`.
@ __carry_ensure TcpConn conn ( Vec u ) carry i n → b {
    : ~ b ok T
    ~ & ok < ( vec_len [u] carry ) n {
        : !i NetErr r ( tcp_read_into conn carry 4096 )
        ?? r {
            T got → { ? <= got 0 { = ok F } {} }
            F _ → { = ok F }
        }
    }
    ^ ok
}

// Upper bound on trailer lines after a chunked body's terminating chunk.
// A peer that streams an endless trailer section (each line ≤ 8 KiB but
// unbounded in count) otherwise holds the connection open indefinitely.
@ __max_trailer_lines → i { ^ 64 }

// Index of the next CRLF in `carry`, topping up from the socket until
// found or `cap` bytes have accumulated. Returns the CR index, or -1 on
// EOF / IO / cap exceeded (a chunk-size or trailer line longer than `cap`
// is rejected, mirroring __read_crlf_line's 8 KiB guard).
@ __carry_find_crlf TcpConn conn ( Vec u ) carry i cap → i {
    : ~ i found -1
    : ~ b stop F
    ~ & == found -1 ! stop {
        : i len ( vec_len [u] carry )
        : *u p ( vec_data [u] carry )
        : ~ i k 0
        ~ & == found -1 < k - len 1 {
            ? & == 13 & 255 # i . p k == 10 & 255 # i . p + k 1 { = found k } {}
            = k + k 1
        }
        ? >= found 0 {} {
            ? >= len cap { = stop T } {
                : !i NetErr r ( tcp_read_into conn carry 4096 )
                ?? r {
                    T got → { ? <= got 0 { = stop T } {} }
                    F _ → { = stop T }
                }
            }
        }
    }
    ^ found
}

// Decode a Transfer-Encoding: chunked body off `carry` (+ socket top-ups)
// into `req.body`, leaving any pipelined-successor bytes after the
// terminating chunk in `carry`. Mirrors read_body's chunked decoder but
// is carry-aware so it works inside the keep-alive loop. Returns F on
// malformed framing, IO error, or a body exceeding `body_max`.
@ __finish_body_chunked TcpConn conn HttpRequest req ( Vec u ) carry i body_max → b {
    : ~ b done F
    : ~ b ok T
    ~ & ok ! done {
        : i crlf ( __carry_find_crlf conn carry 8192 )
        ? < crlf 0 { = ok F } {
            : String szline ( _bsubstr carry 0 crlf )
            ( __vec_drop_front_u carry + crlf 2 )
            : !i ParseErr szr ( _parse_hex_size szline )
            ?? szr {
                T n → {
                    ? < n 0 { = ok F } {
                        ? == n 0 {
                            // Terminating chunk: consume trailer lines up to
                            // the closing empty line. The trailer section is
                            // bounded — an unbounded run of trailer lines is
                            // a slowloris variant — at __max_trailer_lines.
                            : ~ b tdone F
                            : ~ i tcount 0
                            ~ & ok ! tdone {
                                : i tc ( __carry_find_crlf conn carry 8192 )
                                ? < tc 0 { = ok F } {
                                    ( __vec_drop_front_u carry + tc 2 )
                                    ? == tc 0 { = tdone T } {
                                        = tcount + tcount 1
                                        ? > tcount ( __max_trailer_lines ) { = ok F } {}
                                    }
                                }
                            }
                            = done T
                        } {
                            ? > + ( vec_len [u] . req body ) n body_max { = ok F } {
                                // Need n bytes of data + the trailing CRLF.
                                ? ( __carry_ensure conn carry + n 2 ) {
                                    : *u cd ( vec_data [u] carry )
                                    // The two octets after the chunk data MUST
                                    // be CRLF (RFC 9112 §7.1). Dropping them
                                    // unverified let a peer smuggle bytes past
                                    // a strict front-end (a framing desync).
                                    ? | != & 255 # i . cd n 13 != & 255 # i . cd + n 1 10 {
                                        = ok F
                                    } {
                                        : ~ i k 0
                                        ~ < k n {
                                            ( vec_push [u] . req body & 255 # i . cd k )
                                            = k + k 1
                                        }
                                        ( __vec_drop_front_u carry + n 2 )
                                    }
                                } { = ok F }
                            }
                        }
                    }
                }
                F _ → { = ok F }
            }
        }
    }
    ^ ok
}

@ _finish_body TcpConn conn HttpRequest req ( Vec u ) carry i body_max → b {
    // Transfer-Encoding takes precedence (RFC 7230 §3.3.3). A chunked body
    // MUST be drained here too — otherwise its bytes are left in `carry`,
    // handed to the handler as an empty body, and mis-parsed as the next
    // request on a keep-alive connection (a desync / smuggling vector).
    : i te_i ( header_index . req headers `Transfer-Encoding` )
    ? >= te_i 0 {
        : *Header thd ( vec_data [Header] . req headers )
        : Header teh . thd te_i
        ? ( __header_value_eq_ci . teh value `chunked` ) { ^ ( __finish_body_chunked conn req carry body_max ) } {}
        // Non-chunked Transfer-Encoding is unsupported (and CL+TE is
        // already rejected at head parse) — fail the body read.
        ^ F
    } {}
    : i cl_i ( header_index . req headers `Content-Length` )
    // No Content-Length: nothing more to read.
    ? < cl_i 0 { ^ T } {}
    : *Header chd ( vec_data [Header] . req headers )
    : Header clh . chd cl_i
    : !i ParseErr nr ( string_to_int . clh value )
    ?? nr {
        T clen → {
            ? < clen 0 { ^ F } {}
            ? > clen body_max { ^ F } {}
            // Drain carry's front into req.body, up to clen bytes.
            : i avail ( vec_len [u] carry )
            : i take ? < clen avail clen avail
            ? > take 0 {
                : *u cdata ( vec_data [u] carry )
                : ~ i k 0
                ~ < k take {
                    ( vec_push [u] . req body . cdata k )
                    = k + k 1
                }
                ( __vec_drop_front_u carry take )
            } {}
            : i have ( vec_len [u] . req body )
            ? >= have clen { ^ T } {}
            : i need - clen have
            // `carry` already drained `have` body bytes into req.body;
            // exactly `need` more sit on the socket. Read precisely
            // that — NOT read_body_to, which re-derives the length
            // from Content-Length and would try to read the whole
            // `clen` again (and rejects need<clen as HttpReqTooLarge).
            : !( Vec u ) HttpReqErr more ( _read_n_bytes conn need )
            ?? more {
                T extra → {
                    ( vec_extend [u] . req body extra )
                    ^ T
                }
                F _ → ^ F
            }
        }
        F _ → ^ F
    }
}

// ── Write a complete HttpResponse back to the connection ──────────────
//
// When `force_close` is T, ensures `Connection: close` rides on the
// wire (replacing any caller-set value via `response_set_header`'s
// dedup semantics). When F, the Connection header is left untouched —
// HTTP/1.1's keep-alive default applies and the caller may continue
// reading further requests on the same socket.
//
// `r` is the caller's (dropped by its owner). `wire` is the
// connection-level scratch buffer (owned by _serve_keepalive_loop):
// serialising into it instead of a fresh Vec saves an allocate/free
// pair per response on the keep-alive hot path.
//
// Only the HEAD is serialised into `wire`; the body is written from
// the response itself as the second segment of one `tcp_write_all2`
// (a single sendmsg on plaintext). Copying the body into `wire` used to
// be the second full copy of every response body — measured at 1 MB it
// was about half of the per-request CPU gap to hyper, which writes its
// body slice by reference.

@ __write_response TcpConn conn HttpResponse r b force_close ( Vec u ) wire → !v NetErr {
    ? force_close {
        ( response_set_header r `Connection` `close` )
    } {}
    ( vec_clear [u] wire )
    ( response_serialize_head_to r wire )
    : !v NetErr wr ( tcp_write_all2 conn wire . r body )
    ^ wr
}

// The 504 that replaces a handler's response past the per-request total
// timeout; the late response is recycled unsent.
@ __timeout_response sink HttpResponse late → HttpResponse {
    ( response_recycle late )
    ^ ( response_text 504 `request total-timeout exceeded\n` )
}

// Build a stock 4xx error response for parse failures.
@ _parse_err_response HttpReqErr e → HttpResponse {
    : s nm ( http_req_err_name e )
    ? != 0 ( nurl_str_eq nm `HttpReqTooLarge` ) {
        ^ ( response_text 413 `request entity too large\n` )
    } {}
    ? != 0 ( nurl_str_eq nm `HttpReqUnsupportedVersion` ) {
        ^ ( response_text 505 `HTTP version not supported\n` )
    } {}
    ^ ( response_text 400 `bad request\n` )
}

// ── Connection-header parsing ─────────────────────────────────────────
//
// Case-insensitive ASCII compare between an OWNED String value (as
// returned by header_get) and a NUL-terminated raw `s` literal.
// Lengths must match exactly — `__header_value_eq_ci v "close"`
// returns F for "Close, Upgrade" and any other multi-token value.
// Multi-token Connection headers fall through to "keep-alive" by
// default; this is acceptable for v1 — clients that genuinely want
// a close on a 1.1 connection send the bare token.

@ __header_value_eq_ci String value s lit → b {
    : i la ( string_len value )
    : i lb ( nurl_str_len lit )
    ? != la lb { ^ F } {}
    : *u pa # *u ( string_data value )
    : *u pb # *u lit
    : ~ i k 0
    ~ < k la {
        : ~ i ca & 255 # i . pa k
        : ~ i cb & 255 # i . pb k
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Returns T if the request asks for the connection to be closed
// after this response. Policy:
//   * non-HTTP/1.1 (any version other than the literal string
//     "HTTP/1.1") → close. We deliberately do not honour
//     `Connection: keep-alive` opt-in for HTTP/1.0 — clients that
//     need persistent connections must speak 1.1.
//   * HTTP/1.1 + bare `Connection: close` value → close.
//   * HTTP/1.1 + missing or other Connection header → keep-alive.
// Borrowed scan for `Connection: close` — walks the Header vec in
// place (first name match wins, mirroring header_get) instead of
// materialising an owned String copy of the value per request.
@ __conn_header_says_close ( Vec Header ) hs → b {
    : i n ( vec_len [Header] hs )
    : *Header hdata ( vec_data [Header] hs )
    : i cn ( nurl_str_len `Connection` )
    : ~ i k 0
    ~ < k n {
        : Header h . hdata k
        ? ( _header_name_eq_ci_n . h name `Connection` cn ) {
            ^ ( __header_value_eq_ci . h value `close` )
        } {}
        = k + k 1
    }
    ^ F
}

@ __request_says_close HttpRequest req → b {
    : s ver ( string_data . req version )
    ? == 0 ( nurl_str_eq ver `HTTP/1.1` ) { ^ T } {}
    ^ ( __conn_header_says_close . req headers )
}

// Returns T if the response carries `Connection: close`. The handler
// can opt this connection out of keep-alive by setting that header
// explicitly.
@ __response_says_close HttpResponse r → b {
    ^ ( __conn_header_says_close . r headers )
}

// ── server_run_once ──────────────────────────────────────────────────
//
// Single connection lifecycle: accept, then drive the keep-alive
// loop until the conn drains (peer close, idle timeout, explicit
// `Connection: close`, or the per-conn request cap fires). Returns
// Ok(0) for every cleanly-drained connection. Returns Err only when
// `tcp_accept` itself fails — per-request write/parse errors close
// the connection but do not bubble out.

// Everything a freshly accepted connection gets, regardless of the
// concurrency model driving it (sync loop, worker pool, or a per-conn
// fiber): the DoS admission gate, the per-conn idle timeout, the
// keep-alive serve loop, and the close. Consumes `conn`.
@ __serve_accepted HttpServer s TcpConn conn → v {
    // DoS gate. If the server was constructed with server_new_with_dos,
    // dos_state holds the shared counters + IP table. acquire returns 0
    // when the global or per-IP cap is exceeded; we close the conn
    // immediately (no canned 503 — that costs more than rejecting at the
    // TCP layer). On accept: extract peer IP (best-effort —
    // tcp_peer_addr returns "ip:port"; we split on ':'). On release: pass
    // the same IP back so the counter unwinds.
    ?? . ( __srv s ) dos_state {
        T g → { ( __serve_gated s g conn ) }
        F → { ( __serve_conn s conn ) }
    }
}

// The idle timeout and the keep-alive serve loop, which takes the
// connection over and closes it with its last owner.
@ __serve_conn HttpServer s TcpConn conn → v {
    // Registered for server_drain; refused unserved while it drains.
    : Atomic st ( atomic_new 0 )
    : i slot ( __drain_enter . ( __srv s ) drain conn st )
    ? < slot 0 { ^ v } {}
    : i ito . ( __srv s ) idle_timeout_ms
    ? > ito 0 { ( tcp_set_timeout conn ito ) } {}
    ( _serve_keepalive_loop s conn st )
    ( __drain_leave . ( __srv s ) drain slot )
}

@ __serve_gated HttpServer s DosState g TcpConn conn → v {
    : ~ s peer_ip ``
    // Owns the "ip" prefix (the "ip:port" truncated at the colon, or the
    // whole address) whose buffer `peer_ip` aliases; dropped on every exit
    // path below, after the serve loop and the dos_state_release that
    // reads peer_ip — the address the connection caches is gone once the
    // serve loop has closed it. The DoS path used to leak one String per
    // connection, which an attacker opening/closing connections in a loop
    // turns into unbounded heap growth.
    : String ip_only ( string_new )
    : s addr ( tcp_peer_addr conn )
    : i an ( nurl_str_len addr )
    : ~ i colon -1
    : ~ i k 0
    ~ & == colon -1 < k an {
        ? == 58 ( nurl_str_at addr an k ) { = colon k } {}
        = k + k 1
    }
    ? > colon 0 {
        : ~ i j 0
        ~ < j colon {
            ( string_push_char ip_only ( nurl_str_at addr an j ) )
            = j + j 1
        }
    } { ( string_push_str ip_only addr ) }
    = peer_ip ( string_data ip_only )
    : i ok ( dos_state_try_acquire g peer_ip )
    ? == ok 0 {
        ( tcp_close_conn conn )
        ^ v
    } {}
    : Atomic st ( atomic_new 0 )
    : i slot ( __drain_enter . ( __srv s ) drain conn st )
    ? >= slot 0 {
        : i ito . ( __srv s ) idle_timeout_ms
        ? > ito 0 { ( tcp_set_timeout conn ito ) } {}
        ( _serve_keepalive_loop s conn st )
        ( __drain_leave . ( __srv s ) drain slot )
    } {}
    ( dos_state_release g peer_ip )
}

@ server_run_once HttpServer s → !v NetErr {
    : !TcpConn NetErr ar ( tcp_accept . ( __srv s ) listener )
    ?? ar {
        T conn → {
            ( __serve_accepted s conn )
            ^ @ !v NetErr { T 0 }
        }
        F e → ^ @ !v NetErr { F e }
    }
}

// The per-connection request loop. Walks request → handler →
// response → repeat until any of the following happens:
//
//   * `_read_request_head` fails with HttpReqIo (peer closed
//     cleanly between requests, or the recv timeout fired). No
//     response is written — connection dies silently.
//   * `_read_request_head` fails with any other parse error. We
//     write the canned 4xx response, then close.
//   * `_finish_body` fails. We write a 400, then close.
//   * The request OR response carries `Connection: close`. We write
//     the response (forcing `Connection: close`), then close.
//   * `n_served` reaches `max_keepalive_requests` (resolved through
//     __keepalive_cap; never on an uncapped connection). Same as the
//     close-after-response path — the cap is defence-in-depth, not
//     a polished policy.
//   * Any `__write_response` returns Err. We close.
//
// The function returns `v` rather than `! v NetErr` because none of
// these per-request errors are interesting at the listener level —
// they all just mean "this connection is done, accept the next one".

@ _serve_keepalive_loop HttpServer s TcpConn conn Atomic st → v {
    : i max_req ( __keepalive_cap . ( __srv s ) max_keepalive_requests )
    : HttpLimits lim . ( __srv s ) limits
    : i body_max . lim body_default_max
    : i req_timeout_ms . ( __srv s ) request_total_timeout_ms
    // One connection-level carry buffer, owned here, freed at the
    // bottom. Survives across keep-alive iterations so a pipelined
    // successor's bytes (or any leftover past a request's body) are
    // visible to the next _read_request_head call without re-reading
    // from the socket.
    : ( Vec u ) carry ( vec_with_cap [u] 4096 )
    // HTTP/2 over TLS (RFC 9113 §3.3): when ALPN settled on "h2" the
    // connection IS HTTP/2 from its first byte — no sniffing, and an
    // invalid preface is a PROTOCOL_ERROR the h2 layer answers with
    // GOAWAY, not an HTTP/1.1 400.
    ? ( tcp_alpn_is conn `h2` ) {
        ( __serve_h2 s conn carry )
        ^ v
    } {}
    // HTTP/2 prior knowledge (RFC 9113 §3.4) on every other connection —
    // a plaintext listener, or a TLS client that negotiated no ALPN. A
    // client that already knows the server speaks HTTP/2 opens with the
    // 24-byte preface `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`. Recognise it
    // from the first bytes and hand the connection, carry and all, to the
    // HTTP/2 connection machinery; anything else is HTTP/1.1 and continues
    // below with the same bytes still in carry. The sniff costs the HTTP/1
    // path nothing extra: the first recv happens here instead of in
    // _read_request_head, and the comparison stops at the first
    // non-matching byte (a GET differs at byte 0, a POST at byte 1). On a
    // shared port garbage that is neither is an HTTP/1.1 request with a
    // bad request line and gets the 400 HTTP/1.1 gives it — a dual-
    // protocol port cannot answer it with an HTTP/2 GOAWAY, so h2spec's
    // §3.5/2 ("invalid connection preface") is only meaningful against an
    // ALPN-h2 or h2-only (http2_serve) endpoint.
    : i h2 ( __sniff_h2_preface conn carry )
    ? == h2 1 {
        ( __serve_h2 s conn carry )
        ^ v
    } {}
    ? < h2 0 {
        // Peer went away before sending a full first line — the same
        // silent close the HTTP/1.1 path gives an idle connection.
        ^ v
    } {}
    // Connection-level response wire buffer, cleared and refilled by
    // __write_response per response — one allocation per CONNECTION
    // instead of one per response.
    : ( Vec u ) wire ( vec_with_cap [u] 256 )
    // One HttpRequest per CONNECTION, refilled in place by every parse:
    // its four line Strings keep their capacity across requests, and
    // its Header objects — Strings and all — cycle through `spare`
    // (request_recycle moves them there, the next parse takes them
    // back). A request therefore allocates nothing on the steady-state
    // keep-alive path; before this the parse and the free together were
    // ~a dozen allocations per request and 10 % of the server's CPU.
    : HttpRequest req ( request_new )
    : ( Vec Header ) spare ( vec_new [Header] )
    // The handler and its `recover` closure, built once per CONNECTION:
    // reading the handler out of the server copies its closure, and a
    // capturing closure literal allocates its environment, so building
    // either per request was two allocations of every response. The
    // closure writes the handler's response into `handed` (captured by
    // pointer — a `: ~` binding the body assigns) and the loop takes it
    // out with mem_replace, leaving the slot empty for the next request.
    // On a panic the slot stays empty: that, not a flag, is how the loop
    // tells the two apart.
    : ( @ HttpResponse HttpRequest ) f . ( __srv s ) handler
    : ~ ? HttpResponse handed @ ?HttpResponse { F }
    : ( @ v ) call_handler \ → v { = handed @ ?HttpResponse { T ( f req ) } }
    : ~ b done F
    : ~ i n_served 0
    ~ ! done {
        : !i HttpReqErr ph ( _read_request_head_into conn carry lim req spare )
        ?? ph {
            T _used → {
                // Busy from here; a connection the drain shut while it
                // idled is closed unanswered (see "Graceful drain").
                ? ( atomic_cas st 0 1 ) {} { = done T }
                ? ! done {
                    // Snapshot the request-start wall-clock right after the
                    // head is parsed. If the handler + body-completion
                    // exceed `request_total_timeout_ms`, we drop the
                    // handler's response and emit a stock 504 instead. The
                    // check is post-handler only — NURL has no thread-
                    // cancellation primitives, so a genuinely runaway
                    // handler runs to completion regardless.
                    : i req_start_ms ? > req_timeout_ms 0 ( now_ms ) 0
                    : b body_ok ( _finish_body conn req carry body_max )
                    ? body_ok {
                        // Upgrade hook (e.g. WebSocket) gets first crack. If it takes
                        // over the connection, run nothing else and let the loop end
                        // so the server closes the finished conn.
                        : ~ b __ws_handled F
                        ? g_ws_upgrade_set {
                            : ( @ b TcpConn HttpRequest ) __upf . g_ws_upgrade fn
                            ? ( __upf conn req ) { = __ws_handled T } {}
                        } {}
                        // Streaming hook: same takeover contract as the
                        // upgrade hook, for chunked/SSE/NDJSON responses.
                        ? & ! __ws_handled g_stream_hook_set {
                            : ( @ b TcpConn HttpRequest ) __shf . g_stream_hook fn
                            ? ( __shf conn req ) { = __ws_handled T } {}
                        } {}
                        ? __ws_handled { = done T } {
                            : b req_close ( __request_says_close req )
                            // The handler runs under `recover`, so a panic in it
                            // answers 500 and keeps the worker; the message is
                            // logged to stderr. The journal reclaims the owned
                            // values the panic skipped (stdlib/std/panic.nu).
                            : !v PanicInfo pr ( recover call_handler )
                            ?? pr {
                                T _ → {}
                                F p → {
                                    ( nurl_eprintln ( nurl_str_cat `[panic] HTTP handler: ` ( string_data . p msg ) ) )
                                }
                            }
                            : ?HttpResponse got ( mem_replace [? HttpResponse] handed @ ?HttpResponse { F } )
                            // Per-request total timeout enforcement: past the
                            // budget the handler's response is dropped and a 504
                            // goes out instead, with `Connection: close` so the
                            // client does not reuse possibly-corrupted state.
                            : ~ b timed_out F
                            ? > req_timeout_ms 0 {
                                ? > - ( now_ms ) req_start_ms req_timeout_ms { = timed_out T } {}
                            } {}
                            : HttpResponse final_resp ?? got {
                                T r → ? timed_out ( __timeout_response r ) r
                                F → ( response_text 500 `internal server error\n` )
                            }
                            : b resp_close ( __response_says_close final_resp )
                            = n_served + n_served 1
                            // max_req > 0: a cap; 0: no keep-alive (close
                            // after this one); < 0: uncapped.
                            : b at_cap ? > max_req 0 >= n_served max_req == max_req 0
                            // A draining server closes the connection after this response.
                            : b should_close | | | | req_close resp_close at_cap timed_out ( server_draining s )
                            : !v NetErr wr ( __write_response conn final_resp should_close wire )
                            // The written response goes back to this thread's
                            // stash: the next response_new reuses its header Vec,
                            // header Strings and body buffer (response_recycle).
                            ( response_recycle final_resp )
                            ( request_recycle req spare )
                            ?? wr {
                                T _ → {
                                    ? should_close { = done T } {
                                        // Idle again — then look at the
                                        // phase: a drain that began while
                                        // this was busy passed it over.
                                        ( atomic_store st 0 )
                                        ? ( server_draining s ) { = done T } {}
                                    }
                                }
                                F we → {
                                    // A failed response write is invisible to the
                                    // handler (it already returned its status) —
                                    // surface it, or a client-side "failed to
                                    // fetch" has nothing to correlate against.
                                    ( nurl_eprint `http: response write failed (` )
                                    ( nurl_eprint ( net_err_name we ) )
                                    ( nurl_eprintln `) — closing connection` )
                                    = done T
                                }
                            }
                        }
                    } {
                        : HttpResponse er ( response_text 400 `malformed body\n` )
                        : !v NetErr _wr ( __write_response conn er T wire )
                        = done T
                    }
                } {}
            }
            F e → {
                // Distinguish "peer closed cleanly with no request
                // bytes" from "got bytes but they didn't parse". The
                // former is normal (browser closing an idle keep-
                // alive), the latter deserves a 4xx so the client knows
                // we rejected the syntax.
                : s nm ( http_req_err_name e )
                ? != 0 ( nurl_str_eq nm `HttpReqIo` ) {} {
                    : HttpResponse er ( _parse_err_response e )
                    : !v NetErr _wr ( __write_response conn er T wire )
                }
                = done T
            }
        }
    }
}

// Decide whether the bytes at the start of a fresh connection are the
// HTTP/2 connection preface. Reads into `carry` until the answer is
// known: 1 = the full 24-byte preface is in carry, 0 = the first bytes
// are not the preface (carry keeps them for the HTTP/1.1 parser),
// -1 = the peer closed or the read failed before either was certain.
@ __sniff_h2_preface TcpConn conn ( Vec u ) carry → i {
    : s want ( h2_conn_preface )
    : ( Slice u ) want_v ( slice_of_str want )
    : i plen ( h2_conn_preface_len )
    : ~ i verdict -2
    ~ == verdict -2 {
        : i have ( vec_len [u] carry )
        : i lim ? < have plen have plen
        : *u p ( vec_data [u] carry )
        : ~ b same T
        : ~ i k 0
        ~ & same < k lim {
            ? != # i . p k ( slice_byte want_v k ) { = same F } {}
            = k + k 1
        }
        ? ! same { = verdict 0 } {
            ? >= have plen { = verdict 1 } {
                : !i NetErr r ( tcp_read_into conn carry 4096 )
                ?? r {
                    T got → { ? <= got 0 { = verdict -1 } {} }
                    F _ → { = verdict -1 }
                }
            }
        }
    }
    ^ verdict
}

// Serve an HTTP/2 connection whose preface (and possibly more) is already
// in `carry`. Takes ownership of carry. The handler contract is the one
// HTTP/1.1 uses — `( @ HttpResponse HttpRequest )` — so routes,
// middleware and the DoS gate around this call see no difference; the
// request-body cap comes from the same HttpLimits. A protocol error has
// already been answered with GOAWAY inside h2_conn_serve; there is
// nothing further to write, the caller closes the socket.
@ __serve_h2 HttpServer s TcpConn conn sink ( Vec u ) carry → v {
    : HttpLimits lim . ( __srv s ) limits
    : !H2Connection H2ConnErr cr ( h2_conn_new_buffered conn carry . lim body_default_max )
    ?? cr {
        T h2c → {
            : ~ H2Connection active h2c
            : ( @ b ) draining \ → b { ^ ( server_draining s ) }
            : !v H2ConnErr sr ( h2_conn_serve_drain active . ( __srv s ) handler draining )
            ?? sr { T _ → {} F _ → {} }
            ( h2_conn_finish active )
        }
        F _ → {}
    }
}

// ── server_run ───────────────────────────────────────────────────────
//
// Drive `server_run_once` in a tight loop until the listener stops.
// Returns Ok on a clean stop (NetClosed / NetAccept after
// server_stop), Err on infrastructure failure mid-flight.

@ server_run HttpServer s → !v NetErr {
    // Retain the listener for the duration of the loop. `server_stop`
    // fired from another thread closes the listener fd + wakes the
    // blocked accept, but its struct free must wait until this thread
    // has returned from `tcp_accept` and stopped reading the handle —
    // without the ref, the close frees the struct mid-poll
    // (heap-use-after-free, observed under ASan). Same contract
    // `server_run_async` already follows for its accept fiber.
    ( tcp_listener_retain . ( __srv s ) listener )
    // Loop forever (until either a clean stop or a real error). One
    // NURL compiler quirk still shapes this implementation:
    //   * Multiple early-`^`-returns inside `?? r { T → … F → … }` arms
    //     leave a phi-with-only-undef-incomings dangling before the
    //     loop_exit branch (terminator missing).
    // The structure below works around it: stash a `done` boolean plus
    // a mutable `last_err` enum (now legal after the 2026-05-14 fix to
    // mutable enum bindings) and emit a single Result construction past
    // the loop.
    : ~ b done F
    : ~ b had_err F
    : ~ NetErr last_err NetClosed
    ~ ! done {
        : !v NetErr r ( server_run_once s )
        ?? r {
            T _ → {}
            F e → {
                : s nm ( net_err_name e )
                ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
                    = done T
                } {
                    // A failed TLS handshake is a per-CONNECTION event (the
                    // pure-TLS handshake runs inside tcp_accept): a port
                    // scanner or a plain-HTTP probe against the TLS port
                    // must not take the listener down. Keep serving.
                    ? != 0 ( nurl_str_eq nm `NetTlsHandshake` ) {} {
                        = last_err e
                        = had_err T
                        = done T
                    }
                }
            }
        }
    }
    ( tcp_listener_release . ( __srv s ) listener )
    ? had_err
    { ^ @ !v NetErr { F last_err } }
    {}
    ^ @ !v NetErr { T 0 }
}

// ── server_run_pool — thread-per-worker model ─────────────────────────
//
// Spawn `n_workers` threads, each looping `server_run_once` against the
// shared listener. Both POSIX accept(2) and Win32 accept are thread-
// safe — the kernel hands at most one accepted connection to a single
// caller, so workers do not need a userland mutex around accept.
//
// Shutdown: caller invokes `server_stop s` (typically from another
// thread, e.g. a signal handler or a control endpoint registered as a
// regular route). Closing the listener causes every worker's
// `tcp_accept` to fail with NetClosed / NetAccept; each worker then
// exits its loop. `server_run_pool` joins all workers and returns Ok.
//
// `n_workers <= 1` short-circuits to plain `server_run` (no threads
// spawned, useful when the caller wants a uniform entry-point but
// flips the worker count via config).
//
// Memory model: each worker captures `s` by value. HttpServer is
// `{ TcpListener, ( @ ... ) handler }` — the listener handle is a
// shared kernel FD via the `s raw` pointer; the handler closure is
// shared via the captured (fn_ptr, env_ptr) pair. Concurrent handler
// invocations must guard their own shared state (this layer guarantees
// at-most-N concurrent calls but no synchronisation around them).
//
// Limitations (Phase 5 MVP — addressed in Phase 7/8):
//   * No per-worker idle timeout (slowloris can pin one worker).
//   * Worker pool size is fixed; no backpressure if all workers are
//     stuck on slow handlers (new connections sit in the kernel's
//     accept queue until backlog fills).
//   * `server_stop` makes accept() fail immediately and lets open
//     connections run until they close; `server_drain` is the graceful
//     stop (idle connections closed, in-flight requests finished with
//     `Connection: close`, a deadline for the rest).
@ server_run_pool HttpServer s i n_workers → !v NetErr {
    ? <= n_workers 1 { ^ ( server_run s ) } {}

    // Retain the listener across the workers' whole lifetime. Workers
    // blocked in `tcp_accept` hold no reference of their own, so a
    // `server_stop` fired from another thread used to free the
    // listener struct while every worker was still polling it
    // (heap-use-after-free at runtime.c's shutting_down check). The
    // ref spans spawn → join; the release below runs only after no
    // worker can touch the handle. Same contract `server_run_async`
    // follows for its accept fiber.
    ( tcp_listener_retain . ( __srv s ) listener )

    // The workers' handles, joined below.
    : ( Vec Thread ) thandles ( vec_with_cap [Thread] n_workers )

    // Worker body: identical to server_run's loop, just inlined here so
    // we don't have to make `s` a parameter (closure capture is the
    // simpler shape than a top-level @-fn + manual env build).
    : ( @ v ) worker \ → v {
        : ~ b done F
        ~ ! done {
            : !v NetErr r ( server_run_once s )
            ?? r {
                T _ → {}
                F e → {
                    : s nm ( net_err_name e )
                    ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
                        = done T
                    } {
                        // Per-connection TLS handshake failures keep the
                        // worker alive (see server_run); any other NetErr is
                        // treated as a fatal worker-level failure. Phase 8
                        // will replace this with a per-error policy
                        // (continue on transient, exit on listener-level).
                        ? != 0 ( nurl_str_eq nm `NetTlsHandshake` ) {} { = done T }
                    }
                }
            }
        }
    }

    : ~ i j 0
    ~ < j n_workers {
        : !Thread ThreadErr tr ( thread_spawn worker )
        ?? tr {
            T t → { ( vec_push [Thread] thandles t ) }
            // A worker that could not be spawned is simply not joined.
            F _ → {}
        }
        = j + j 1
    }

    // Block until every worker exits (i.e. listener was closed by
    // caller via server_stop, or every accept hit a fatal NetErr).
    = j 0
    ~ < j ( vec_len [Thread] thandles ) {
        ?? ( vec_get [Thread] thandles j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( tcp_listener_release . ( __srv s ) listener )
    ^ @ !v NetErr { T 0 }
}

// ── server_run_async — fiber-driven (Phase 7) ─────────────────────────
//
// Per-conn fiber instead of per-conn thread. Accept fibers (one per runtime
// worker, server_set_acceptors) loop on
// the listener; each successful accept spawns a *handler fiber* that
// runs the existing `_serve_keepalive_loop` — which transparently
// goes through `tcp_read_chunk` / `tcp_write_all`, both of which are
// now context-aware (fiber → park on the reactor; thread → block).
// So no duplication of the keep-alive loop: same code path, different
// concurrency primitive.
//
// Caller is responsible for the runtime lifecycle. Typical shape:
//
//   ( runtime_init 0 )                 // 0 = default worker count
//   : !v NetErr r ( server_run_async server )
//   ( runtime_shutdown )
//
// `server_run_async` returns when the accept loop exits (listener
// closed via `server_stop` from a signal handler, or accept failed
// fatally). The conn fibers that were in flight at that point keep
// running on the workers; `runtime_shutdown` then joins them.
//
// Memory model: same as server_run_pool. Each conn fiber captures the
// HttpServer handle by value (it's an opaque pointer-handle); concurrent
// handler invocations must guard their own shared state.
//
// v1 scope (matching docs/ASYNC.md Phase 7):
//   * No per-request total timeout enforcement beyond what the
//     existing keep-alive loop already does (it's the same loop).
//   * No paired idle-timer fiber yet — slowloris defence relies on
//     `tcp_set_timeout`'s per-recv deadline, which under async mode
//     surfaces as NetTimeout on read and ends the conn fiber.
//   * Graceful stop: `server_drain` (see "Graceful drain") — the accept
//     fiber ends, idle connections close, in-flight ones finish.

$ `stdlib/std/async.nu`

// Per-conn fiber body — the same admission + keep-alive + close path
// every other concurrency model gets (__serve_accepted applies the DoS
// gate and the per-conn idle timeout, then runs the loop over the
// context-aware tcp_read_chunk / tcp_write_all). Lifted to top-level so
// the surrounding accept-loop closure stays simple — nested ":"-binding
// of a closure inside another closure's body provoked an IR-codegen bug
// in earlier sweeps.
@ __async_serve_conn HttpServer s TcpConn c0 → v {
    // Complete the TLS handshake (no-op for plaintext) HERE, on the
    // connection's own fiber — the accept loop hands over the bare
    // transport conn precisely so N clients' handshakes overlap
    // instead of serialising on the accept fiber. On Err the TLS
    // layer has already closed the socket; there is no one to answer.
    : !TcpConn NetErr hs ( tcp_conn_complete_tls . ( __srv s ) listener c0 )
    ?? hs {
        T c → { ( __serve_accepted s c ) }
        F _ → {}
    }
}

// Top-level accept loop. Spawned as a fiber by `server_run_async`;
// per accepted conn it spawns one more fiber that runs the
// per-conn keep-alive loop. Result (NetClosed / NetAccept clean
// shutdown vs. fatal NetErr) flows back through the mutable
// captures of the spawning frame.
@ __async_accept_loop HttpServer s → v {
    : TcpListener listener . ( __srv s ) listener
    : ~ b done F
    ~ ! done {
        // Transport accept only — each conn fiber completes its own TLS
        // handshake (see __async_serve_conn), so handshakes overlap.
        : !TcpConn NetErr cr ( tcp_accept_transport listener )
        ?? cr {
            T c → {
                // spawn_owned: the runtime frees this per-connection
                // closure's env when the conn fiber finishes — with
                // plain `spawn` (env BORROWED) it leaked per accept.
                ( spawn_owned \ → v { ( __async_serve_conn s c ) } )
            }
            F e → {
                // Mirror server_run's policy: a failed TLS handshake is
                // a per-CONNECTION event (a port scanner or plain-HTTP
                // probe against the TLS port) — keep accepting. Any
                // other error means the listener is gone (clean stop)
                // or broken: end the loop. (With the handshake on the
                // conn fiber this arm should not see NetTlsHandshake,
                // but the policy costs nothing to keep.)
                : s nm ( net_err_name e )
                ? != 0 ( nurl_str_eq nm `NetTlsHandshake` ) {} { = done T }
            }
        }
    }
}

@ server_run_async HttpServer s → !v NetErr {
    // Retain the listener for the lifetime of the accept fiber. server_stop
    // (often called from another thread) closes the listener to break the
    // accept loop; the close wakes the parked accept fiber via the reactor,
    // but freeing the listener struct there would race the fiber's next
    // touch of it. The extra ref defers the free until we release it below,
    // after runtime_run has drained every fiber.
    ( tcp_listener_retain . ( __srv s ) listener )
    // One accept fiber per runtime worker (server_set_acceptors), all on
    // the one listener: whichever is woken first takes the connection,
    // the rest find EAGAIN and park again. A single accept fiber made
    // every connection's accept — and the spawn of its fiber — one
    // worker's job at a time; connection churn (oha --disable-keepalive,
    // 20 clients) measured 15–18k → 19–22k conn/s with four, and ~15 %
    // less server CPU per connection. One listener and SO_REUSEPORT
    // listeners per worker measured the same within the noise (shared
    // 4-core host), and the shared listener needs no second socket, works
    // for TLS listeners and stops with the one close: fibers migrate
    // between workers, so a listener per worker buys no affinity here.
    // runtime_run blocks until the accept fibers exit AND every in-flight
    // conn fiber drains (pending=0).
    : ~ i nacc ( atomic_load . ( __srv s ) acceptors )
    ? <= nacc 0 { = nacc ( runtime_worker_count ) } {}
    ? < nacc 1 { = nacc 1 } {}
    : ~ i k 0
    ~ < k nacc {
        ( spawn \ → v { ( __async_accept_loop s ) } )
        = k + k 1
    }
    ( runtime_run )
    ( tcp_listener_release . ( __srv s ) listener )
    ^ @ !v NetErr { T 0 }
}
