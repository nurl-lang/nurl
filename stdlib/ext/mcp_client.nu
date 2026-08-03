// stdlib/ext/mcp_client.nu — MCP (Model Context Protocol) client over
// HTTP. NURL programs use this to CONSUME tools exposed by other MCP
// servers — e.g. an agent loop that calls `tools/list` to discover
// capabilities then `tools/call` to invoke them. Symmetric counterpart
// to `mcp.nu` (stdio server) and `mcp_http.nu` (HTTP server) — closes
// the LLM-host story on the consumer side.
//
// Layered on the existing HTTP+JSON+MCP-envelope primitives:
//
//   http.nu      → http_request_to (timeouts)
//   json.nu      → json_stringify, json_parse, json_obj_get/set
//   mcp.nu       → mcp_response_result (envelope builder) / mcp_notification
//
// No runtime/compiler changes. No state — every helper is a single
// HTTP round-trip. Sessions can layer on top via the `Mcp-Session-Id`
// header (MCP spec §3.6) — pass it via `mcp_call_with_session`.
//
// API:
//
//   ( mcp_client_new s endpoint i timeout_ms )
//                                  → McpClient   borrowed endpoint
//   ( mcp_client_free McpClient c ) → v
//
//   ( mcp_call McpClient c s method ( ? Json ) params )
//                                  → ! Json McpErr     full response
//
//   ( mcp_initialize McpClient c s client_name s client_version )
//                                  → ! Json McpErr    legacy handshake
//   ( mcp_ping        McpClient c ) → ! Json McpErr   legacy heartbeat
//
//   Modern era (2026-07-28 — per-request `_meta`, no handshake):
//   ( mcp_discover McpClient c s client_name s client_version )
//                                  → ! Json McpErr    server/discover
//   ( mcp_server_is_modern McpClient c s name s ver ) → b
//                                  dual-era probe: T ⇒ speak modern,
//                                  F ⇒ fall back to mcp_initialize
//   ( mcp_call_modern McpClient c s method ( ? Json ) params s name s ver )
//                                  → ! Json McpErr    injects `_meta` +
//                                  Mcp-Method / MCP-Protocol-Version headers
//   ( mcp_tools_call_modern McpClient c s tool Json args s name s ver )
//                                  → ! Json McpErr    + Mcp-Name header
//   ( mcp_tools_list  McpClient c ) → ! ( Vec Json ) McpErr
//   ( mcp_tools_call  McpClient c s name Json args )
//                                  → ! Json McpErr
//   ( mcp_prompts_list  McpClient c ) → ! ( Vec Json ) McpErr
//   ( mcp_resources_list McpClient c ) → ! ( Vec Json ) McpErr
//
//   ( mcp_err_name McpErr e ) → s
//
// Memory model:
//
//   * `mcp_client_new` COPIES `endpoint` into an owned String. The
//     resulting handle is heap-light (one String + two ints).
//   * `params` / `args` are CONSUMED by the call — caller must NOT
//     re-use them after handing over. Pass `json_clone` if needed.
//   * `mcp_call` returns the full JSON-RPC response object on success
//     (caller probes `.result`/`.error` itself). Helpers like
//     `mcp_tools_list` extract the `.result.tools` array as a fresh
//     OWNED Vec of cloned Json objects so the caller can free the
//     enclosing response separately.
//   * On `error` envelope (server-reported) the response IS the
//     `! Json` Ok-arm — server-error is NOT promoted to McpErr. McpErr
//     covers transport + JSON-shape failures. Use `mcp_response_is_error`
//     and `mcp_response_error_code/message` to read server errors.

