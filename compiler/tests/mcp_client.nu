// mcp_client.nu — MCP HTTP client acceptance test. Pure offline:
// envelope shapes + response inspection are exercised directly.
// The actual HTTP round-trip (mcp_call against a live server) is
// gated by NURL_HTTP_TESTS=1 — same convention as `http_basic.nu`.
//
// Coverage:
//   * mcp_client_new + free (empty + populated endpoint).
//   * Empty endpoint → mcp_call returns McpAuth without touching net.
//   * mcp_err_name covers all variants.
//   * mcp_response_is_error / _error_code / _error_message on a
//     synthetic JSON-RPC error envelope.
//   * mcp_response_get_result extracts the `result` object on success.
//   * `__extract_array_field` accessible via tool/prompt/resource list
//     extraction is exercised by feeding a synthetic response.

$ `stdlib/ext/mcp_client.nu`
$ `stdlib/ext/json.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_int s prefix i n → v {
    ( nurl_print prefix )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

@ println_bool s prefix b v → v {
    ( nurl_print prefix )
    ? v { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )
}

// ── McpErr name table ────────────────────────────────────────────────

@ run_err_names → v {
    ( nurl_print `── McpErr names ──\n` )
    ( println_str `  McpAuth     = ` ( mcp_err_name @ McpErr { McpAuth } ) )
    ( println_str `  McpHttp     = ` ( mcp_err_name @ McpErr { McpHttp } ) )
    ( println_str `  McpJson     = ` ( mcp_err_name @ McpErr { McpJson } ) )
    ( println_str `  McpProtocol = ` ( mcp_err_name @ McpErr { McpProtocol } ) )
    ( println_str `  McpOther    = ` ( mcp_err_name @ McpErr { McpOther } ) )
}

// ── Empty endpoint short-circuit ─────────────────────────────────────

@ run_auth_short_circuit → v {
    ( nurl_print `── empty endpoint ──\n` )
    : McpClient c ( mcp_client_new `` 5000 )
    : !Json McpErr r ( mcp_call c `ping` @ ?Json { F ( json_null ) } )
    ?? r {
        T j → {
            ( nurl_print `  UNEXPECTED Some\n` )
            ( json_free j )
        }
        F e → ( println_str `  err = ` ( mcp_err_name e ) )
    }
    ( mcp_client_free c )
}

// ── Synthetic response inspection ────────────────────────────────────
//
// Build a minimal JSON-RPC error envelope by hand and feed it into
// mcp_response_is_error / _error_code / _error_message. Then a
// success envelope and verify mcp_response_get_result extracts the inner
// object. Validates the JSON path-walk without network.

@ run_response_inspect → v {
    ( nurl_print `── error response inspect ──\n` )
    // { "jsonrpc": "2.0", "id": 1, "error": { "code": -32602, "message": "Invalid params" } }
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int -32602 ) )
    ( json_obj_set err `message` ( json_str_lit `Invalid params` ) )
    : Json resp ( json_obj_new )
    ( json_obj_set resp `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set resp `id` ( json_int 1 ) )
    ( json_obj_set resp `error` err )

    ( println_bool `  is_error    = ` ( mcp_response_is_error resp ) )
    ( println_int `  error_code  = ` ( mcp_response_error_code resp ) )
    ( println_str `  error_msg   = ` ( mcp_response_error_message resp ) )
    ( json_free resp )

    ( nurl_print `── success response inspect ──\n` )
    // { "jsonrpc": "2.0", "id": 2, "result": { "tools": [], "ok": true } }
    : Json result ( json_obj_new )
    ( json_obj_set result `tools` ( json_arr_new ) )
    ( json_obj_set result `ok` ( json_bool T ) )
    : Json resp2 ( json_obj_new )
    ( json_obj_set resp2 `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set resp2 `id` ( json_int 2 ) )
    ( json_obj_set resp2 `result` result )

    ( println_bool `  is_error    = ` ( mcp_response_is_error resp2 ) )
    : ?Json got ( mcp_response_get_result resp2 )
    ?? got {
        T res → {
            // We don't free `res` — borrowed view into resp2.
            : ?Json ok_o ( json_obj_get res `ok` )
            ?? ok_o {
                T j → ( println_bool `  result.ok   = ` ( json_bool_val j ) )
                F _ → ( nurl_print `  result.ok missing\n` )
            }
        }
        F _ → ( nurl_print `  result missing\n` )
    }
    ( json_free resp2 )
}

// ── tools/list extraction (synthetic response) ───────────────────────
//
// Build a response containing { result: { tools: [{name:"echo"},
// {name:"add"}] } } and call our extraction logic. We can't call
// mcp_tools_list directly without a network round-trip, but the
// underlying __extract_array_field is the only meaningful step, and
// it's exposed to test through the same code path mcp_tools_list
// uses internally — replicate the call shape here.

@ run_tools_extract → v {
    ( nurl_print `── tools array extract ──\n` )
    : Json tools ( json_arr_new )
    : Json t1 ( json_obj_new )
    ( json_obj_set t1 `name` ( json_str_lit `echo` ) )
    ( json_arr_push tools t1 )
    : Json t2 ( json_obj_new )
    ( json_obj_set t2 `name` ( json_str_lit `add` ) )
    ( json_arr_push tools t2 )

    : Json result ( json_obj_new )
    ( json_obj_set result `tools` tools )
    : Json resp ( json_obj_new )
    ( json_obj_set resp `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set resp `id` ( json_int 3 ) )
    ( json_obj_set resp `result` result )

    : ( Vec Json ) extracted ( __extract_array_field resp `tools` )
    ( println_int `  count = ` ( vec_len [Json] extracted ) )

    : i n ( vec_len [Json] extracted )
    : *Json data ( vec_data [Json] extracted )
    : ~ i k 0
    ~ < k n {
        : Json el . data k
        : ?Json name_o ( json_obj_get el `name` )
        ?? name_o {
            T j → ( println_str `  tool = ` ( json_str_data j ) )
            F _ → ( nurl_print `  unnamed\n` )
        }
        = k + k 1
    }
    ( vec_free_with [Json] extracted \ Json e → v { ( json_free e ) } )
    ( json_free resp )
}

@ main → i {
    ( run_err_names )
    ( run_auth_short_circuit )
    ( run_response_inspect )
    ( run_tools_extract )
    ^ 0
}
