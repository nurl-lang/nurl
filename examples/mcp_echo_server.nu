// mcp_echo_server.nu — a complete MCP server in NURL, over stdio.
//
// Register the tools, pick a transport, done. Everything below the
// registration — JSON-RPC framing, the dual-era version gate,
// `server/discover`, `_meta` decorations, per-handler panic isolation —
// is `stdlib/ext/mcp_server.nu`'s job, and you should never write it
// again. (Three servers in this repo did, from an earlier version of
// this very example, and their copies drifted apart.)
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
//
// Serving the same tools over HTTP instead is one line — see
// examples/mcp_echo_server_http.nu.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_server.nu`
$ `stdlib/core/string.nu`

// ── The tool ────────────────────────────────────────────────────────
//
// A handler takes the call's `arguments` object and returns a
// tool-result envelope. It may fail however it likes: a panic in here
// becomes an error envelope for this one call, not a dead server.

@ echo_tool Json args → Json {
    : ?Json text_j ( json_obj_get args `text` )
    ?? text_j {
        T tv → { ^ ( mcp_tool_result_text ( json_str_data tv ) ) }
        F _ → { ^ ( mcp_tool_result_error `missing required argument: text` ) }
    }
}

@ main → i {
    : McpServer srv ( mcp_server_new `nurl-echo` `1.0.0` )

    // Instructions ride `server/discover` and the initialize result:
    // how a model should approach this server. Optional, and the first
    // thing a real server should write.
    ( mcp_server_set_instructions srv
    `One tool, echo, which returns the text you give it. Useful as a
connectivity check before trying anything that costs something.` )

    // `_full` carries the ToolAnnotations. They matter: an ABSENT
    // destructiveHint defaults to TRUE in the spec, so a tool listed
    // without them is shown to the user as if it could destroy state,
    // and clients that auto-allow read-only tools will not.
    //             read-only  destructive  idempotent  open-world
    ( mcp_server_add_tool_full srv `echo`
    `Echo the supplied text back to the caller.`
    ( mcp_schema_of1 `text` `string` `Text to echo` T )
    T F T F
    \ Json a → Json { ^ ( echo_tool a ) } )

    // Blocks until stdin closes. Handlers must outlive this call —
    // the wrapper above captures nothing, so it lives as long as the
    // program.
    ?? ( mcp_server_serve_stdio srv ) {
        T _ → {}
        F e → { ( mcp_log ( mcp_server_err_name e ) ) }
    }
    ( mcp_server_free srv )
    ^ 0
}
