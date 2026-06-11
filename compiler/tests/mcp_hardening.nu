// mcp_hardening.nu — regressions for the MCP bulletproofing pass.
//
//   1. Registry handler panic-guard. A tool handler that PANICS must yield a
//      tool-error envelope (isError:true) — never unwind the dispatch, which
//      over stdio would crash the whole MCP server process. A handler that
//      SUCCEEDS must still return its real result (the panic guard carries
//      the value out of the recover closure through a shared-ctl Vec sink;
//      a naive `= result ...` inside the closure does NOT propagate, so the
//      success case is the load-bearing half of this test).
//   2. Reverse-RPC id gating. mcp_session_resolve_rpc must REJECT a response
//      whose id was never issued (forged / non-pending — otherwise a client
//      floods the results queue and can inject forged results), while still
//      settling a genuinely-pending reverse RPC.
//
// main returns the failure count (0 = pass).

$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_registry.nu`
$ `stdlib/ext/mcp_session.nu`

@ echo_handler Json args → Json {
    ^ ( mcp_tool_result_text `HELLO_REAL` )
}

// A tool handler that always panics. Handlers BORROW args (the dispatcher
// frees it), so we must NOT free args here.
@ boom_handler Json args → Json {
    ( panic `kaboom` )
    ^ ( json_null )
}

// Pull the first content item's `text` out of a tool-result envelope.
@ first_text Json res → s {
    : ?Json c ( json_obj_get res `content` )
    ^ ?? c {
        T arr → {
            : ?Json e0 ( json_arr_get arr 0 )
            ^ ?? e0 {
                T el → {
                    : ?Json t ( json_obj_get el `text` )
                    ^ ?? t { T tj → ( json_str_data tj ) F → `(notext)` }
                }
                F → `(noel)`
            }
        }
        F → `(nocontent)`
    }
}

@ call_tool McpRegistry r s name → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `name` ( json_str_lit name ) )
    ( json_obj_set p `arguments` ( json_obj_new ) )
    : Json out ( mcp_registry_dispatch r `tools/call` @ ?Json { T p } )
    ( json_free p )
    ^ out
}

@ run → i {
    : ~ i fails 0

    : McpRegistry r ( mcp_registry_new `t` `1.0` )
    ( mcp_registry_add_tool r `echo` `ok` ( json_obj_new ) \ Json a → Json { ^ ( echo_handler a ) } )
    ( mcp_registry_add_tool r `boom` `panics` ( json_obj_new ) \ Json a → Json { ^ ( boom_handler a ) } )

    // 1a. Success path must return the real result.
    : Json r1 ( call_tool r `echo` )
    : s t1 ( first_text r1 )
    ? != 0 ( nurl_str_eq t1 `HELLO_REAL` ) { ( puts `ok: success tool returned real result` ) }
    { ( nurl_eprintln ( nurl_str_cat `FAIL: success path got: ` t1 ) ) = fails + fails 1 }
    ( json_free r1 )

    // 1b. Panic path must return an isError envelope, not crash.
    : Json r2 ( call_tool r `boom` )
    : ?Json ie ( json_obj_get r2 `isError` )
    ?? ie {
        T j → {
            ? ( json_as_bool j ) { ( puts `ok: tool panic returned isError` ) }
            { ( nurl_eprintln `FAIL: isError not true` ) = fails + fails 1 }
        }
        F → { ( nurl_eprintln `FAIL: no isError field` ) = fails + fails 1 }
    }
    ( json_free r2 )
    ( mcp_registry_free r )

    // 2. resolve_rpc rejects a non-pending (forged) id, settles a pending one.
    : McpSessionStore st ( mcp_session_store_new )
    : String sid ( mcp_session_create st )
    : s sids ( string_data sid )

    : Json forged ( json_obj_new )
    ( json_obj_set forged `id` ( json_int 999 ) )
    ( json_obj_set forged `result` ( json_obj_new ) )
    : b accepted ( mcp_session_resolve_rpc st sids forged )
    ? accepted { ( nurl_eprintln `FAIL: forged response accepted` ) = fails + fails 1 }
    { ( puts `ok: forged reverse-RPC response rejected` ) }

    : Json p ( json_obj_new )
    : i rid ( mcp_session_begin_rpc st sids `sampling/createMessage` p )
    : Json good ( json_obj_new )
    ( json_obj_set good `id` ( json_int rid ) )
    ( json_obj_set good `result` ( json_obj_new ) )
    : b ok2 ( mcp_session_resolve_rpc st sids good )
    ? ok2 { ( puts `ok: pending reverse-RPC response settled` ) }
    { ( nurl_eprintln `FAIL: pending response rejected` ) = fails + fails 1 }

    ( string_free sid )
    ( mcp_session_store_free st )
    ^ fails
}

@ main → i { ^ ( run ) }
