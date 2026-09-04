// mcp_server_contract.nu — the WIRE, frozen.
//
// The other MCP tests check that a field has the value they expect.
// This one prints the exact bytes of every response the server can
// produce, and its golden freezes them. That is the difference between
// "the facade works" and "work underneath the facade cannot break the
// programs above it": a refactor that renames a key, reorders an
// object, drops `resultType`, changes a TTL, or moves an error code
// fails HERE, in CI, instead of in somebody's client.
//
// It is deliberately dull to read. Every line is a promise.
//
// What is pinned:
//   * initialize (legacy handshake) and server/discover (2026-07-28)
//   * the version gate: an unsupported declared version → -32022 with
//     `data.supported` so a client can retry on a mutual revision
//   * `_meta` serverInfo on a modern request, absent on a legacy one
//   * tools/list — descriptors, built schemas, annotations, the
//     CacheableResult fields
//   * tools/call — success, tool-level error, unknown tool, and a
//     PANICKING handler (which must become one error envelope, not a
//     dead process)
//   * prompts and resources, list and get/read
//   * completion/complete
//   * every JSON-RPC error code the dispatcher can emit
//   * a notification (no id) producing no response at all
//
// If you are changing this file's golden, you are changing what
// clients see. That should be a sentence in the commit message.

$ `stdlib/ext/mcp_server.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_tasks.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

// ── request builders ────────────────────────────────────────────────

@ req s method → Json {
    : Json r ( json_obj_new )
    ( json_obj_set r `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set r `method` ( json_str_lit method ) )
    ^ r
}

@ req_id i id s method → Json {
    : Json r ( req method )
    ( json_obj_set r `id` ( json_int id ) )
    ^ r
}

@ with_params Json r Json params → Json {
    ( json_obj_set r `params` params )
    ^ r
}

// A request declaring a protocol version in `_meta` — the modern era.
@ with_version Json r s version → Json {
    : Json meta ( json_obj_new )
    ( json_obj_set meta `io.modelcontextprotocol/protocolVersion`
    ( json_str_lit version ) )
    ?? ( json_obj_get r `params` ) {
        T p → { ( json_obj_set p `_meta` meta ) }
        F _ → {
            : Json p ( json_obj_new )
            ( json_obj_set p `_meta` meta )
            ( json_obj_set r `params` p )
        }
    }
    ^ r
}

@ call_params s tool Json args → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `name` ( json_str_lit tool ) )
    ( json_obj_set p `arguments` args )
    ^ p
}

// ── the observation ─────────────────────────────────────────────────
//
// Print the envelope this request produces, byte for byte. CONSUMES
// the request.

@ show McpServer srv s tag Json request → v {
    // The tag goes out BEFORE the dispatch so that a server log line —
    // a panicking handler, a notification that failed — lands on its
    // own line above the response it belongs to rather than inside it.
    // On POSIX that is what the record shows: the runner captures
    // `> out 2>&1` and NURL drains stdout before any stderr write, so
    // the merge is program order (compiler/tests/stdout_flush_order.nu
    // pins that rule). run_tests.ps1 reads the two pipes separately and
    // concatenates them, so on Windows every stderr line lands after
    // every stdout line whatever the program does — which is why this
    // test carries an outputs-windows/ golden holding the same lines in
    // that order. Do not "fix" either golden into the other's shape.
    ( nurl_print tag )
    ( nurl_print `\n` )
    : ?Json reply ( mcp_server_envelope srv request )
    ( nurl_print `  ` )
    ?? reply {
        T resp → {
            : String out ( json_stringify resp )
            ( nurl_print ( string_data out ) )
            ( string_free out )
            ( json_free resp )
        }
        F _ → { ( nurl_print `<no response — notification>` ) }
    }
    ( nurl_print `\n` )
    ( json_free request )
}

// ── the server under contract ───────────────────────────────────────

