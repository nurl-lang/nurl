// unikernel/demos/mcpd.nu — an MCP endpoint that IS the machine.
//
// The plan's endpoint milestone (B10) is a unikernel that boots
// straight into a running MCP node. This is that shape with the
// repository's own echo server as the payload: the dispatch function
// and every layer under it are `examples/mcp_echo_server_http.nu`
// unchanged — JSON-RPC over Streamable HTTP, the same
// `mcp_http_handler` the corpus tests drive — and the only difference
// is the address it binds and the machine it binds on.
//
// 0.0.0.0 rather than 127.0.0.1, because on this machine there is
// nobody else to talk to locally: the client is on the host, through
// the hypervisor's port forward. The example keeps its loopback bind,
// since on a Linux box that IS the safe default and changing it there
// would expose someone's echo server to their network.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`

// ── Tool descriptor table ──────────────────────────────────────────

@ build_tools_list → ( Vec Json ) {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )

    : Json props ( json_obj_new )
    : Json text_prop ( json_obj_new )
    ( json_obj_set text_prop `type` ( json_str_lit `string` ) )
    ( json_obj_set text_prop `description` ( json_str_lit `Text to echo` ) )
    ( json_obj_set props `text` text_prop )
    ( json_obj_set schema `properties` props )

    : Json required ( json_arr_new )
    ( json_arr_push required ( json_str_lit `text` ) )
    ( json_obj_set schema `required` required )

    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools
    ( mcp_tool_descriptor `echo` `Echo the supplied text back to the caller.` schema ) )
    ^ tools
}

// ── Tool runners ───────────────────────────────────────────────────

@ run_echo Json args → Json {
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

@ dispatch_tool s name Json args → Json {
    ? != 0 ( nurl_str_eq name `echo` ) {
        ^ ( run_echo args )
    } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── Per-method handlers (return-style for HTTP transport) ─────────

@ handle_initialize Json id → Json {
    : Json result ( mcp_initialize_result `nurl-echo-mcp-http` `0.1.0` )
    ^ ( mcp_response_result id result )
}

@ handle_ping Json id → Json {
    : Json empty ( json_obj_new )
    ^ ( mcp_response_result id empty )
}

@ handle_tools_list Json id → Json {
    : ( Vec Json ) tools ( build_tools_list )
    : Json result ( mcp_tools_list_result tools )
    ^ ( mcp_response_result id result )
}

@ handle_tools_call Json id Json params → Json {
    : ?Json name_j ( json_obj_get params `name` )
    ?? name_j {
        T nv → {
            : s name ( json_str_data nv )
            : ?Json args_j ( json_obj_get params `arguments` )
            : Json args ?? args_j {
                T av → ( json_clone av )
                F → ( json_obj_new )
            }
            : Json result ( dispatch_tool name args )
            ( json_free args )
            ^ ( mcp_response_result id result )
        }
        F → {
            ^ ( mcp_response_error id mcp_err_invalid_params
            `tools/call requires a "name" parameter` )
        }
    }
}

// ── HTTP-transport dispatcher ─────────────────────────────────────
//
// Mirror of mcp_echo_server.nu's `handle` — but where the stdio
// version writes via `mcp_send_message`, this returns the response
// Json so `mcp_http_handler` can wrap it in an HTTP envelope.
// Notifications return None, becoming HTTP 202 Accepted on the wire.

@ dispatch Json req → ?Json {
    : ?Json method_j ( json_obj_get req `method` )
    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )
            : ?Json id_opt ( json_obj_get req `id` )

            ?? id_opt {
                T id → {
                    ? != 0 ( nurl_str_eq method `initialize` ) {
                        ^ @ ?Json { T ( handle_initialize id ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `ping` ) {
                        ^ @ ?Json { T ( handle_ping id ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/list` ) {
                        ^ @ ?Json { T ( handle_tools_list id ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/call` ) {
                        : ?Json params_j ( json_obj_get req `params` )
                        : Json params ?? params_j {
                            T pv → ( json_clone pv )
                            F → ( json_obj_new )
                        }
                        : Json out ( handle_tools_call id params )
                        ( json_free params )
                        ^ @ ?Json { T out }
                    } {}
                    // Unknown method.
                    : i mlen ( nurl_str_len method )
                    : String msg ( string_with_cap + 32 mlen )
                    ( string_push_str msg `unknown method: ` )
                    ( string_push_str msg method )
                    : Json err ( mcp_response_error id mcp_err_method_not_found
                    ( string_data msg ) )
                    ( string_free msg )
                    ^ @ ?Json { T err }
                }
                F → {
                    // Notification — log and skip.
                    ? != 0 ( nurl_str_eq method `notifications/initialized` ) {
                        ( mcp_log `client initialized` )
                    } {}
                    ^ @ ?Json { F @ Json { JNull } }
                }
            }
        }
        F → {
            ( mcp_log `request without method, ignoring` )
            ^ @ ?Json { F @ Json { JNull } }
        }
    }
}

// ── main ───────────────────────────────────────────────────────────

@ main → i {
    : ( @ ?Json Json ) f \ Json req → ?Json { ^ ( dispatch req ) }
    ( mcp_log `serving MCP on 0.0.0.0:18770` )
    : !v NetErr r ( mcp_server_run_http `0.0.0.0` 18770 f )
    ?? r {
        T _ → 0
        F e → {
            ( mcp_log ( net_err_name e ) )
            ^ 1
        }
    }
    ^ 0
}
