// stdlib/ext/mcp_http.nu — Streamable HTTP transport for MCP.
//
// Layered on top of `stdlib/ext/mcp.nu` (envelope + shape primitives)
// and the Phase 4–6 HTTP server stack (`http_server.nu` +
// `http_request.nu` + `http_response.nu`). Kept in a separate file so
// stdio-only MCP servers don't drag in the HTTP / TCP machinery just
// to read and write `\n`-delimited JSON-RPC.
//
// **Transport summary** (per the MCP "Streamable HTTP" spec, see
// https://modelcontextprotocol.io/specification/2025-11-25/basic/transports):
//
//   POST /mcp     — client sends a JSON-RPC request OR a top-level
//                   array of requests (batch); server replies with the
//                   matching JSON-RPC response (HTTP 200, application/
//                   json), an array of non-notification responses for
//                   a batch, OR — for a notification or batch of pure
//                   notifications — an empty 202 Accepted body.
//   GET  /mcp     — opens a server-to-client SSE channel. v2 ships
//                   a single-event stub (HTTP 200, Content-Type
//                   `text/event-stream`, body = one `event: ready`
//                   frame, then connection close) so clients can
//                   detect the protocol. A real continuous stream
//                   requires a notification queue + custom accept
//                   loop with `response_begin_chunked` — tracked as
//                   the next-after-v2 extension.
//   Mcp-Session-Id — Forward-compat session header. If the client
//                   sends `Mcp-Session-Id: <opaque>` on a request,
//                   the handler echoes it back on the response. No
//                   per-session state store yet — the value is
//                   round-tripped verbatim.
//   DELETE /mcp   — client closes a session. Stateless MVP returns
//                   204 No Content with no bookkeeping.
//
// **What this module provides.**
//
//   1. `mcp_http_handler dispatch → ( @ HttpResponse HttpRequest )`
//      — wraps a user-supplied dispatch closure into an HTTP handler
//      that's drop-in compatible with `server_new` (Phase 4) or with
//      a route-registered closure on `http_router.nu` (Phase 6).
//
//   2. `mcp_server_run_http host port dispatch → ! v NetErr` — the
//      one-line convenience: open a loopback listener on `host:port`,
//      mount the dispatcher on POST `/mcp`, add permissive CORS for
//      browser-based clients, run forever. Returns when the listener
//      is stopped or hits a fatal accept error.
//
//   3. `mcp_dispatch_response_to_http`-style helpers if/when batch
//      requests or partial streaming need to layer on top — for the
//      MVP we keep it to the two entry points above.
//
// **The `dispatch` closure.**
//
// User-supplied. Signature:
//
//   ( @ ? Json Json ) dispatch
//   // takes one parsed JSON-RPC request (BORROWED) and returns:
//   //   Some(json)  — server replies HTTP 200 application/json, body
//   //                 = `json_stringify json`. The Json is then freed
//   //                 by the handler.
//   //   None        — request was a notification; server replies
//   //                 HTTP 202 Accepted, no body.
//
// The dispatcher decides "notification vs. request" itself by checking
// `( json_obj_get req "id" )` — same logic that the stdio version
// uses in `examples/mcp_echo_server.nu`'s `handle` function. The HTTP
// transport simply translates whatever `dispatch` returns into the
// appropriate HTTP envelope.
//
// Memory model:
//   * `dispatch` BORROWS the request Json — the handler frees it
//     after `dispatch` returns regardless of which arm fired.
//   * `dispatch` returns OWNED Json on the Some arm — the handler
//     consumes it (json_stringify reads, then json_free) and writes
//     the wire bytes.
//   * On the None arm, the placeholder Json (a JNull node) is freed
//     by the handler. Cost is one tiny allocation per notification.
//
// Limitations / not yet implemented (each is straight-line work, just
// outside the MVP):
//   * GET /mcp continuous SSE stream — v2 returns a single ready
//     event then closes the connection. Pushing notifications over
//     time needs a notification queue + Last-Event-ID resumption + a
//     custom accept loop using the chunked streaming primitives
//     (`response_begin_chunked` / `_write_chunk` / `_end_chunked`).
//   * Mcp-Session-Id state pinning — v2 echoes the header but stores
//     no per-session state. Stateful dispatch needs a session-id →
//     state map + per-session dispatcher closure.
//   * (BATCH NOW SHIPPED) Top-level `[req1, req2, ...]` arrays route
//     through `dispatch` per element; non-notification responses are
//     collected into an array response; pure-notification batches
//     return 202; empty batches return invalid_request per JSON-RPC.
//   * `Accept: text/event-stream` content-negotiation upgrade for
//     POST — fall back to JSON for simplicity. The mainstream clients
//     accept either.
//   * Authorization (Bearer tokens) — easy to layer on as middleware
//     using `http_router.nu`'s closure-wrapping pattern.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Internal: build a JSON-RPC error response wrapped in HTTP 200 ────
//
// Per the MCP / JSON-RPC convention HTTP 200 is the correct envelope
// for protocol-level errors (parse failure, invalid request); HTTP-
// level non-200 codes are reserved for transport problems. The id is
// JNull when the request was unparseable (no id available).