@ t_echo Json args → Json {
    ?? ( json_obj_get args `text` ) {
        T v → { ^ ( mcp_tool_result_text ( json_str_data v ) ) }
        F _ → { ^ ( mcp_tool_result_error `missing required argument: text` ) }
    }
}

@ t_boom Json args → Json {
    ( panic `handler exploded` )
    ^ ( mcp_tool_result_text `unreachable` )
}

@ p_greet Json args → Json {
    : Json msg ( json_obj_new )
    ( json_obj_set msg `role` ( json_str_lit `user` ) )
    : Json content ( json_obj_new )
    ( json_obj_set content `type` ( json_str_lit `text` ) )
    ( json_obj_set content `text` ( json_str_lit `Hello from NURL.` ) )
    ( json_obj_set msg `content` content )
    : Json arr ( json_arr_new )
    ( json_arr_push arr msg )
    : Json out ( json_obj_new )
    ( json_obj_set out `messages` arr )
    ^ out
}

@ r_hello → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `text` ( json_str_lit `hello from a resource` ) )
    ^ out
}

@ c_paths Json argument → Json {
    : Json arr ( json_arr_new )
    ( json_arr_push arr ( json_str_lit `src/` ) )
    ( json_arr_push arr ( json_str_lit `stdlib/` ) )
    ^ arr
}

@ build → McpServer {
    : McpServer srv ( mcp_server_new `contract` `1.0.0` )
    ( mcp_server_set_instructions srv `Echo first; it is the cheap one.` )
    ( mcp_server_add_tool_full srv `echo` `Echo the supplied text back.`
    ( mcp_schema_of1 `text` `string` `Text to echo` T )
    T F T F \ Json a → Json { ^ ( t_echo a ) } )
    ( mcp_server_add_tool srv `boom` `Panics on purpose.` ( mcp_schema_empty )
    \ Json a → Json { ^ ( t_boom a ) } )
    // Registered with a SCHEMA, which is what everyone reaches for —
    // prompts/list must still advertise the spec's array of
    // {name, description, required}.
    : Json greet_args ( mcp_schema_obj )
    ( mcp_schema_prop greet_args `name` `string` `Who to greet` T )
    ( mcp_schema_prop greet_args `formal` `boolean` `Use a formal register` F )
    ( mcp_server_add_prompt srv `greet` `A friendly greeting.`
    greet_args \ Json a → Json { ^ ( p_greet a ) } )
    ( mcp_server_add_resource srv `mcp://hello` `hello` `text/plain`
    `A greeting.` \ → Json { ^ ( r_hello ) } )
    ( mcp_server_add_completion srv `ref/prompt` `greet`
    \ Json a → Json { ^ ( c_paths a ) } )
    ^ srv
}

