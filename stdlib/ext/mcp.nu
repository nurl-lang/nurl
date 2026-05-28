// stdlib/ext/mcp.nu — Model Context Protocol (MCP) server primitives.
//
// MCP is JSON-RPC 2.0 over a transport. NURL ships the **stdio**
// transport here: each line on stdin is one JSON-RPC message, each
// line on stdout is the server's reply or notification. This is the
// transport every MCP client supports (Claude Desktop, claude.ai, the
// reference SDKs, …) so a NURL-built MCP server can plug into the
// existing ecosystem without an HTTP server.
//
// **What this module is.** A minimal primitives layer:
//   1. line-delimited JSON I/O (`mcp_read_request`, `mcp_send_message`)
//   2. MCP/JSON-RPC envelope builders (`mcp_response_result`, …)
//   3. Tool-shaped result helpers (`mcp_text_content`,
//      `mcp_tool_result_text`, …)
//
// What this module is NOT (yet): a high-level "register a tool with a
// closure handler" framework. That requires putting closures in user
// structs / Vec elements, which the compiler's text-level
// `scan_generic_structs` + closure-capture pipeline doesn't yet handle
// uniformly. The user writes the dispatch loop themselves — see
// `examples/mcp_echo_server.nu` for the canonical shape.
//
// HTTP/SSE and Streamable-HTTP transports live in
// `stdlib/ext/mcp_http.nu`.
//
// ── API ─────────────────────────────────────────────────────────────
//
// Reading:
//   ( mcp_read_request )            → ? Json
//                                     None on stdin EOF; skips empty
//                                     lines and logs+continues on
//                                     parse errors so the server
//                                     stays in sync with the client.
//
// Writing:
//   ( mcp_send_message Json msg )   → v
//                                     stringify + write + newline +
//                                     flush stdout. Consumes msg.
//   ( mcp_log s text )              → v   stderr (NEVER stdout — the
//                                          MCP transport reserves
//                                          stdout for JSON-RPC).
//
// JSON-RPC envelopes (all return owned Json — call `json_free` after
// you've sent them, or pass to `mcp_send_message` which consumes):
//   ( mcp_response_result Json id Json result )      → Json
//   ( mcp_response_error  Json id i code s message ) → Json
//   ( mcp_notification    s method Json params )     → Json
//
// `id` is BORROWED — these helpers `json_clone` it internally so
// the caller's request Json can be freed independently.
// `result` and `params` are CONSUMED — they're embedded into the
// returned envelope and freed when the envelope is freed.
//
// MCP-specific shapes:
//   ( mcp_text_content      s text )              → Json
//                                                  {"type":"text","text":...}
//   ( mcp_tool_result_text  s text )              → Json
//                                                  {"content":[{type:text,text}],
//                                                   "isError":false}
//   ( mcp_tool_result_error s message )           → Json
//                                                  same shape, isError=true
//   ( mcp_tool_descriptor   s name s desc Json schema ) → Json
//                                                  {"name","description",
//                                                   "inputSchema"}
//   ( mcp_tools_list_result ( Vec Json ) tools )  → Json
//                                                  {"tools":[…]} — CONSUMES
//                                                  the Vec (and each Json
//                                                  element) into the shape.
//   ( mcp_initialize_result s name s version )    → Json
//                                                  default capabilities
//                                                  declares only "tools".
//
// JSON-RPC error codes (use with `mcp_response_error`):
//   PARSE_ERROR      = -32700
//   INVALID_REQUEST  = -32600
//   METHOD_NOT_FOUND = -32601
//   INVALID_PARAMS   = -32602
//   INTERNAL_ERROR   = -32603
// (These are constants below: `mcp_err_parse_error` etc., since
// `: i FOO` only accepts literal RHS — see std/log.nu for prior art.)
//
// ── Memory model ────────────────────────────────────────────────────
//
// Standard NURL single-owner. Every Json that this module returns is
// owned by the caller; pass to `mcp_send_message` (consumes) or
// `json_free` to release. The only borrows are inside `id` arguments
// to the envelope builders (cloned internally) and `s` arguments
// (always borrowed in NURL).
//
// ── Protocol notes ──────────────────────────────────────────────────
//
// * Notifications (no `id` field) require NO response from the server
//   — the user's main loop must check `( json_obj_get req `id` )` and
//   skip the reply when the result is None.
// * `notifications/initialized` is sent by the client right after the
//   `initialize` handshake completes; servers should accept and
//   ignore it.
// * `ping` requests get an empty result `{}`.
// * `protocolVersion` defaults to the value returned by
//   `mcp_protocol_version` — currently the latest stable revision
//   (`2025-11-25`). MCP revisions only bump on backwards-incompatible
//   changes, so a server advertising the latest revision serves older
//   clients fine — but pinning to an old revision pushes negotiation
//   the wrong way. `tools/mcp_spec_drift_check.sh` verifies the
//   pinned version matches the spec site's "current".
// * `mcp_protocol_version_legacy` returns `2024-11-05` — the previous
//   pinned revision. Useful for serving clients that explicitly
//   negotiate that version (a server MAY agree to whatever the
//   client requests, as long as it's a revision the server supports).