@ __mcp_http_jsonrpc_error i code s message → HttpResponse {
    : Json id_null @ Json { JNull }
    : Json env ( mcp_response_error id_null code message )
    : HttpResponse r ( response_json 200 env )
    ( json_free id_null )
    ( json_free env )
    ^ r
}

// Permissive CORS layer. Always added by mcp_server_run_http for
// browser-based clients; exposed as a primitive so callers who mount
// MCP on a router can apply it themselves. Adds the headers the MCP
// spec recommends, plus Mcp-Session-Id (forward compat for sessions).

@ __mcp_http_apply_cors HttpResponse r → v {
    ( response_set_header r `Access-Control-Allow-Origin` `*` )
    ( response_set_header r `Access-Control-Allow-Headers` `Content-Type, Authorization, Mcp-Session-Id` )
    ( response_set_header r `Access-Control-Expose-Headers` `Mcp-Session-Id` )
}

// MCP Streamable HTTP content-negotiation: if the client offers
// `text/event-stream` in `Accept` (every official SDK does, since the
// 2025-03-26 spec describes the POST→SSE upgrade as the normal path),
// emit the JSON-RPC reply wrapped in a single SSE `message` event
// rather than a bare `application/json` body. Otherwise fall back to
// plain JSON for legacy clients. CONSUMES `resp_json`.
@ __mcp_http_response_for_json HttpRequest req Json resp_json → HttpResponse {
    : b want_sse F
    : ?String accept ( header_get . req headers `Accept` )
    ?? accept {
        T s → {
            ? ( string_contains s `text/event-stream` ) { = want_sse T } {}
            ( string_free s )
        }
        F e → { ( string_free e ) }
    }
    ? want_sse {
        : String payload ( json_stringify resp_json )
        ( json_free resp_json )
        : String body ( string_with_cap + ( string_len payload ) 28 )
        ( string_push_str body `event: message\r\ndata: ` )
        ( string_push_str body ( string_data payload ) )
        ( string_push_str body `\r\n\r\n` )
        ( string_free payload )
        : HttpResponse r ( response_text 200 ( string_data body ) )
        ( response_set_header r `Content-Type` `text/event-stream` )
        ( response_set_header r `Cache-Control` `no-cache` )
        ( string_free body )
        ^ r
    } {
        : HttpResponse r ( response_json 200 resp_json )
        ( json_free resp_json )
        ^ r
    }
}

// Echo the client-supplied Mcp-Session-Id back on the response. v1
// forwards the header verbatim — there is no per-session state store
// yet, so the field is forward-compat surface for clients that begin
// sending session ids before the server implements pinning.
@ __mcp_http_echo_session HttpRequest req HttpResponse r → v {
    : ?String sid ( header_get . req headers `Mcp-Session-Id` )
    ?? sid {
        T s → {
            ? > ( string_len s ) 0 {
                ( response_set_header r `Mcp-Session-Id` ( string_data s ) )
            } {}
            ( string_free s )
        }
        F _ → {}
    }
}

