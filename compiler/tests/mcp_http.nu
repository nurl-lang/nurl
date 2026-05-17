// mcp_http.nu — offline acceptance test for stdlib/ext/mcp_http.nu.
// Builds synthetic HttpRequests in-memory, runs them through the MCP
// HTTP handler, prints status + body so the snapshot pins the exact
// wire-shape per case. No socket, no curl. Gated alongside
// http_request_parser / http_response_builder / http_router in
// run_tests.{bat,sh}.
//
// Coverage:
//   * POST initialize (well-formed JSON-RPC request) → 200 + envelope
//   * POST notifications/initialized (no id) → 202 Accepted, no body
//   * POST tools/list → 200 + tools array
//   * POST tools/call (echo) → 200 + content array
//   * POST malformed JSON body → 200 + JSON-RPC parse_error envelope
//   * POST empty body → 200 + JSON-RPC invalid_request envelope
//   * GET / → 405 (no SSE in MVP)
//   * DELETE / → 204 (stateless)
//   * OPTIONS / → 204 + CORS preflight headers
//   * PUT / → 405 (unknown method)

$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

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

// Build a synthetic HttpRequest. POST bodies are encoded into the
// request's body Vec[u]; non-POST methods leave it empty.
@ make_req s method s path s body → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    : i blen ( nurl_str_len body )
    ? > blen 0 {
        ( bytes_extend_str . req body body )
    } {}
    ^ req
}

@ body_to_string HttpResponse r → String {
    : i n ( vec_len [u] . r body )
    : *u data ( vec_data [u] . r body )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : u byte . data k
        ( string_push_char out # i byte )
        = k + k 1
    }
    ^ out
}

// Test dispatcher. Mirrors the per-method dispatch from
// examples/mcp_echo_server.nu but returns ? Json instead of writing
// to stdout. Notifications (no `id`) return None.

@ test_run_echo Json args → Json {
    : ?Json text_j ( json_obj_get args `text` )
    ?? text_j {
        T tv → {
            : s text ( json_str_data tv )
            ^ ( mcp_tool_result_text text )
        }
        F → ^ ( mcp_tool_result_error `missing required argument: text` )
    }
    ^ ( mcp_tool_result_error `internal: unreachable` )
}

@ test_build_tools_list → ( Vec Json ) {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )

    : Json props ( json_obj_new )
    : Json tprop ( json_obj_new )
    ( json_obj_set tprop `type` ( json_str_lit `string` ) )
    ( json_obj_set props `text` tprop )
    ( json_obj_set schema `properties` props )

    : Json req_arr ( json_arr_new )
    ( json_arr_push req_arr ( json_str_lit `text` ) )
    ( json_obj_set schema `required` req_arr )

    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools
    ( mcp_tool_descriptor `echo` `Echo back the input.` schema ) )
    ^ tools
}

