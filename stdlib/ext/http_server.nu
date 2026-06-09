// stdlib/ext/http_server.nu — HTTP/1.1 server with keep-alive.
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
//      tcp_accept → __serve_keepalive_loop → close
//                       │
//                       ▼   loops while connection alive
//      __read_request_head → handler → __write_response
//
// API (this revision):
//
//   ( server_new TcpListener listener
//                ( @ HttpResponse HttpRequest ) handler ) → HttpServer
//   ( server_new_with_timeout    listener handler i idle_ms )                      → HttpServer
//   ( server_new_full            listener handler i idle_ms i max_keepalive_reqs ) → HttpServer
//   ( server_default_idle_timeout_ms )       → i      30000 ms
//   ( server_default_max_keepalive_requests ) → i     1000
//   ( server_run_once HttpServer s )                     → ! v NetErr
//   ( server_run      HttpServer s )                     → ! v NetErr
//   ( server_run_pool HttpServer s i n_workers )         → ! v NetErr
//   ( server_stop     HttpServer s )                     → v
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
//   * The handler receives an HttpRequest BORROWED. It must NOT free
//     fields of the request — the server frees the whole request
//     after the handler returns. The handler's returned HttpResponse
//     is OWNED by the server, freed after serialise+write.
//
// Keep-alive policy (Phase 5.4):
//
//   * HTTP/1.1 + no `Connection: close` → connection is reused.
//   * HTTP/1.1 + `Connection: close` (request OR response)  → close.
//   * HTTP/1.0  → close (we do not honour `Connection: keep-alive`
//     opt-in for HTTP/1.0; clients that need keep-alive must speak
//     HTTP/1.1).
//   * After `max_keepalive_requests` reuses on one connection
//     (default 1000), the server forces close — a defence-in-depth
//     cap against a single client monopolising a worker.
//   * The per-conn idle timeout (`tcp_set_timeout`, default 30 s)
//     applies to EVERY recv on the connection — including the wait
//     for the next request between calls. So a connection that
//     idles past the deadline auto-closes, freeing the worker.
//
// Pipelining (HTTP/1.1 §6.3.2):
//
//   * The keep-alive loop owns one connection-level `Vec[u] carry`
//     that survives across requests. `__read_request_head` reads
//     into carry until `parse_request_head` succeeds, then drops
//     the consumed-by-the-head bytes from carry's front — anything
//     past the head (request body + a pipelined successor's bytes)
//     stays in carry. `__finish_body` then drains exactly
//     Content-Length bytes off carry's front into `req.body`,
//     topping up from the socket if short. Any remaining bytes in
//     carry feed the next iteration's `__read_request_head`
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
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/dos.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// ── HttpServer struct + lifecycle ─────────────────────────────────────
//
// Six knobs at v2.1+:
//   * idle_timeout_ms          — per-conn recv deadline. 0 = OS default.
//   * max_keepalive_requests   — per-conn request reuse cap. 0 = no keep-alive.
//   * limits                   — head / header-count / body byte caps
//                                (consulted by parse_request_head_with /
//                                 __finish_body's body-byte loop).
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

