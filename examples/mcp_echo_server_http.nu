// mcp_echo_server_http.nu — the same MCP server over Streamable HTTP.
//
// Identical to examples/mcp_echo_server.nu down to the last
// registration; only the last call differs. That is the point: the
// transport is a choice made in one line, not a second implementation
// of the protocol. See that file for what each registration does.
//
// Run by hand:
//
//     ./build.sh   # or .\build.bat on Windows
//     ./nurl.sh examples/mcp_echo_server_http.nu &
//
// Then probe via curl:
//
//     curl -s -X POST http://127.0.0.1:18770/mcp \
//          -H 'Content-Type: application/json' \
//          --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
//     curl -s -X POST http://127.0.0.1:18770/mcp \
//          -H 'Content-Type: application/json' \
//          --data '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
//     curl -s -X POST http://127.0.0.1:18770/mcp \
//          -H 'Content-Type: application/json' \
//          --data '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hello"}}}'
//
// Bind to 0.0.0.0 instead of 127.0.0.1 to expose on the LAN, and pass a
// non-empty token to require `Authorization: Bearer <token>` (compared
// in constant time). For TLS, put NURL behind nginx/caddy or build the
// listener yourself with `tcp_listen_tls` from ext/http_server.nu and
// hand `mcp_server_http_dispatch`'s closure to `mcp_http_handler` —
// which is all `mcp_server_serve_http` does.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_server.nu`
$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`

@ echo_tool Json args → Json {
    : ?Json text_j ( json_obj_get args `text` )
    ?? text_j {
        T tv → { ^ ( mcp_tool_result_text ( json_str_data tv ) ) }
        F _ → { ^ ( mcp_tool_result_error `missing required argument: text` ) }
    }
}

@ main → i {
    : McpServer srv ( mcp_server_new `nurl-echo` `1.0.0` )
    ( mcp_server_set_instructions srv
    `One tool, echo, which returns the text you give it. Useful as a
connectivity check before trying anything that costs something.` )
    ( mcp_server_add_tool_full srv `echo`
    `Echo the supplied text back to the caller.`
    ( mcp_schema_of1 `text` `string` `Text to echo` T )
    T F T F
    \ Json a → Json { ^ ( echo_tool a ) } )

    ( mcp_log `nurl-echo-mcp-http 0.2.0 listening on 127.0.0.1:18770/mcp` )
    : ~ i rc 0
    // The empty token serves unauthenticated; pass one to require a
    // bearer header on every request.
    ?? ( mcp_server_serve_http srv `127.0.0.1` 18770 `` ) {
        T _ → {}
        F e → {
            ( mcp_log ( nurl_str_cat `server error: ` ( net_err_name e ) ) )
            = rc 1
        }
    }
    ( mcp_server_free srv )
    ^ rc
}