// Dispatcher: handles initialize, ping, tools/list, tools/call.
// Returns None for notifications (no `id`). Mirrors the stdio-side
// `handle` shape but returns owned Json instead of writing.
@ test_dispatch Json req → ?Json {
    : ?Json id_opt ( json_obj_get req `id` )
    : ?Json method_j ( json_obj_get req `method` )

    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )

            ?? id_opt {
                T id → {
                    // Has id → request, build response.
                    ? != 0 ( nurl_str_eq method `initialize` ) {
                        : Json result ( mcp_initialize_result `nurl-mcp-test` `0.1.0` )
                        ^ @ ?Json { T ( mcp_response_result id result ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `ping` ) {
                        : Json empty ( json_obj_new )
                        ^ @ ?Json { T ( mcp_response_result id empty ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/list` ) {
                        : ( Vec Json ) tools ( test_build_tools_list )
                        : Json result ( mcp_tools_list_result tools )
                        ^ @ ?Json { T ( mcp_response_result id result ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/call` ) {
                        : ?Json params_j ( json_obj_get req `params` )
                        : Json params ?? params_j {
                            T pv → ( json_clone pv )
                            F → ( json_obj_new )
                        }
                        : ?Json name_j ( json_obj_get params `name` )
                        ?? name_j {
                            T nv → {
                                : s name ( json_str_data nv )
                                : ?Json args_j ( json_obj_get params `arguments` )
                                : Json args ?? args_j {
                                    T av → ( json_clone av )
                                    F → ( json_obj_new )
                                }
                                : Json result ? != 0 ( nurl_str_eq name `echo` )
                                ( test_run_echo args )
                                ( mcp_tool_result_error `unknown tool` )
                                ( json_free args )
                                ( json_free params )
                                ^ @ ?Json { T ( mcp_response_result id result ) }
                            }
                            F → {
                                ( json_free params )
                                : Json err ( mcp_response_error id mcp_err_invalid_params `tools/call requires "name"` )
                                ^ @ ?Json { T err }
                            }
                        }
                    } {}
                    // Unknown method — error response.
                    : Json err ( mcp_response_error id mcp_err_method_not_found `unknown method` )
                    ^ @ ?Json { T err }
                }
                F → {
                    // Notification → no reply.
                    ^ @ ?Json { F @ Json { JNull } }
                }
            }
        }
        F → {
            // No method field — invalid. Return None so the handler
            // surfaces a 202 (we treat this like a notification).
            ^ @ ?Json { F @ Json { JNull } }
        }
    }
}

@ run_case
( @ HttpResponse HttpRequest ) handler
s label s method s path s body → v {
    ( nurl_print `── ` ) ( nurl_print label ) ( nurl_print ` ──\n` )
    : HttpRequest req ( make_req method path body )
    : HttpResponse resp ( handler req )
    ( println_int `  status=` . resp status )
    : ?String ct ( header_get . resp headers `Content-Type` )
    ?? ct {
        T s → { ( println_str `  ct=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  ct=` `<absent>` ) ( string_free e ) }
    }
    : ?String acao ( header_get . resp headers `Access-Control-Allow-Origin` )
    ?? acao {
        T s → { ( println_str `  cors=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  cors=` `<absent>` ) ( string_free e ) }
    }
    : String body_s ( body_to_string resp )
    : i bl ( string_len body_s )
    ( println_int `  body_len=` bl )
    ? > bl 0 {
        ( println_str `  body=` ( string_data body_s ) )
    } {
        ( println_str `  body=` `<empty>` )
    }
    ( string_free body_s )
    ( http_response_free resp )
    ( request_free req )
}

@ main → i {
    // Build the handler once. Closure literal wraps the @-function so
    // it conforms to the (@ ? Json Json) closure-typed parameter.
    : ( @ ?Json Json ) dispatch \ Json req → ?Json { ^ ( test_dispatch req ) }
    : ( @ HttpResponse HttpRequest ) handler ( mcp_http_handler dispatch )

    ( run_case handler `post_initialize` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}` )

    ( run_case handler `post_notification` `POST` `/mcp`
    `{"jsonrpc":"2.0","method":"notifications/initialized"}` )

    ( run_case handler `post_ping` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":2,"method":"ping"}` )

    ( run_case handler `post_tools_list` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":3,"method":"tools/list"}` )

    ( run_case handler `post_tools_call_echo` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}` )

    ( run_case handler `post_unknown_method` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":5,"method":"frobnicate"}` )

    ( run_case handler `post_malformed_json` `POST` `/mcp`
    `{"jsonrpc":"2.0","id":` )

    ( run_case handler `post_empty_body` `POST` `/mcp` `` )

    ( run_case handler `get_endpoint` `GET` `/mcp` `` )

    ( run_case handler `delete_endpoint` `DELETE` `/mcp` `` )

    ( run_case handler `options_preflight` `OPTIONS` `/mcp` `` )

    ( run_case handler `put_endpoint` `PUT` `/mcp` `whatever` )

    // ── Batch (JSON-RPC 2.0 array-of-requests) ─────────────────────────
    ( run_case handler `batch_mixed` `POST` `/mcp`
    `[{"jsonrpc":"2.0","id":10,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":11,"method":"frobnicate"}]` )

    ( run_case handler `batch_all_notifications` `POST` `/mcp`
    `[{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","method":"notifications/initialized"}]` )

    ( run_case handler `batch_empty` `POST` `/mcp` `[]` )

    // ── Mcp-Session-Id echo (v2 forward-compat surface) ────────────────
    ( nurl_print `── session_echo_post ──\n` )
    : HttpRequest sreq ( make_req `POST` `/mcp` `{"jsonrpc":"2.0","id":99,"method":"ping"}` )
    : Header sh @ Header { ( string_from `Mcp-Session-Id` ) ( string_from `sess-abc-123` ) }
    ( vec_push [Header] . sreq headers sh )
    : HttpResponse sresp ( handler sreq )
    : ?String sout ( header_get . sresp headers `Mcp-Session-Id` )
    ?? sout {
        T s → { ( println_str `  echoed=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  echoed=` `<absent>` ) ( string_free e ) }
    }
    ( http_response_free sresp )
    ( request_free sreq )

    ( nurl_print `── session_echo_get ──\n` )
    : HttpRequest sreq2 ( make_req `GET` `/mcp` `` )
    : Header sh2 @ Header { ( string_from `Mcp-Session-Id` ) ( string_from `sess-xyz-789` ) }
    ( vec_push [Header] . sreq2 headers sh2 )
    : HttpResponse sresp2 ( handler sreq2 )
    : ?String sout2 ( header_get . sresp2 headers `Mcp-Session-Id` )
    ?? sout2 {
        T s → { ( println_str `  echoed=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  echoed=` `<absent>` ) ( string_free e ) }
    }
    ( http_response_free sresp2 )
    ( request_free sreq2 )

    ( nurl_print `── session_absent ──\n` )
    : HttpRequest noreq ( make_req `POST` `/mcp` `{"jsonrpc":"2.0","id":100,"method":"ping"}` )
    : HttpResponse noresp ( handler noreq )
    : ?String noout ( header_get . noresp headers `Mcp-Session-Id` )
    ?? noout {
        T s → { ( println_str `  echoed=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  echoed=` `<absent>` ) ( string_free e ) }
    }
    ( http_response_free noresp )
    ( request_free noreq )

    ^ 0
}