$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/io.nu`
$ `stdlib/ext/json.nu`

// ── JSON-RPC error codes ────────────────────────────────────────────
//
// NURL's module-level `: i FOO` only takes literal-int RHS. The
// negative-int form `: i FOO -32700` works thanks to grammar v1.2's
// negative-literal lexing.

: i mcp_err_parse_error -32700
: i mcp_err_invalid_request -32600
: i mcp_err_method_not_found -32601
: i mcp_err_invalid_params -32602
: i mcp_err_internal_error -32603

// ── Protocol version ────────────────────────────────────────────────
//
// MCP revisions are dated YYYY-MM-DD per
// https://modelcontextprotocol.io/specification/versioning. The version
// only bumps on backwards-incompatible changes, so a server that
// advertises the LATEST revision serves earlier clients correctly —
// pinning to an old date pushes negotiation the wrong way.
//
// `tools/mcp_spec_drift_check.sh` verifies the pinned version below
// matches the spec site's "current" version; CI integration would
// fail fast when the spec drifts.

@ mcp_protocol_version → s {
    // Latest stable revision (as of 2026-05-19; verified via spec site).
    ^ `2025-11-25`
}

@ mcp_protocol_version_legacy → s {
    // Previous pinned revision — kept exported for callers that want
    // to explicitly negotiate the older shape (e.g. for compatibility
    // with a fixed older client).
    ^ `2024-11-05`
}

// ── Logging ─────────────────────────────────────────────────────────

@ mcp_log s text → v {
    ( nurl_eprint `[mcp] ` )
    ( nurl_eprint text )
    ( nurl_eprint `\n` )
    ( eflush )
}

// ── Reading ─────────────────────────────────────────────────────────
//
// Reads NDJSON-style messages. Skips empty lines; on parse error,
// logs to stderr and keeps reading. Only returns None on stdin EOF
// so the user's main loop can use `?? msg` as the termination signal.

@ mcp_read_request → ?Json {
    : ~ b looking T
    ~ looking {
        : String line ( read_line )

        ? ( stdin_eof ) {
            ( string_free line )
            ^ @ ?Json { F @ Json { JNull } }
        } {}

        : i ll ( string_len line )
        ? == ll 0 {
            ( string_free line )
        } {
            : !Json JsonError pj ( json_parse ( string_data line ) )
            ?? pj {
                T j → {
                    ( string_free line )
                    ^ @ ?Json { T j }
                }
                F _ → {
                    ( mcp_log `parse error, skipping line` )
                    ( string_free line )
                }
            }
        }
    }
    ^ @ ?Json { F @ Json { JNull } }
}

// ── Writing ─────────────────────────────────────────────────────────

@ mcp_send_message Json msg → v {
    : String s ( json_stringify msg )
    ( nurl_print ( string_data s ) )
    ( nurl_print `\n` )
    ( flush )
    ( string_free s )
    ( json_free msg )
}

// ── JSON-RPC envelopes ──────────────────────────────────────────────

@ mcp_response_result Json id Json result → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_clone id ) )
    ( json_obj_set out `result` result )
    ^ out
}

@ mcp_response_error Json id i code s message → Json {
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int code ) )
    ( json_obj_set err `message` ( json_str_lit message ) )
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_clone id ) )
    ( json_obj_set out `error` err )
    ^ out
}

@ mcp_notification s method Json params → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `method` ( json_str_lit method ) )
    ( json_obj_set out `params` params )
    ^ out
}

// ── MCP-specific result shapes ──────────────────────────────────────

@ mcp_text_content s text → Json {
    : Json c ( json_obj_new )
    ( json_obj_set c `type` ( json_str_lit `text` ) )
    ( json_obj_set c `text` ( json_str_lit text ) )
    ^ c
}

@ __mcp_tool_result_envelope s text b is_err → Json {
    : Json arr ( json_arr_new )
    ( json_arr_push arr ( mcp_text_content text ) )
    : Json out ( json_obj_new )
    ( json_obj_set out `content` arr )
    ( json_obj_set out `isError` ( json_bool is_err ) )
    ^ out
}

@ mcp_tool_result_text s text → Json {
    ^ ( __mcp_tool_result_envelope text F )
}

@ mcp_tool_result_error s message → Json {
    ^ ( __mcp_tool_result_envelope message T )
}

@ mcp_tool_descriptor s name s desc Json schema → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `name` ( json_str_lit name ) )
    ( json_obj_set out `description` ( json_str_lit desc ) )
    ( json_obj_set out `inputSchema` schema )
    ^ out
}

// CONSUMES the Vec[Json]: every element is moved into the wrapped
// JArr. After this call the caller must not vec_free the input — the
// Json envelope owns it.
@ mcp_tools_list_result ( Vec Json ) tools → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [Json] tools )
    : ~ i k 0
    ~ < k n {
        : ?Json e ( vec_get [Json] tools k )
        ?? e {
            T jv → ( json_arr_push arr jv )
            F → {}
        }
        = k + k 1
    }
    // Drop the now-emptied Vec — JArr keeps a fresh one inside.
    ( vec_free [Json] tools )
    : Json out ( json_obj_new )
    ( json_obj_set out `tools` arr )
    ^ out
}

@ mcp_initialize_result s name s version → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit name ) )
    ( json_obj_set info `version` ( json_str_lit version ) )

    // Declare only the `tools` capability for now. Empty object means
    // "supported, no extra options" per the MCP spec.
    : Json tools_cap ( json_obj_new )
    : Json caps ( json_obj_new )
    ( json_obj_set caps `tools` tools_cap )

    : Json out ( json_obj_new )
    ( json_obj_set out `protocolVersion` ( json_str_lit ( mcp_protocol_version ) ) )
    ( json_obj_set out `capabilities` caps )
    ( json_obj_set out `serverInfo` info )
    ^ out
}