: HttpServer {
    TcpListener listener
    ( @ HttpResponse HttpRequest ) handler
    i idle_timeout_ms
    i max_keepalive_requests
    HttpLimits limits
    i request_total_timeout_ms
    // DoS state — raw handle to runtime-side NurlDosState (mutex-
    // protected concurrent + per-IP counters). 0 = DoS protection
    // disabled (the historical default; matches every constructor
    // except `server_new_with_dos`). When non-zero, server_run_once
    // takes the acquire/release path that rejects connections over
    // the configured caps. Multiple workers in server_run_pool share
    // the same state via the shared HttpServer value.
    s dos_state
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

// Default cap on keep-alive request reuse per connection. After this
// many requests on a single conn, the server forces `Connection:
// close` and drops the conn. Defence-in-depth — a single misbehaving
// client cannot monopolise one worker forever. Pass 0 to disable
// keep-alive entirely (every connection serves exactly one request,
// matching pre-Phase-5.4 behaviour).
@ server_default_max_keepalive_requests → i { ^ 1000 }

// Per-request total timeout default. 0 = disabled (matches pre-Phase-8
// behaviour; the per-conn idle timeout still bounds slow reads).
@ server_default_request_total_timeout_ms → i { ^ 0 }

@ server_new TcpListener listener ( @ HttpResponse HttpRequest ) handler → HttpServer {
    ^ @ HttpServer { listener handler
        ( server_default_idle_timeout_ms )
        ( server_default_max_keepalive_requests )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        # s 0 }
}

@ server_new_with_timeout TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms → HttpServer {
    ^ @ HttpServer { listener handler idle_timeout_ms
        ( server_default_max_keepalive_requests )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        # s 0 }
}

@ server_new_full TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms i max_keepalive_requests → HttpServer {
    ^ @ HttpServer { listener handler idle_timeout_ms max_keepalive_requests
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        # s 0 }
}

// `server_new_complete` — every knob explicit. Use when overriding
// parser limits and/or per-request total timeout. See the struct comment
// for what each field controls.
@ server_new_complete TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms i max_keepalive_requests HttpLimits limits i request_total_timeout_ms → HttpServer {
    ^ @ HttpServer { listener handler idle_timeout_ms max_keepalive_requests limits request_total_timeout_ms # s 0 }
}

// DoS-aware constructor. Allocates a NurlDosState on the runtime side
// configured with the given caps; server_stop disposes it. All other
// knobs use defaults — combine with the keep-alive / timeout knobs
// after construction by directly mutating the returned struct, or
// extend this helper if a uniform full-knob variant is needed later.
@ server_new_with_dos TcpListener listener ( @ HttpResponse HttpRequest ) handler DosLimits dos_limits → HttpServer {
    : i st ( dos_state_new . dos_limits max_concurrent_conns
    . dos_limits max_conns_per_ip )
    ^ @ HttpServer { listener handler
        ( server_default_idle_timeout_ms )
        ( server_default_max_keepalive_requests )
        ( http_default_limits )
        ( server_default_request_total_timeout_ms )
        # s st }
}

// Snapshot the current active-connection count — useful for /metrics
// observability endpoints. Returns 0 when DoS protection is disabled.
@ server_active_conn_count HttpServer s → i {
    : s rp . s dos_state
    : i raw # i rp
    ? == raw 0 { ^ 0 } {}
    ^ ( dos_state_active raw )
}

@ server_stop HttpServer s → v {
    : s rp . s dos_state
    : i raw # i rp
    ? != raw 0 { ( dos_state_free raw ) } {}
    ( tcp_close_listener . s listener )
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
            : ( Vec u ) tail ( vec_with_cap [u] remaining )
            : *u p ( vec_data [u] buf )
            : ~ i k 0
            ~ < k remaining {
                ( vec_push [u] tail . p + n k )
                = k + k 1
            }
            ( vec_clear [u] buf )
            ( vec_extend [u] buf tail )
            ( vec_free [u] tail )
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
// request's body + pipelined successor) for `__finish_body` / the next
// iteration to consume. The returned `head.body` is left untouched
// (empty) — the body lives in carry until `__finish_body` drains it.
//
// On socket error: returns Err(HttpReqIo). On unrecoverable parse
// error: returns the matching HttpReqErr (TooLarge / Malformed /
// UnsupportedVersion). Carry's state is unspecified on Err (caller is
// about to close).

@ __read_request_head TcpConn conn ( Vec u ) carry HttpLimits limits → !ParsedHeadOk HttpReqErr {
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
                    // Incomplete = keep reading. Top up carry.
                    : !( Vec u ) NetErr r ( tcp_read_chunk conn 4096 )
                    ?? r {
                        T chunk → {
                            : i got ( vec_len [u] chunk )
                            ( vec_extend [u] carry chunk )
                            ( vec_free [u] chunk )
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
        : !( Vec u ) NetErr r ( tcp_read_chunk conn 4096 )
        ?? r {
            T chunk → {
                : i got ( vec_len [u] chunk )
                ( vec_extend [u] carry chunk )
                ( vec_free [u] chunk )
                ? <= got 0 { = ok F } {}
            }
            F _ → { = ok F }
        }
    }
    ^ ok
}

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
                : !( Vec u ) NetErr r ( tcp_read_chunk conn 4096 )
                ?? r {
                    T chunk → {
                        : i got ( vec_len [u] chunk )
                        ( vec_extend [u] carry chunk )
                        ( vec_free [u] chunk )
                        ? <= got 0 { = stop T } {}
                    }
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
            : String szline ( __bsubstr carry 0 crlf )
            ( __vec_drop_front_u carry + crlf 2 )
            : !i ParseErr szr ( __parse_hex_size szline )
            ( string_free szline )
            ?? szr {
                T n → {
                    ? < n 0 { = ok F } {
                        ? == n 0 {
                            // Terminating chunk: consume trailer lines up to
                            // the closing empty line.
                            : ~ b tdone F
                            ~ & ok ! tdone {
                                : i tc ( __carry_find_crlf conn carry 8192 )
                                ? < tc 0 { = ok F } {
                                    ( __vec_drop_front_u carry + tc 2 )
                                    ? == tc 0 { = tdone T } {}
                                }
                            }
                            = done T
                        } {
                            ? > + ( vec_len [u] . req body ) n body_max { = ok F } {
                                // Need n bytes of data + the trailing CRLF.
                                ? ( __carry_ensure conn carry + n 2 ) {
                                    : *u cd ( vec_data [u] carry )
                                    : ~ i k 0
                                    ~ < k n {
                                        ( vec_push [u] . req body & 255 # i . cd k )
                                        = k + k 1
                                    }
                                    ( __vec_drop_front_u carry + n 2 )
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

@ __finish_body TcpConn conn HttpRequest req ( Vec u ) carry i body_max → b {
    // Transfer-Encoding takes precedence (RFC 7230 §3.3.3). A chunked body
    // MUST be drained here too — otherwise its bytes are left in `carry`,
    // handed to the handler as an empty body, and mis-parsed as the next
    // request on a keep-alive connection (a desync / smuggling vector).
    : ?String te ( header_get . req headers `Transfer-Encoding` )
    ?? te {
        T tev → {
            : String te_lc ( string_to_lower tev )
            : b is_chunked != 0 ( nurl_str_eq ( string_data te_lc ) `chunked` )
            ( string_free te_lc )
            ( string_free tev )
            ? is_chunked { ^ ( __finish_body_chunked conn req carry body_max ) } {}
            // Non-chunked Transfer-Encoding is unsupported (and CL+TE is
            // already rejected at head parse) — fail the body read.
            ^ F
        }
        F _ → {}
    }
    : ?String cl ( header_get . req headers `Content-Length` )
    ?? cl {
        T clv → {
            : !i ParseErr nr ( string_to_int clv )
            ( string_free clv )
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
                    : !( Vec u ) HttpReqErr more ( __read_n_bytes conn need )
                    ?? more {
                        T extra → {
                            ( vec_extend [u] . req body extra )
                            ( vec_free [u] extra )
                            ^ T
                        }
                        F _ → ^ F
                    }
                }
                F _ → ^ F
            }
        }
        F _ → ^ T  // No Content-Length: nothing more to read.
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
// Frees `r` after serialise+write regardless of outcome.

@ __write_response TcpConn conn HttpResponse r b force_close → !v NetErr {
    ? force_close {
        ( response_set_header r `Connection` `close` )
    } {}
    : ( Vec u ) wire ( response_serialize r )
    : !v NetErr wr ( tcp_write_all conn wire )
    ( vec_free [u] wire )
    ( http_response_free r )
    ^ wr
}

// Build a stock 4xx error response for parse failures.
@ __parse_err_response HttpReqErr e → HttpResponse {
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
    : ~ i k 0
    ~ < k la {
        : i ca ( string_get value k )
        : i cb ( nurl_str_get lit k )
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
@ __request_says_close HttpRequest req → b {
    : s ver ( string_data . req version )
    ? == 0 ( nurl_str_eq ver `HTTP/1.1` ) { ^ T } {}
    : ?String hv ( header_get . req headers `Connection` )
    ?? hv {
        T value → {
            : b says_close ( __header_value_eq_ci value `close` )
            ( string_free value )
            ^ says_close
        }
        F empty → { ( string_free empty ) ^ F }
    }
}

// Returns T if the response carries `Connection: close`. The handler
// can opt this connection out of keep-alive by setting that header
// explicitly.
@ __response_says_close HttpResponse r → b {
    : ?String hv ( header_get . r headers `Connection` )
    ?? hv {
        T value → {
            : b says_close ( __header_value_eq_ci value `close` )
            ( string_free value )
            ^ says_close
        }
        F empty → { ( string_free empty ) ^ F }
    }
}

// ── server_run_once ──────────────────────────────────────────────────
//
// Single connection lifecycle: accept, then drive the keep-alive
// loop until the conn drains (peer close, idle timeout, explicit
// `Connection: close`, or the per-conn request cap fires). Returns
// Ok(0) for every cleanly-drained connection. Returns Err only when
// `tcp_accept` itself fails — per-request write/parse errors close
// the connection but do not bubble out.

@ server_run_once HttpServer s → !v NetErr {
    : !TcpConn NetErr ar ( tcp_accept . s listener )
    ?? ar {
        T conn → {
            // DoS gate. If the server was constructed with
            // server_new_with_dos, dos_state holds a runtime-side
            // counter+IP-table. acquire returns 0 when the global or
            // per-IP cap is exceeded; we close the conn immediately
            // (no canned 503 — that costs more than rejecting at the
            // TCP layer). On accept: extract peer IP (best-effort —
            // tcp_peer_addr returns "ip:port"; we split on ':'). On
            // release: pass the same IP back so the counter unwinds.
            : s ds_rp . s dos_state
            : i ds_raw # i ds_rp
            : ~ s peer_ip ``
            ? != ds_raw 0 {
                : s addr ( tcp_peer_addr conn )
                : i an ( nurl_str_len addr )
                : ~ i colon -1
                : ~ i k 0
                ~ & == colon -1 < k an {
                    ? == 58 ( nurl_str_get addr k ) { = colon k } {}
                    = k + k 1
                }
                ? > colon 0 {
                    : String ip_only ( string_new )
                    : ~ i j 0
                    ~ < j colon {
                        ( string_push_char ip_only ( nurl_str_get addr j ) )
                        = j + j 1
                    }
                    = peer_ip ( string_data ip_only )
                    // Note: ip_only String leaks here — peer_ip references
                    // the same buffer and we need it alive through the
                    // serve loop. The DoS-protection lifetime budget for
                    // a connection makes this acceptable; freed by the
                    // process when the conn closes via tcp_close_conn.
                } { = peer_ip addr }
                : i ok ( dos_state_try_acquire ds_raw peer_ip )
                ? == ok 0 {
                    ( tcp_close_conn conn )
                    ^ @ !v NetErr { T 0 }
                } {}
            } {}
            : i ito . s idle_timeout_ms
            ? > ito 0 { ( tcp_set_timeout conn ito ) } {}
            ( __serve_keepalive_loop s conn )
            ? != ds_raw 0 { ( dos_state_release ds_raw peer_ip ) } {}
            ( tcp_close_conn conn )
            ^ @ !v NetErr { T 0 }
        }
        F e → ^ @ !v NetErr { F e }
    }
}

// The per-connection request loop. Walks request → handler →
// response → repeat until any of the following happens:
//
//   * `__read_request_head` fails with HttpReqIo (peer closed
//     cleanly between requests, or the recv timeout fired). No
//     response is written — connection dies silently.
//   * `__read_request_head` fails with any other parse error. We
//     write the canned 4xx response, then close.
//   * `__finish_body` fails. We write a 400, then close.
//   * The request OR response carries `Connection: close`. We write
//     the response (forcing `Connection: close`), then close.
//   * `n_served` reaches `max_keepalive_requests`. Same as the
//     close-after-response path — the cap is defence-in-depth, not
//     a polished policy.
//   * Any `__write_response` returns Err. We close.
//
// The function returns `v` rather than `! v NetErr` because none of
// these per-request errors are interesting at the listener level —
// they all just mean "this connection is done, accept the next one".

@ __serve_keepalive_loop HttpServer s TcpConn conn → v {
    : i max_req . s max_keepalive_requests
    : HttpLimits lim . s limits
    : i body_max . lim body_default_max
    : i req_timeout_ms . s request_total_timeout_ms
    // One connection-level carry buffer, owned here, freed at the
    // bottom. Survives across keep-alive iterations so a pipelined
    // successor's bytes (or any leftover past a request's body) are
    // visible to the next __read_request_head call without re-reading
    // from the socket.
    : ( Vec u ) carry ( vec_with_cap [u] 4096 )
    : ~ b done F
    : ~ i n_served 0
    ~ ! done {
        : !ParsedHeadOk HttpReqErr ph ( __read_request_head conn carry lim )
        ?? ph {
            T pho → {
                // Snapshot the request-start wall-clock right after the
                // head is parsed. If the handler + body-completion
                // exceed `request_total_timeout_ms`, we drop the
                // handler's response and emit a stock 504 instead. The
                // check is post-handler only — NURL has no thread-
                // cancellation primitives, so a genuinely runaway
                // handler runs to completion regardless.
                : i req_start_ms ? > req_timeout_ms 0 ( now_ms ) 0
                : HttpRequest req . pho head
                : b body_ok ( __finish_body conn req carry body_max )
                ? body_ok {
                    : b req_close ( __request_says_close req )
                    : ( @ HttpResponse HttpRequest ) f . s handler
                    // Wrap the handler in `recover` so a panic inside
                    // the handler doesn't kill the worker thread. On
                    // panic the default `resp` (500) flows out to the
                    // client; the captured message is logged to stderr.
                    // Owned allocations inside the handler that didn't
                    // run their auto-drop leak — see
                    // stdlib/std/panic.nu's header for the cost model.
                    : ~ HttpResponse resp ( response_text 500 `internal server error\n` )
                    : !v PanicInfo pr ( recover \ → v { = resp ( f req ) } )
                    ?? pr {
                        T _ → {}
                        F p → {
                            ( nurl_eprintln ( nurl_str_cat `[panic] HTTP handler: ` ( string_data . p msg ) ) )
                            ( panic_info_free p )
                        }
                    }
                    // Per-request total timeout enforcement: free the
                    // handler's response and substitute 504 if we blew
                    // the budget. `should_close` forces `Connection:
                    // close` so the client doesn't reuse possibly-
                    // corrupted state.
                    : ~ HttpResponse final_resp resp
                    : ~ b timed_out F
                    ? > req_timeout_ms 0 {
                        : i elapsed - ( now_ms ) req_start_ms
                        ? > elapsed req_timeout_ms {
                            ( http_response_free resp )
                            = final_resp ( response_text 504 `request total-timeout exceeded\n` )
                            = timed_out T
                        } {}
                    } {}
                    : b resp_close ( __response_says_close final_resp )
                    = n_served + n_served 1
                    : b at_cap ? > max_req 0 >= n_served max_req T
                    : b should_close | | | req_close resp_close at_cap timed_out
                    : !v NetErr wr ( __write_response conn final_resp should_close )
                    ( request_free req )
                    ?? wr {
                        T _ → {
                            ? should_close { = done T } {}
                        }
                        F _ → { = done T }
                    }
                } {
                    : HttpResponse er ( response_text 400 `malformed body\n` )
                    : !v NetErr _wr ( __write_response conn er T )
                    ( request_free req )
                    = done T
                }
            }
            F e → {
                // Distinguish "peer closed cleanly with no request
                // bytes" from "got bytes but they didn't parse". The
                // former is normal (browser closing an idle keep-
                // alive), the latter deserves a 4xx so the client knows
                // we rejected the syntax.
                : s nm ( http_req_err_name e )
                ? != 0 ( nurl_str_eq nm `HttpReqIo` ) {} {
                    : HttpResponse er ( __parse_err_response e )
                    : !v NetErr _wr ( __write_response conn er T )
                }
                = done T
            }
        }
    }
    ( vec_free [u] carry )
}

// ── server_run ───────────────────────────────────────────────────────
//
// Drive `server_run_once` in a tight loop until the listener stops.
// Returns Ok on a clean stop (NetClosed / NetAccept after
// server_stop), Err on infrastructure failure mid-flight.

@ server_run HttpServer s → !v NetErr {
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
                    = last_err e
                    = had_err T
                    = done T
                }
            }
        }
    }
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
//   * No graceful drain — `server_stop` makes accept() fail
//     immediately; a worker mid-request finishes that request, then
//     exits. That's fine but observable as a small lag.
@ server_run_pool HttpServer s i n_workers → !v NetErr {
    ? <= n_workers 1 { ^ ( server_run s ) } {}

    // Storage for n thread handles, indexed by worker number.
    : s thandles ( nurl_alloc * n_workers 8 )

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
                        // Any other NetErr is treated as a fatal worker-level
                        // failure. Phase 8 will replace this with a per-error
                        // policy (continue on transient, exit on listener-level).
                        = done T
                    }
                }
            }
        }
    }

    : ~ i j 0
    ~ < j n_workers {
        : !Thread ThreadErr tr ( thread_spawn worker )
        ?? tr {
            T t → {
                : s tp . t raw
                : i traw # i tp
                // nurl_poke uses SLOT indexing (×8 stride internally);
                // pass `j`, NOT `j * 8`. Pre-fix this overran the
                // 8×n_workers byte buffer by writing at byte offset
                // j*64 — survived for small worker counts thanks to
                // malloc-arena slack, crashed once the spillover hit
                // anything load-bearing.
                ( nurl_poke thandles j traw )
            }
            F _ → {
                // Spawn failure → leave a NULL slot so the join phase skips it.
                ( nurl_poke thandles j 0 )
            }
        }
        = j + j 1
    }

    // Block until every worker exits (i.e. listener was closed by
    // caller via server_stop, or every accept hit a fatal NetErr).
    = j 0
    ~ < j n_workers {
        : i traw ( nurl_peek thandles j )
        ? != traw 0 {
            : s tp # s traw
            : Thread t @ Thread { tp }
            ( thread_join t )
        } {}
        = j + j 1
    }
    ( nurl_free thandles )
    // Every worker has joined and the threads shared this one `worker`
    // closure's heap-captured env (thread_spawn BORROWS it — it is never
    // freed by the thread). Release it now that no worker can touch it,
    // mirroring the per-server cleanup contract.
    : *u worker_env # *u worker 1
    ( nurl_free # s worker_env )
    ^ @ !v NetErr { T 0 }
}

// ── server_run_async — fiber-driven (Phase 7) ─────────────────────────
//
// Per-conn fiber instead of per-conn thread. One accept fiber loops on
// the listener; each successful accept spawns a *handler fiber* that
// runs the existing `__serve_keepalive_loop` — which transparently
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
//   * No graceful drain on shutdown — workers exit their loops as
//     soon as their currently-running fiber yields/completes.

$ `stdlib/std/async.nu`

// Per-conn fiber body — runs the existing keep-alive loop (which
// uses the now-context-aware tcp_read_chunk / tcp_write_all) then
// closes. Lifted to top-level so the surrounding accept-loop closure
// stays simple — nested ":"-binding of a closure inside another
// closure's body provoked an IR-codegen bug in earlier sweeps.
@ __async_serve_conn HttpServer s TcpConn c → v {
    ( __serve_keepalive_loop s c )
    ( tcp_close_conn c )
}

// Top-level accept loop. Spawned as a fiber by `server_run_async`;
// per accepted conn it spawns one more fiber that runs the
// per-conn keep-alive loop. Result (NetClosed / NetAccept clean
// shutdown vs. fatal NetErr) flows back through the mutable
// captures of the spawning frame.
@ __async_accept_loop HttpServer s → v {
    : TcpListener listener . s listener
    : ~ b done F
    ~ ! done {
        : !TcpConn NetErr cr ( tcp_accept listener )
        ?? cr {
            T c → {
                ( spawn \ → v { ( __async_serve_conn s c ) } )
            }
            F e → { = done T }
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
    ( tcp_listener_retain . s listener )
    // Spawn one accept fiber; runtime_run blocks until the accept
    // fiber exits AND every in-flight conn fiber drains (pending=0).
    // Bind the closure so we can free its heap-captured env afterwards:
    // `spawn` BORROWS the env (the fiber runtime never frees it), so a
    // fire-and-forget inline closure here would leak its env once per
    // server start. runtime_run returns only after the accept fiber has
    // exited, so the env is safe to release at that point.
    : ( @ v ) accept_fiber \ → v { ( __async_accept_loop s ) }
    ( spawn accept_fiber )
    ( runtime_run )
    ( tcp_listener_release . s listener )
    : *u accept_env # *u accept_fiber 1
    ( nurl_free # s accept_env )
    ^ @ !v NetErr { T 0 }
}
