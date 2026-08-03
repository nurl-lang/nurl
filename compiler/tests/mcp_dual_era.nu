// mcp_dual_era.nu — offline regression for the 2026-07-28 dual-era
// registry behavior on top of mcp_registry_envelope:
//   * server/discover returns supportedVersions + caps + _meta
//     serverInfo + the CacheableResult fields
//   * a modern request (per-request `_meta` protocolVersion) gets
//     `_meta` serverInfo on its result; a legacy request does not
//   * an unsupported declared version gets the spec-shaped
//     UnsupportedProtocolVersionError (-32022, data.supported)
//   * legacy `initialize` echoes a supported handshake-era revision
//     and never advertises the modern (handshake-less) revision
//   * list results carry ttlMs + cacheScope; every result carries
//     resultType "complete"
// No sockets, no stdio — pure dispatcher exercises, full response
// JSON printed so the wire shape is locked byte-for-byte.

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_registry.nu`

@ echo_tool Json args → Json {
    : ?Json t ( json_obj_get args `text` )
    : ~ s text `(none)`
    ?? t {
        T jt → { = text ( json_as_str jt ) }
        F _ → {}
    }
    ^ ( mcp_tool_result_text text )
}

@ roundtrip McpRegistry r s tag s reqs → v {
    : !Json JsonError pj ( json_parse reqs )
    ?? pj {
        T req → {
            : ?Json resp_o ( mcp_registry_envelope r req )
            ?? resp_o {
                T resp → {
                    : String out ( json_stringify resp )
                    ( nurl_print tag )
                    ( nurl_print ` ` )
                    ( nurl_print ( string_data out ) )
                    ( nurl_print `\n` )
                    ( string_free out )
                    ( json_free resp )
                }
                F e → {
                    ( json_free e )
                    ( nurl_print tag )
                    ( nurl_print ` (no response)\n` )
                }
            }
            ( json_free req )
        }
        F _ → { ( nurl_print `parse fail\n` ) }
    }
}

@ main → i {
    : McpRegistry r ( mcp_registry_new `dual-test` `1.2.3` )
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    ( mcp_registry_add_tool r `echo` `Echo back the input.` schema \ Json a → Json { ^ ( echo_tool a ) } )

    // Modern: server/discover.
    ( roundtrip r `discover` `{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"t","version":"0"}}}}` )

    // Modern: tools/list — CacheableResult fields + _meta serverInfo.
    ( roundtrip r `list-mod` `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}` )

    // Modern: tools/call still works with per-request _meta.
    ( roundtrip r `call-mod` `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}` )

    // Unsupported declared version → -32022 with data.supported.
    ( roundtrip r `badver` `{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01"}}}` )

    // Legacy initialize, old revision → echoed back.
    ( roundtrip r `init-old` `{"jsonrpc":"2.0","id":5,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}` )

    // Legacy initialize requesting the modern revision → answered with
    // the newest handshake-era revision instead (2026-07-28 has no
    // handshake; echoing it would strand a legacy client).
    ( roundtrip r `init-mod` `{"jsonrpc":"2.0","id":6,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}` )

    // Legacy tools/list (no _meta) → no serverInfo _meta on the result.
    ( roundtrip r `list-leg` `{"jsonrpc":"2.0","id":7,"method":"tools/list"}` )

    // Legacy ping still answered.
    ( roundtrip r `ping` `{"jsonrpc":"2.0","id":8,"method":"ping"}` )

    ( mcp_registry_free r )
    ^ 0
}
