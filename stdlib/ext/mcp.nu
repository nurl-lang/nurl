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
// * `notifications/initialized` is sent by LEGACY clients right after
//   the `initialize` handshake completes; servers should accept and
//   ignore it.
// * `ping` requests (legacy revisions) get an empty result `{}`.
//
// ── Protocol eras (2026-07-28 spec) ─────────────────────────────────
//
// Revision 2026-07-28 removed the `initialize` handshake: a MODERN
// request carries its protocol version + client identity in
// `params._meta` (`io.modelcontextprotocol/protocolVersion` etc.) and
// servers MUST implement `server/discover`. Revisions `2025-11-25`
// and earlier are LEGACY (handshake-based). This module supports
// building DUAL-ERA servers per the spec's compatibility matrix
// (specification/2026-07-28/basic/versioning):
//
//   * `mcp_protocol_version` — the latest revision (`2026-07-28`);
//     what `server/discover` and client `_meta` advertise first.
//     `tools/mcp_spec_drift_check.sh` verifies it matches the spec
//     site's "current".
//   * `mcp_protocol_version_initialize` — the newest HANDSHAKE-era
//     revision (`2025-11-25`); what `initialize` responses advertise
//     (a legacy client would reject a non-handshake revision).
//   * `mcp_protocol_version_legacy` — `2024-11-05`, kept for callers
//     that explicitly negotiate the oldest shape.
//   * `mcp_version_supported` / `mcp_supported_versions_json` — the
//     full supported set, for `server/discover` and the
//     `UnsupportedProtocolVersionError` data payload.
//   * `mcp_request_protocol_version` / `mcp_request_is_modern` — read
//     a request's `_meta` version (empty string = legacy request).
//   * Every result built via `mcp_response_result` carries
//     `resultType: "complete"` (required in 2026-07-28; ignored by
//     legacy clients, whose spec says unknown fields are tolerated
//     and absence means "complete").

$ `stdlib/core/string.nu`
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

// Resource lookup failure. Kept at the spec's -32002 rather than
// folded into invalid-params: a client distinguishes "that URI is not
// served here" (re-list and pick another) from "your request was
// malformed" (do not retry as-is), and only a distinct code carries
// that.
: i mcp_err_resource_not_found -32002

// MCP-reserved codes (2026-07-28 partitioned -32020..-32099 for the
// spec; earlier drafts used -32001/-32003/-32004 — renumbered).
: i mcp_err_header_mismatch -32020
: i mcp_err_missing_client_capability -32021
: i mcp_err_unsupported_protocol_version -32022

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
    // Latest stable revision (as of 2026-08-03; verified via spec site).
    // First of the MODERN (stateless, per-request `_meta`) era.
    ^ `2026-07-28`
}

@ mcp_protocol_version_initialize → s {
    // Newest HANDSHAKE-era revision — what `initialize` responses
    // advertise. 2026-07-28 has no handshake, so answering an
    // `initialize` with it would make a legacy client disconnect;
    // dual-era servers answer initialize with a legacy revision and
    // serve modern clients through per-request `_meta`.
    ^ `2025-11-25`
}

@ mcp_protocol_version_legacy → s {
    // Oldest supported revision — kept exported for callers that want
    // to explicitly negotiate the older shape (e.g. for compatibility
    // with a fixed older client).
    ^ `2024-11-05`
}

// The full supported set. A dual-era server serves every handshake
// revision through the same JSON-RPC methods (the wire shapes NURL
// implements are unchanged across them), plus the modern revision.
@ mcp_version_supported s v → b {
    ? != 0 ( nurl_str_eq v `2026-07-28` ) { ^ T } {}
    ? != 0 ( nurl_str_eq v `2025-11-25` ) { ^ T } {}
    ? != 0 ( nurl_str_eq v `2025-06-18` ) { ^ T } {}
    ? != 0 ( nurl_str_eq v `2025-03-26` ) { ^ T } {}
    ? != 0 ( nurl_str_eq v `2024-11-05` ) { ^ T } {}
    ^ F
}