// ── mcp_http_handler ─────────────────────────────────────────────────
//
// Build an HTTP handler closure from a dispatch closure. Usable as a
// drop-in for `server_new` (Phase 4) or — wrapped for the
// `(HttpRequest, Params)` signature — as a route handler on
// `http_router.nu`.
//
// Method handling:
//   POST   → decode body, parse JSON, call dispatch, format result.
//   GET    → 405 (no SSE notifications stream in MVP).
//   DELETE → 204 (stateless, nothing to delete).
//   OPTIONS → 204 with permissive CORS preflight headers.
//   other  → 405 with Allow header.
//
// Errors return JSON-RPC error envelopes with HTTP 200 (standard
// JSON-RPC convention) for `parse error` and `invalid request`.

@ mcp_http_handler
( @ ?Json Json ) dispatch
→ ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : s rm ( string_data . req method )

        // OPTIONS preflight: short-circuit with permissive CORS.
        ? != 0 ( nurl_str_eq rm `OPTIONS` ) {
            : HttpResponse pre ( response_status_only 204 )
            ( response_set_header pre `Access-Control-Allow-Methods` `POST, GET, DELETE, OPTIONS` )
            ( response_set_header pre `Access-Control-Max-Age` `86400` )
            ( __mcp_http_apply_cors pre )
            ( __mcp_http_echo_session req pre )
            ^ pre
        } {}

        // GET: single-event SSE stub. A real notification stream would
        // need a queue + chunked writes from a custom accept loop — this
        // path advertises the wire protocol (`text/event-stream` + an
        // initial `ready` event) so clients can open the endpoint
        // without a 405. Connection is closed immediately after the
        // single event. v2 extension point.
        ? != 0 ( nurl_str_eq rm `GET` ) {
            : HttpResponse r ( response_text 200 `event: ready\ndata: {"server":"nurl-mcp","streaming":"single-event"}\n\n` )
            ( response_set_header r `Content-Type` `text/event-stream` )
            ( response_set_header r `Cache-Control` `no-cache` )
            ( response_set_header r `Connection` `close` )
            ( __mcp_http_apply_cors r )
            ( __mcp_http_echo_session req r )
            ^ r
        } {}

        // DELETE: stateless — nothing to free. (Forward compat: real
        // session teardown would invalidate the Mcp-Session-Id state.)
        ? != 0 ( nurl_str_eq rm `DELETE` ) {
            : HttpResponse r ( response_status_only 204 )
            ( __mcp_http_apply_cors r )
            ( __mcp_http_echo_session req r )
            ^ r
        } {}

        // Anything other than POST: 405.
        ? != 0 ( nurl_str_eq rm `POST` ) {} {
            : HttpResponse r ( response_text 405 `Method Not Allowed\n` )
            ( response_set_header r `Allow` `POST, GET, DELETE, OPTIONS` )
            ( __mcp_http_apply_cors r )
            ( __mcp_http_echo_session req r )
            ^ r
        }

        // POST body must be non-empty.
        : i bn ( vec_len [u] . req body )
        ? <= bn 0 {
            : HttpResponse r ( __mcp_http_jsonrpc_error mcp_err_invalid_request `empty request body` )
            ( __mcp_http_apply_cors r )
            ( __mcp_http_echo_session req r )
            ^ r
        } {}

        // Decode body as UTF-8 String. bytes_to_str adds a NUL terminator
        // so json_parse (which reads via raw `s`) sees a clean string.
        : String body_str ( bytes_to_str . req body )
        : !Json JsonError pj ( json_parse ( string_data body_str ) )
        ( string_free body_str )

        ?? pj {
            T jreq → {
                // JSON-RPC 2.0 batch: top-level array routes through the
                // dispatcher per-element, collecting non-notification
                // responses into a new array. Empty batch → invalid
                // request per the spec. Explicit while-loop avoids a
                // nested closure inside the outer handler closure (the
                // compiler's capture analysis emits a duplicate body for
                // closures captured from within another closure body).
                ? ( json_is_arr jreq ) {
                    : i bn ( json_arr_len jreq )
                    ? <= bn 0 {
                        ( json_free jreq )
                        : HttpResponse r ( __mcp_http_jsonrpc_error mcp_err_invalid_request `empty batch` )
                        ( __mcp_http_apply_cors r )
                        ( __mcp_http_echo_session req r )
                        ^ r
                    } {}
                    : ( Vec Json ) resps ( vec_new [Json] )
                    : ~ i bi 0
                    ~ < bi bn {
                        : ?Json elem ( json_arr_get jreq bi )
                        ?? elem {
                            T el → {
                                : ?Json reply ( dispatch el )
                                ?? reply {
                                    T resp → ( vec_push [Json] resps resp )
                                    F empty → ( json_free empty )
                                }
                            }
                            F _ → {}
                        }
                        = bi + bi 1
                    }
                    ( json_free jreq )

                    : i nr ( vec_len [Json] resps )
                    ? > nr 0 {
                        : Json resp_arr ( json_arr resps )
                        : HttpResponse r ( __mcp_http_response_for_json req resp_arr )
                        ( __mcp_http_apply_cors r )
                        ( __mcp_http_echo_session req r )
                        ^ r
                    } {
                        ( vec_free [Json] resps )
                        : HttpResponse r ( response_status_only 202 )
                        ( __mcp_http_apply_cors r )
                        ( __mcp_http_echo_session req r )
                        ^ r
                    }
                } {}

                // Single request — original path.
                : ?Json reply ( dispatch jreq )
                ( json_free jreq )

                ?? reply {
                    T resp_json → {
                        : HttpResponse r ( __mcp_http_response_for_json req resp_json )
                        ( __mcp_http_apply_cors r )
                        ( __mcp_http_echo_session req r )
                        ^ r
                    }
                    F empty → {
                        ( json_free empty )
                        // Notification consumed — no body, 202 Accepted.
                        : HttpResponse r ( response_status_only 202 )
                        ( __mcp_http_apply_cors r )
                        ( __mcp_http_echo_session req r )
                        ^ r
                    }
                }
            }
            F _ → {
                : HttpResponse r ( __mcp_http_jsonrpc_error mcp_err_parse_error `request body is not valid JSON` )
                ( __mcp_http_apply_cors r )
                ( __mcp_http_echo_session req r )
                ^ r
            }
        }
    }
}