@ main → i {
    : McpServer srv ( build )

    ( nurl_print `=== handshake ===\n` )
    ( show srv `initialize (legacy)` ( req_id 1 `initialize` ) )
    ( show srv `server/discover` ( req_id 2 `server/discover` ) )
    ( show srv `initialize (modern _meta)`
    ( with_version ( req_id 3 `initialize` ) `2026-07-28` ) )
    ( show srv `unsupported version`
    ( with_version ( req_id 4 `initialize` ) `1999-01-01` ) )
    ( show srv `ping` ( req_id 5 `ping` ) )

    ( nurl_print `=== tools ===\n` )
    ( show srv `tools/list` ( req_id 6 `tools/list` ) )
    : Json a1 ( json_obj_new )
    ( json_obj_set a1 `text` ( json_str_lit `hello` ) )
    ( show srv `tools/call echo`
    ( with_params ( req_id 7 `tools/call` ) ( call_params `echo` a1 ) ) )
    ( show srv `tools/call echo (missing arg)`
    ( with_params ( req_id 8 `tools/call` ) ( call_params `echo` ( json_obj_new ) ) ) )
    ( show srv `tools/call unknown`
    ( with_params ( req_id 9 `tools/call` ) ( call_params `nope` ( json_obj_new ) ) ) )
    // A handler that panics must produce ONE error envelope. Over
    // stdio there is no outer recover, so without the per-handler
    // guard this line would end the process.
    ( show srv `tools/call panicking handler`
    ( with_params ( req_id 10 `tools/call` ) ( call_params `boom` ( json_obj_new ) ) ) )
    ( show srv `tools/call no name`
    ( with_params ( req_id 11 `tools/call` ) ( json_obj_new ) ) )

    ( nurl_print `=== prompts ===\n` )
    ( show srv `prompts/list` ( req_id 12 `prompts/list` ) )
    : Json gp ( json_obj_new )
    ( json_obj_set gp `name` ( json_str_lit `greet` ) )
    ( show srv `prompts/get` ( with_params ( req_id 13 `prompts/get` ) gp ) )
    ( show srv `prompts/get no name`
    ( with_params ( req_id 14 `prompts/get` ) ( json_obj_new ) ) )
    : Json gp2 ( json_obj_new )
    ( json_obj_set gp2 `name` ( json_str_lit `absent` ) )
    ( show srv `prompts/get unknown` ( with_params ( req_id 15 `prompts/get` ) gp2 ) )

    ( nurl_print `=== resources ===\n` )
    ( show srv `resources/list` ( req_id 16 `resources/list` ) )
    : Json rp ( json_obj_new )
    ( json_obj_set rp `uri` ( json_str_lit `mcp://hello` ) )
    ( show srv `resources/read` ( with_params ( req_id 17 `resources/read` ) rp ) )
    ( show srv `resources/read no uri`
    ( with_params ( req_id 18 `resources/read` ) ( json_obj_new ) ) )
    : Json rp2 ( json_obj_new )
    ( json_obj_set rp2 `uri` ( json_str_lit `mcp://absent` ) )
    ( show srv `resources/read unknown`
    ( with_params ( req_id 19 `resources/read` ) rp2 ) )

    ( nurl_print `=== completion ===\n` )
    : Json ref ( json_obj_new )
    ( json_obj_set ref `type` ( json_str_lit `ref/prompt` ) )
    ( json_obj_set ref `name` ( json_str_lit `greet` ) )
    : Json arg ( json_obj_new )
    ( json_obj_set arg `name` ( json_str_lit `path` ) )
    ( json_obj_set arg `value` ( json_str_lit `s` ) )
    : Json cp ( json_obj_new )
    ( json_obj_set cp `ref` ref )
    ( json_obj_set cp `argument` arg )
    ( show srv `completion/complete`
    ( with_params ( req_id 20 `completion/complete` ) cp ) )

    ( nurl_print `=== tasks extension ===\n` )
    // A store makes tasks/* exist and declares the extension. The
    // capability gate's -32003 must reach the client WITH its `data`:
    // the code says what went wrong, `requiredCapabilities` says what
    // to do about it, and an error carrier that models only code and
    // message drops exactly the actionable half.
    : McpServer tsrv ( mcp_server_new `contract-tasks` `1.0.0` )
    : McpTaskStore store ( mcp_task_store_new )
    ( mcp_server_set_task_store tsrv store \ → v {} )
    ( show tsrv `server/discover (tasks declared)` ( req_id 30 `server/discover` ) )
    : Json tp ( json_obj_new )
    ( json_obj_set tp `taskId` ( json_str_lit `0123456789abcdef0123456789abcdef` ) )
    ( show tsrv `tasks/get without the capability`
    ( with_params ( req_id 31 `tasks/get` ) tp ) )
    ( mcp_task_store_free store )
    ( mcp_server_free tsrv )

    ( nurl_print `=== errors and notifications ===\n` )
    ( show srv `unknown method` ( req_id 21 `nope/nope` ) )
    // No `id` — a notification. JSON-RPC 2.0 §4.1: no response, ever,
    // not even to report that it failed.
    ( show srv `notification` ( req `notifications/initialized` ) )
    ( show srv `notification of an unknown method` ( req `nope/nope` ) )

    ( mcp_server_free srv )
    ^ 0
}
