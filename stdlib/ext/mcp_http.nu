// stdlib/ext/mcp_http.nu — Streamable HTTP transport for MCP.
//
// Layered on top of `stdlib/ext/mcp.nu` (envelope + shape primitives)
// and the Phase 4–6 HTTP server stack (`http_server.nu` +
// `http_request.nu` + `http_response.nu`). Kept in a separate file so
// stdio-only MCP servers don't drag in the HTTP / TCP machinery just
// to read and write `\n`-delimited JSON-RPC.
//
// **Transport summary** (per the MCP "Streamable HTTP" spec, see
// https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/):
//
//   POST /mcp     — client sends one JSON-RPC request; server replies
//                   with a JSON-RPC response (HTTP 200, application/
//                   json) OR — for a notification with no `id` field —
//                   an empty 202 Accepted body.
//   GET  /mcp     — opens a server-to-client SSE stream. Used for
//                   server-initiated notifications. The MVP here
//                   answers 405 Method Not Allowed because tools-only
//                   servers don't push notifications. Easy to extend
//                   later by swapping the handler with one that
//                   `response_begin_chunked`s an event-stream.
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
//   * GET /mcp SSE stream for server-initiated notifications — needs
//     a notification queue + Last-Event-ID resumption + the chunked
//     streaming primitives from `http_response.nu` (already shipped).
//   * Mcp-Session-Id header for stateful sessions — would need a
//     session-id → state map + per-session dispatcher closure.
//   * Batch requests (top-level `[req1, req2]` arrays) — protocol
//     allows it, but the canonical MCP clients (Claude Desktop,
//     claude.ai) send single requests today.
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
  ( response_set_header r `Access-Control-Allow-Origin`  `*` )
  ( response_set_header r `Access-Control-Allow-Headers` `Content-Type, Authorization, Mcp-Session-Id` )
  ( response_set_header r `Access-Control-Expose-Headers` `Mcp-Session-Id` )
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
  ( @ ? Json Json ) dispatch
  → ( @ HttpResponse HttpRequest ) {
  ^ \ HttpRequest req → HttpResponse {
    : s rm ( string_data . req method )

    // OPTIONS preflight: short-circuit with permissive CORS.
    ? != 0 ( nurl_str_eq rm `OPTIONS` ) {
      : HttpResponse pre ( response_status_only 204 )
      ( response_set_header pre `Access-Control-Allow-Methods` `POST, GET, DELETE, OPTIONS` )
      ( response_set_header pre `Access-Control-Max-Age`       `86400` )
      ( __mcp_http_apply_cors pre )
      ^ pre
    } {}

    // GET: SSE stream not implemented in MVP.
    ? != 0 ( nurl_str_eq rm `GET` ) {
      : HttpResponse r ( response_text 405 `MCP HTTP server does not push notifications (no SSE stream)\n` )
      ( response_set_header r `Allow` `POST, DELETE, OPTIONS` )
      ( __mcp_http_apply_cors r )
      ^ r
    } {}

    // DELETE: stateless — nothing to free.
    ? != 0 ( nurl_str_eq rm `DELETE` ) {
      : HttpResponse r ( response_status_only 204 )
      ( __mcp_http_apply_cors r )
      ^ r
    } {}

    // Anything other than POST: 405.
    ? != 0 ( nurl_str_eq rm `POST` ) {} {
      : HttpResponse r ( response_text 405 `Method Not Allowed\n` )
      ( response_set_header r `Allow` `POST, GET, DELETE, OPTIONS` )
      ( __mcp_http_apply_cors r )
      ^ r
    }

    // POST body must be non-empty.
    : i bn ( vec_len [u] . req body )
    ? <= bn 0 {
      : HttpResponse r ( __mcp_http_jsonrpc_error mcp_err_invalid_request `empty request body` )
      ( __mcp_http_apply_cors r )
      ^ r
    } {}

    // Decode body as UTF-8 String. bytes_to_str adds a NUL terminator
    // so json_parse (which reads via raw `s`) sees a clean string.
    : String body_str ( bytes_to_str . req body )
    : ! Json ParseErr pj ( json_parse ( string_data body_str ) )
    ( string_free body_str )

    ?? pj {
      T jreq → {
        // Hand the parsed request off to the user dispatcher.
        : ? Json reply ( dispatch jreq )
        ( json_free jreq )

        ?? reply {
          T resp_json → {
            : HttpResponse r ( response_json 200 resp_json )
            ( json_free resp_json )
            ( __mcp_http_apply_cors r )
            ^ r
          }
          F empty → {
            ( json_free empty )
            // Notification consumed — no body, 202 Accepted.
            : HttpResponse r ( response_status_only 202 )
            ( __mcp_http_apply_cors r )
            ^ r
          }
        }
      }
      F _ → {
        : HttpResponse r ( __mcp_http_jsonrpc_error mcp_err_parse_error `request body is not valid JSON` )
        ( __mcp_http_apply_cors r )
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
  ( @ ? Json Json ) dispatch
  → ! v NetErr {
  : ! TcpListener NetErr lr ( tcp_listen host port )
  ?? lr {
    T listener → {
      : ( @ HttpResponse HttpRequest ) handler ( mcp_http_handler dispatch )
      : HttpServer srv ( server_new listener handler )
      : ! v NetErr rr ( server_run srv )
      ( server_stop srv )
      ^ rr
    }
    F e → ^ @ ! v NetErr { F e }
  }
}