// Owned JSON array of the supported revisions, newest first — the
// shape `server/discover`'s `supportedVersions` and the
// UnsupportedProtocolVersionError `data.supported` field carry.
@ mcp_supported_versions_json → Json {
    : Json arr ( json_arr_new )
    ( json_arr_push arr ( json_str_lit `2026-07-28` ) )
    ( json_arr_push arr ( json_str_lit `2025-11-25` ) )
    ( json_arr_push arr ( json_str_lit `2025-06-18` ) )
    ( json_arr_push arr ( json_str_lit `2025-03-26` ) )
    ( json_arr_push arr ( json_str_lit `2024-11-05` ) )
    ^ arr
}

// ── Per-request `_meta` (modern era) ────────────────────────────────

// The protocol version a request declares in
// `params._meta["io.modelcontextprotocol/protocolVersion"]`.
// Returns a BORROWED s (valid while `req` lives); empty string when
// absent — i.e. a legacy-era request.
@ mcp_request_protocol_version Json req → s {
    : ?Json p ( json_obj_get req `params` )
    ?? p {
        T pv → {
            : ?Json m ( json_obj_get pv `_meta` )
            ?? m {
                T mv → {
                    : ?Json ver ( json_obj_get mv `io.modelcontextprotocol/protocolVersion` )
                    ?? ver {
                        T jv → { ^ ( json_as_str jv ) }
                        F _ → { ^ `` }
                    }
                }
                F _ → { ^ `` }
            }
        }
        F _ → { ^ `` }
    }
}

@ mcp_request_is_modern Json req → b {
    ^ > ( nurl_str_len ( mcp_request_protocol_version req ) ) 0
}

// Legacy handshake negotiation: the revision an `initialize` response
// should advertise for the given request params — the client's
// requested `protocolVersion` when it is a supported HANDSHAKE-era
// revision, else `mcp_protocol_version_initialize`. (Echoing the
// modern, handshake-less revision would strand a legacy client.)
// Returned s is BORROWED (from params or from a static literal).
@ mcp_initialize_version_for ? Json params → s {
    : ~ s ver ( mcp_protocol_version_initialize )
    ?? params {
        T p → {
            : ?Json rv ( json_obj_get p `protocolVersion` )
            ?? rv {
                T jv → {
                    : s req_ver ( json_as_str jv )
                    ? & ( mcp_version_supported req_ver )
                    == 0 ( nurl_str_eq req_ver ( mcp_protocol_version ) )
                    { = ver req_ver } {}
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ver
}

// Client-side `_meta` for modern requests: protocolVersion +
// clientInfo + clientCapabilities. Caller sets it on `params._meta`.
@ mcp_client_meta s client_name s client_version → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit client_name ) )
    ( json_obj_set info `version` ( json_str_lit client_version ) )
    : Json meta ( json_obj_new )
    ( json_obj_set meta `io.modelcontextprotocol/protocolVersion` ( json_str_lit ( mcp_protocol_version ) ) )
    ( json_obj_set meta `io.modelcontextprotocol/clientInfo` info )
    ( json_obj_set meta `io.modelcontextprotocol/clientCapabilities` ( json_obj_new ) )
    ^ meta
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
    // 2026-07-28: every result carries `resultType` ("complete" for
    // ordinary results). Injected centrally so every server built on
    // these envelopes conforms. Safe for legacy clients too: JSON-RPC
    // consumers tolerate unknown result fields, and the changelog
    // requires clients to treat an ABSENT field as "complete" — the
    // field is purely additive.
    ? ( json_is_obj result ) {
        ? ( json_obj_has result `resultType` ) {} {
            ( json_obj_set result `resultType` ( json_str_lit `complete` ) )
        }
    } {}
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_clone id ) )
    ( json_obj_set out `result` result )
    ^ out
}

// Error envelope with a `data` member (e.g. the -32022
// UnsupportedProtocolVersionError's {supported, requested}).
// CONSUMES `data`; `id` is borrowed (cloned) like the other builders.
@ mcp_response_error_data Json id i code s message Json data → Json {
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int code ) )
    ( json_obj_set err `message` ( json_str_lit message ) )
    ( json_obj_set err `data` data )
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_clone id ) )
    ( json_obj_set out `error` err )
    ^ out
}