$ `stdlib/ext/http.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── McpClient struct ──────────────────────────────────────────────────

: McpClient {
    String endpoint
    i timeout_ms
}

@ mcp_client_new s endpoint i timeout_ms → McpClient {
    : i ito ? > timeout_ms 0 timeout_ms 30000
    ^ @ McpClient { ( string_from endpoint ) ito }
}

@ mcp_client_free McpClient c → v {
    ( string_free . c endpoint )
}

// ── McpErr ────────────────────────────────────────────────────────────

: | McpErr {
    McpAuth  // empty endpoint (early-return before network)
    McpHttp  // transport failure (connect/timeout/tls/dns/4xx-5xx)
    McpJson  // server replied with non-JSON / malformed JSON body
    McpProtocol  // missing jsonrpc field, missing id, etc.
    McpOther
}

@ mcp_err_name McpErr e → s {
    ^ ?? e {
        McpAuth → `McpAuth`
        McpHttp → `McpHttp`
        McpJson → `McpJson`
        McpProtocol → `McpProtocol`
        McpOther → `McpOther`
    }
}

// ── Envelope construction ────────────────────────────────────────────

@ __mcp_request_envelope i id s method ? Json params → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_int id ) )
    ( json_obj_set out `method` ( json_str_lit method ) )
    ?? params {
        T p → ( json_obj_set out `params` p )
        F _ → {}
    }
    ^ out
}

// ── mcp_call: single round-trip ──────────────────────────────────────

@ mcp_call McpClient c s method ? Json params → !Json McpErr {
    ^ ( __mcp_call_with_headers c method params `` )
}

// Internal transport core shared by the legacy and modern call paths.
// `extra_headers` rides after the base headers; `` for none. Each
// entry must be `Name: value\r\n`-terminated.
@ __mcp_call_with_headers McpClient c s method ? Json params s extra_headers → !Json McpErr {
    : i n ( string_len . c endpoint )
    ? == n 0 {
        ?? params { T p → ( json_free p ) F _ → {} }
        ^ @ !Json McpErr { F @ McpErr { McpAuth } }
    } {}

    // JSON-RPC id only needs to round-trip with the response. Use the
    // millisecond clock — uniqueness within a process is overkill for
    // single round-trips, and HTTP frames the request/response pair.
    : i id ( now_ms )
    : Json req ( __mcp_request_envelope id method params )
    : String body ( json_stringify req )
    ( json_free req )

    : String hdrs ( string_from `Content-Type: application/json\r\nAccept: application/json\r\n` )
    ( string_push_str hdrs extra_headers )

    : !Response HttpErr hr ( http_request_to
    `POST`
    ( string_data . c endpoint )
    ( string_data body )
    ( string_data hdrs )
    . c timeout_ms
    0 )
    ( string_free hdrs )
    ( string_free body )

    ?? hr {
        T resp → {
            : i status ( http_status resp )
            ? & >= status 200 < status 300 {
                : s body_view ( http_body_str resp )
                : !Json JsonError pr ( json_parse body_view )
                ( response_free resp )
                ?? pr {
                    T j → {
                        // Validate jsonrpc field (lenient — many servers omit it).
                        ^ @ !Json McpErr { T j }
                    }
                    F _ → ^ @ !Json McpErr { F @ McpErr { McpJson } }
                }
            } {
                ( response_free resp )
                ^ @ !Json McpErr { F @ McpErr { McpHttp } }
            }
        }
        F _ → ^ @ !Json McpErr { F @ McpErr { McpHttp } }
    }
}

// ── Response inspection ──────────────────────────────────────────────

@ mcp_response_is_error Json r → b {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T _ → ^ T
        F _ → ^ F
    }
}

@ mcp_response_error_code Json r → i {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T err → {
            : ?Json codeo ( json_obj_get err `code` )
            ?? codeo {
                T j → {
                    : ?i n ( json_num_as_i j )
                    ?? n {
                        T x → { ^ x }
                        F _ → { ^ 0 }
                    }
                }
                F _ → { ^ 0 }
            }
        }
        F _ → { ^ 0 }
    }
    ^ 0
}

@ mcp_response_error_message Json r → s {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T err → {
            : ?Json m ( json_obj_get err `message` )
            ?? m {
                T j → ^ ( json_str_data j )
                F _ → ^ ``
            }
        }
        F _ → ^ ``
    }
    ^ ``
}

// Extract the `result` member of a JSON-RPC response envelope.
// Renamed from `mcp_response_result` 2026-05-23 to break the latent
// link-time collision with `mcp.nu`'s 2-arg envelope BUILDER of the
// same name (both ended up in the same IR when a program imported
// `mcp_client.nu`, since the client transitively pulls in `mcp.nu`).
@ mcp_response_get_result Json r → ?Json {
    ^ ( json_obj_get r `result` )
}

// ── Convenience wrappers ─────────────────────────────────────────────

@ mcp_initialize McpClient c s client_name s client_version → !Json McpErr {
    : Json caps ( json_obj_new )
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit client_name ) )
    ( json_obj_set info `version` ( json_str_lit client_version ) )
    : Json params ( json_obj_new )
    // Handshake-era revision — `initialize` IS the legacy path; the
    // modern revision has no handshake (use mcp_discover/_call_modern).
    ( json_obj_set params `protocolVersion` ( json_str_lit ( mcp_protocol_version_initialize ) ) )
    ( json_obj_set params `capabilities` caps )
    ( json_obj_set params `clientInfo` info )
    ^ ( mcp_call c `initialize` @ ?Json { T params } )
}

// ── Modern era (2026-07-28) ──────────────────────────────────────────

// Modern call: injects per-request `_meta` (protocolVersion +
// clientInfo + clientCapabilities — set only when the caller's params
// don't already carry a `_meta`) plus the Mcp-Method and
// MCP-Protocol-Version headers the Streamable HTTP transport requires.
// `params` None → a fresh object is created to carry `_meta`.
@ mcp_call_modern McpClient c s method ? Json params s client_name s client_version → !Json McpErr {
    : Json p ?? params { T pv → pv F _ → ( json_obj_new ) }
    ? ( json_obj_has p `_meta` ) {} {
        ( json_obj_set p `_meta` ( mcp_client_meta client_name client_version ) )
    }
    : String eh ( string_from `Mcp-Method: ` )
    ( string_push_str eh method )
    ( string_push_str eh `\r\nMCP-Protocol-Version: ` )
    ( string_push_str eh ( mcp_protocol_version ) )
    ( string_push_str eh `\r\n` )
    : !Json McpErr r ( __mcp_call_with_headers c method @ ?Json { T p } ( string_data eh ) )
    ( string_free eh )
    ^ r
}

// tools/call with the additional `Mcp-Name` routing header (the
// header names the tool so gateways can meter per-tool). `args` is
// CONSUMED.
@ mcp_tools_call_modern McpClient c s name Json args s client_name s client_version → !Json McpErr {
    : Json params ( json_obj_new )
    ( json_obj_set params `name` ( json_str_lit name ) )
    ( json_obj_set params `arguments` args )
    ( json_obj_set params `_meta` ( mcp_client_meta client_name client_version ) )
    : String eh ( string_from `Mcp-Method: tools/call\r\nMcp-Name: ` )
    ( string_push_str eh name )
    ( string_push_str eh `\r\nMCP-Protocol-Version: ` )
    ( string_push_str eh ( mcp_protocol_version ) )
    ( string_push_str eh `\r\n` )
    : !Json McpErr r ( __mcp_call_with_headers c `tools/call` @ ?Json { T params } ( string_data eh ) )
    ( string_free eh )
    ^ r
}

// server/discover — supported versions + capabilities + identity.
@ mcp_discover McpClient c s client_name s client_version → !Json McpErr {
    ^ ( mcp_call_modern c `server/discover` @ ?Json { F } client_name client_version )
}

// Dual-era probe per the 2026-07-28 versioning page: T when the
// server answered server/discover with a DiscoverResult (modern or
// dual-era server — keep speaking modern), F otherwise (legacy server
// — fall back to mcp_initialize; or transport failure). Cache the
// answer for the lifetime of the origin, per the spec.
@ mcp_server_is_modern McpClient c s client_name s client_version → b {
    : !Json McpErr r ( mcp_discover c client_name client_version )
    ?? r {
        T resp → {
            : ~ b modern F
            : ?Json res ( json_obj_get resp `result` )
            ?? res {
                T rv → {
                    ? ( json_obj_has rv `supportedVersions` ) { = modern T } {}
                }
                F _ → {}
            }
            ( json_free resp )
            ^ modern
        }
        F _ → { ^ F }
    }
}

@ mcp_ping McpClient c → !Json McpErr {
    ^ ( mcp_call c `ping` @ ?Json { F } )
}

// Send tools/list, then unwrap result.tools into an OWNED Vec[Json]
// of cloned tool descriptors. Caller frees with vec_free_with /
// json_free. Empty Vec on shape mismatch (server returned a non-array
// or omitted the field).
@ _extract_array_field Json r s field → ( Vec Json ) {
    : ( Vec Json ) out ( vec_new [Json] )
    : ?Json result ( json_obj_get r `result` )
    ?? result {
        T res → {
            : ?Json arr_o ( json_obj_get res field )
            ?? arr_o {
                T arr → {
                    ( json_arr_each arr \ Json el → v {
                        ( vec_push [Json] out ( json_clone el ) )
                    } )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ mcp_tools_list McpClient c → !( Vec Json ) McpErr {
    : !Json McpErr r ( mcp_call c `tools/list` @ ?Json { F } )
    ?? r {
        T resp → {
            : ( Vec Json ) tools ( _extract_array_field resp `tools` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpErr { T tools }
        }
        F e → ^ @ !( Vec Json ) McpErr { F e }
    }
}

@ mcp_prompts_list McpClient c → !( Vec Json ) McpErr {
    : !Json McpErr r ( mcp_call c `prompts/list` @ ?Json { F } )
    ?? r {
        T resp → {
            : ( Vec Json ) ps ( _extract_array_field resp `prompts` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpErr { T ps }
        }
        F e → ^ @ !( Vec Json ) McpErr { F e }
    }
}

@ mcp_resources_list McpClient c → !( Vec Json ) McpErr {
    : !Json McpErr r ( mcp_call c `resources/list` @ ?Json { F } )
    ?? r {
        T resp → {
            : ( Vec Json ) rs ( _extract_array_field resp `resources` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpErr { T rs }
        }
        F e → ^ @ !( Vec Json ) McpErr { F e }
    }
}

// `args` is the JSON object handed to the tool. Consumed.
@ mcp_tools_call McpClient c s name Json args → !Json McpErr {
    : Json params ( json_obj_new )
    ( json_obj_set params `name` ( json_str_lit name ) )
    ( json_obj_set params `arguments` args )
    ^ ( mcp_call c `tools/call` @ ?Json { T params } )
}