// ── mcp_server_run_http ──────────────────────────────────────────────
//
// One-line convenience: open a listener on `host:port`, mount the
// MCP dispatcher on every path (the MVP doesn't differentiate
// `/mcp` from `/anything-else` since there's only one endpoint), run
// the server forever. Use `host = "127.0.0.1"` for loopback-only
// (the MCP-over-HTTP convention for local agent integrations).
//
// Returns Ok on a clean stop (NetClosed after `tcp_close_listener`),
// Err on an infrastructure failure (port already in use, accept
// failure mid-flight). The handler closure does not need explicit
// CORS wrapping — `mcp_http_handler` already adds the headers per-
// response.
//
// For multi-route servers (where /mcp is one endpoint among many),
// build the handler manually with `mcp_http_handler dispatch` and
// register it on a `Router` via `router_post path mcp_h`.

@ mcp_server_run_http
s host i port
( @ ?Json Json ) dispatch
→ !v NetErr {
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            // Wrap dispatch in an explicit closure rather than passing
            // the parameter through directly. The bare @-fn ↔ closure
            // coercion in argument position currently fails the
            // type-checker (the compiler diagnoses it — wrap as
            // `\ args → R { ( fn args ) }`) even when the source value
            // is itself a closure-typed parameter.
            : ( @ HttpResponse HttpRequest ) handler ( mcp_http_handler \ Json r → ?Json { ^ ( dispatch r ) } )
            : HttpServer srv ( server_new listener handler )
            : !v NetErr rr ( server_run srv )
            ( server_stop srv )
            ^ rr
        }
        F e → ^ @ !v NetErr { F e }
    }
}