// The spec-shaped UnsupportedProtocolVersionError response: the
// client reads `data.supported`, picks a mutual revision and retries.
@ mcp_unsupported_version_response Json id s requested → Json {
    : Json data ( json_obj_new )
    ( json_obj_set data `supported` ( mcp_supported_versions_json ) )
    ( json_obj_set data `requested` ( json_str_lit requested ) )
    ^ ( mcp_response_error_data id mcp_err_unsupported_protocol_version `Unsupported protocol version` data )
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

// Attach MCP ToolAnnotations (spec 2025-03-26) to a tool descriptor and
// return the same handle. Clients use these as trust hints for
// permission defaults and grouping — claude.ai, for one, can default
// read-only tools to auto-allow while write-shaped tools need approval.
// An ABSENT destructiveHint defaults to TRUE in the spec, so a harmless
// tool that skips annotations entirely is presented as if it could
// destroy state; every tool a server lists should pass through here.
@ mcp_tool_annotate Json tool b read_only b destructive b idempotent b open_world → Json {
    : Json a ( json_obj_new )
    ( json_obj_set a `readOnlyHint` ( json_bool read_only ) )
    ( json_obj_set a `destructiveHint` ( json_bool destructive ) )
    ( json_obj_set a `idempotentHint` ( json_bool idempotent ) )
    ( json_obj_set a `openWorldHint` ( json_bool open_world ) )
    ( json_obj_set tool `annotations` a )
    ^ tool
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
    // CacheableResult fields are REQUIRED on tools/list results in
    // 2026-07-28 (and harmless earlier). Conservative defaults; a
    // server with a static tool set can overwrite with a longer
    // public hint via mcp_result_set_cacheable.
    ( mcp_result_set_cacheable out 60000 `private` )
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
    // Handshake-era revision on purpose — see mcp_protocol_version_initialize.
    ( json_obj_set out `protocolVersion` ( json_str_lit ( mcp_protocol_version_initialize ) ) )
    ( json_obj_set out `capabilities` caps )
    ( json_obj_set out `serverInfo` info )
    ^ out
}

// ── 2026-07-28 result decorations ───────────────────────────────────

// CacheableResult (required on tools/list, prompts/list,
// resources/list, resources/read, resources/templates/list results):
// `ttlMs` = freshness hint in milliseconds; `cacheScope` = "public"
// (shared intermediaries may cache) or "private".
@ mcp_result_set_cacheable Json result i ttl_ms s scope → v {
    ( json_obj_set result `ttlMs` ( json_int ttl_ms ) )
    ( json_obj_set result `cacheScope` ( json_str_lit scope ) )
}

// Attach `_meta["io.modelcontextprotocol/serverInfo"]` to a result —
// modern-era servers SHOULD identify themselves in every result.
// Merges into an existing `_meta` object when present.
@ mcp_result_set_server_info Json result s name s version → v {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit name ) )
    ( json_obj_set info `version` ( json_str_lit version ) )
    : ?Json m ( json_obj_get result `_meta` )
    ?? m {
        T mv → { ( json_obj_set mv `io.modelcontextprotocol/serverInfo` info ) }
        F _ → {
            : Json meta ( json_obj_new )
            ( json_obj_set meta `io.modelcontextprotocol/serverInfo` info )
            ( json_obj_set result `_meta` meta )
        }
    }
}

// server/discover result (servers MUST implement the RPC in
// 2026-07-28). CONSUMES `caps`. `instructions` empty = omitted. The
// discover output is static for the server's lifetime, so it carries
// a long public cache hint.
@ mcp_discover_result s name s version Json caps s instructions → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `resultType` ( json_str_lit `complete` ) )
    ( json_obj_set out `supportedVersions` ( mcp_supported_versions_json ) )
    ( json_obj_set out `capabilities` caps )
    ( mcp_result_set_server_info out name version )
    ? > ( nurl_str_len instructions ) 0 {
        ( json_obj_set out `instructions` ( json_str_lit instructions ) )
    } {}
    ( mcp_result_set_cacheable out 3600000 `public` )
    ^ out
}
