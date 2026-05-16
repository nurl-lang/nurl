// tools/nurl-lsp/main.nu — NURL Language Server (Phase 1: lifecycle).
//
// Stdio JSON-RPC server. Listens for LSP requests + notifications,
// dispatches by `method` name, writes responses for requests. This
// phase implements the protocol-lifecycle skeleton only:
//
//   * initialize   → reply with ServerCapabilities + serverInfo
//   * initialized  (notification) → no-op
//   * shutdown     → reply with null, set g_shutdown_received
//   * exit         (notification) → exit 0 if shutdown received, 1 otherwise
//
// Anything else: unknown requests get a JSON-RPC MethodNotFound error
// reply; unknown notifications are logged to stderr and ignored.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `tools/nurl-lsp/jsonrpc.nu`

: ~ b g_shutdown_received F
: ~ b g_exit_requested F

@ __build_capabilities → Json {
    : Json caps ( json_obj_new )
    ( json_obj_set caps `textDocumentSync` ( json_int 1 ) )
    ^ caps
}

@ __build_server_info → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit `nurl-lsp` ) )
    ( json_obj_set info `version` ( json_str_lit `0.4.1` ) )
    ^ info
}

@ __make_response Json id Json result → Json {
    : Json env ( json_obj_new )
    ( json_obj_set env `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set env `id` id )
    ( json_obj_set env `result` result )
    ^ env
}

@ __make_error Json id i code s msg → Json {
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int code ) )
    ( json_obj_set err `message` ( json_str_lit msg ) )
    : Json env ( json_obj_new )
    ( json_obj_set env `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set env `id` id )
    ( json_obj_set env `error` err )
    ^ env
}

@ __handle_initialize Json id → v {
    : Json caps ( __build_capabilities )
    : Json info ( __build_server_info )
    : Json result ( json_obj_new )
    ( json_obj_set result `capabilities` caps )
    ( json_obj_set result `serverInfo` info )
    : Json resp ( __make_response id result )
    ( write_message resp )
    ( json_free resp )
}

@ __handle_shutdown Json id → v {
    = g_shutdown_received T
    : Json resp ( __make_response id ( json_null ) )
    ( write_message resp )
    ( json_free resp )
}

@ __handle_unknown_request Json id s method → v {
    : String msg ( string_with_cap 64 )
    ( string_push_str msg `method not found: ` )
    ( string_push_str msg method )
    : Json resp ( __make_error id - 0 32601 ( string_data msg ) )
    ( write_message resp )
    ( json_free resp )
    ( string_free msg )
}

// Dispatch a single message. Sets g_exit_requested when the loop
// should terminate (after `exit` notification OR EOF).
// json_obj_get returns a BORROWED view into `msg`'s subtree — never
// json_free its result. Only the cloned `id` that we hand to a
// response builder needs explicit freeing, and that happens inside
// the handler via the `json_free resp` of the enclosing envelope.
@ __dispatch Json msg → v {
    : ?Json mo ( json_obj_get msg `method` )
    ?? mo {
        F _ → {}
        T method_j → {
            : s method ( json_str_data method_j )
            : ?Json id_o ( json_obj_get msg `id` )
            ?? id_o {
                T id_j → {
                    : Json id ( json_clone id_j )
                    ? ( nurl_str_eq method `initialize` ) {
                        ( __handle_initialize id )
                    } {
                        ? ( nurl_str_eq method `shutdown` ) {
                            ( __handle_shutdown id )
                        } {
                            ( __handle_unknown_request id method )
                        }
                    }
                }
                F _ → {
                    ? ( nurl_str_eq method `exit` ) {
                        = g_exit_requested T
                    } {
                        ? ( nurl_str_eq method `initialized` ) {} {
                            ( nurl_eprintln method )
                        }
                    }
                }
            }
        }
    }
}

@ main → i {
    : ~ b done F
    ~ ! done {
        : ?Json mr ( read_message )
        ?? mr {
            F _ → { = done T }
            T msg → {
                ( __dispatch msg )
                ( json_free msg )
                ? g_exit_requested { = done T } {}
            }
        }
    }
    ? g_shutdown_received { ^ 0 } { ^ 1 }
}
