// mcp_echo_server.nu — minimal MCP stdio server in NURL.
//
// Implements just enough of the protocol to register a single tool
// `echo` and answer the client's tool calls. All transport is
// newline-delimited JSON-RPC 2.0 over stdin/stdout. Logs go to
// stderr — stdout is reserved for protocol bytes.
//
// Run by hand:
//
//     ./build.sh
//     ./nurl.sh examples/mcp_echo_server.nu
//     printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n'\
//            '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'\
//            '{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n'\
//            '{"jsonrpc":"2.0","id":3,"method":"tools/call",'\
//                '"params":{"name":"echo","arguments":{"text":"hello"}}}\n' \
//       | ./examples/mcp_echo_server
//
// Or wire it into Claude Desktop / claude.ai by adding an MCP server
// entry whose `command` invokes the compiled binary.

$ `stdlib/ext/mcp.nu`
$ `stdlib/core/string.nu`

// ── Tool descriptor table ──────────────────────────────────────────
//
// Built once per tools/list. Keeping it inline avoids needing a
// closure-in-struct registry — the server's known tools are a fixed
// list at compile time.

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

// ── Tool dispatch ──────────────────────────────────────────────────
//
// Called from the tools/call handler. Returns the tool result Json
// (including isError flag) — the caller wraps it in a JSON-RPC
// response envelope.

@ run_echo Json args → Json {
    : ?Json text_j ( json_obj_get args `text` )
    ?? text_j {
        T tv → {
            : s text ( json_str_data tv )
            ^ ( mcp_tool_result_text text )
        }
        F → {
            ^ ( mcp_tool_result_error `missing required argument: text` )
        }
    }
    // Unreachable — match is exhaustive — but the compiler wants a
    // trailing return for Json.
    ^ ( mcp_tool_result_error `internal: shape mismatch` )
}

@ dispatch_tool s name Json args → Json {
    ? != ( nurl_str_eq name `echo` ) 0 {
        ^ ( run_echo args )
    } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── Per-method handlers ────────────────────────────────────────────

@ handle_initialize Json id → v {
    : Json result ( mcp_initialize_result `nurl-echo-mcp` `0.1.0` )
    ( mcp_send_message ( mcp_response_result id result ) )
}

// server/discover — 2026-07-28 servers MUST implement this; it also
// serves as the stdio backward-compat probe for dual-era clients.
@ handle_discover Json id → v {
    : Json caps ( json_obj_new )
    ( json_obj_set caps `tools` ( json_obj_new ) )
    : Json result ( mcp_discover_result `nurl-echo-mcp` `0.1.0` caps `` )
    ( mcp_send_message ( mcp_response_result id result ) )
}

@ handle_ping Json id → v {
    : Json empty ( json_obj_new )
    ( mcp_send_message ( mcp_response_result id empty ) )
}

@ handle_tools_list Json id → v {
    : ( Vec Json ) tools ( build_tools_list )
    : Json result ( mcp_tools_list_result tools )
    ( mcp_send_message ( mcp_response_result id result ) )
}

@ handle_tools_call Json id Json params → v {
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
            ( mcp_send_message ( mcp_response_result id result ) )
        }
        F → {
            ( mcp_send_message
            ( mcp_response_error id mcp_err_invalid_params
            `tools/call requires a "name" parameter` ) )
        }
    }
}

@ handle_unknown_method Json id s method → v {
    : i mlen ( nurl_str_len method )
    : String msg ( string_with_cap + 32 mlen )
    ( string_push_str msg `unknown method: ` )
    ( string_push_str msg method )
    ( mcp_send_message
    ( mcp_response_error id mcp_err_method_not_found ( string_data msg ) ) )
    ( string_free msg )
}

// ── Main loop ──────────────────────────────────────────────────────

@ handle Json req → v {
    : ?Json method_j ( json_obj_get req `method` )
    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )
            : ?Json id_opt ( json_obj_get req `id` )

            // Notifications (no `id`) require no response. We branch first
            // so that valid notifications never trigger a method-not-found
            // reply for, e.g., `notifications/initialized`.
            ?? id_opt {
                T id → {
                    ? != ( nurl_str_eq method `server/discover` ) 0 {
                        ( handle_discover id )
                    } {
                        ? != ( nurl_str_eq method `initialize` ) 0 {
                            ( handle_initialize id )
                        } {
                            ? != ( nurl_str_eq method `ping` ) 0 {
                                ( handle_ping id )
                            } {
                                ? != ( nurl_str_eq method `tools/list` ) 0 {
                                    ( handle_tools_list id )
                                } {
                                    ? != ( nurl_str_eq method `tools/call` ) 0 {
                                        : ?Json params_j ( json_obj_get req `params` )
                                        : Json params ?? params_j {
                                            T pv → ( json_clone pv )
                                            F → ( json_obj_new )
                                        }
                                        ( handle_tools_call id params )
                                        ( json_free params )
                                    } {
                                        ( handle_unknown_method id method )
                                    } } } } }
                }
                F → {
                    // Notification — nothing to send. Trace at most.
                    ? != ( nurl_str_eq method `notifications/initialized` ) 0 {
                        ( mcp_log `client initialized` )
                    } {}
                }
            }
        }
        F → {
            ( mcp_log `request without method, ignoring` )
        }
    }
}

@ main → i {
    ( mcp_log `nurl-echo-mcp 0.1.0 ready` )
    : ~ b running T
    ~ running {
        : ?Json msg ( mcp_read_request )
        ?? msg {
            T req → {
                ( handle req )
                ( json_free req )
            }
            F _ → {
                = running F
            }
        }
    }
    ( mcp_log `bye` )
    ^ 0
}
