// Regression: stdlib/ext/mcp_session.nu — stateful MCP session store,
// outbound notification queue, and server→client (reverse) RPC
// correlation for sampling/createMessage. Pure in-memory; no sockets.
// Returns the failure count.

$ `stdlib/ext/mcp_session.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ i fails 0

    : McpSessionStore store ( mcp_session_store_new )
    ? != ( mcp_session_count store ) 0 { ( nurl_print `  FAIL count0\n` ) = fails + fails 1 } {}

    : String id ( mcp_session_create store )
    : s sid ( string_data id )
    ? != ( mcp_session_count store ) 1 { ( nurl_print `  FAIL count1\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_valid store sid ) { ( nurl_print `  FAIL valid\n` ) = fails + fails 1 } {}
    ? ( mcp_session_valid store `bogus` ) { ( nurl_print `  FAIL valid-bogus\n` ) = fails + fails 1 } {}
    // 32 hex chars of session id
    ? != ( nurl_str_len sid ) 32 { ( nurl_print `  FAIL id-len\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_touch store sid 12345 ) { ( nurl_print `  FAIL touch\n` ) = fails + fails 1 } {}

    // ── Outbound notification queue ──
    ( mcp_session_push_notify store sid ( mcp_notification `notifications/message` ( json_str_lit `hi` ) ) )
    ( mcp_session_push_notify store sid ( mcp_notification `notifications/message` ( json_str_lit `bye` ) ) )
    : ( Vec Json ) q1 ( mcp_session_drain_notify store sid )
    ? != ( vec_len [Json] q1 ) 2 { ( nurl_print `  FAIL drain2\n` ) = fails + fails 1 } {}
    ( vec_free_with [Json] q1 \ Json j → v { ( json_free j ) } )
    // Drain again → empty (queue cleared).
    : ( Vec Json ) q2 ( mcp_session_drain_notify store sid )
    ? != ( vec_len [Json] q2 ) 0 { ( nurl_print `  FAIL drain-empty\n` ) = fails + fails 1 } {}
    ( vec_free [Json] q2 )

    // ── Reverse RPC: sampling/createMessage ──
    : ( Vec Json ) msgs ( vec_new [Json] )
    ( vec_push [Json] msgs ( mcp_sampling_message `user` `What is 2+2?` ) )
    : i rpc_id ( mcp_session_request_sampling store sid msgs `Be terse.` 64 )
    ? != rpc_id 1 { ( nurl_print `  FAIL rpc-id\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_is_pending store sid rpc_id ) { ( nurl_print `  FAIL pending\n` ) = fails + fails 1 } {}

    // The request must be queued for the client; inspect method + id.
    : ( Vec Json ) outq ( mcp_session_drain_notify store sid )
    ? != ( vec_len [Json] outq ) 1 { ( nurl_print `  FAIL rpc-queued\n` ) = fails + fails 1 } {}
    : ?Json reqo ( vec_get [Json] outq 0 )
    ?? reqo {
        T req → {
            : ?Json mo ( json_obj_get req `method` )
            ?? mo { T mj → { ? != 1 ( nurl_str_eq ( json_str_data mj ) `sampling/createMessage` ) { ( nurl_print `  FAIL rpc-method\n` ) = fails + fails 1 } {} } F → { ( nurl_print `  FAIL no-method\n` ) = fails + fails 1 } }
            : ?Json io ( json_obj_get req `id` )
            ?? io { T ij → { ? != ( json_as_int ij ) 1 { ( nurl_print `  FAIL rpc-reqid\n` ) = fails + fails 1 } {} } F → {} }
        }
        F → {}
    }
    ( vec_free_with [Json] outq \ Json j → v { ( json_free j ) } )

    // Take before resolve → None.
    ?? ( mcp_session_take_result store sid rpc_id ) { T j → { ( nurl_print `  FAIL early-result\n` ) ( json_free j ) = fails + fails 1 } F → {} }

    // Client posts back the response → resolve.
    : Json result ( json_obj_new )
    ( json_obj_set result `role` ( json_str_lit `assistant` ) )
    ( json_obj_set result `content` ( mcp_text_content `4` ) )
    : Json id_node ( json_int rpc_id )
    : Json response ( mcp_response_result id_node result )
    ( json_free id_node )
    ? ! ( mcp_session_resolve_rpc store sid response ) { ( nurl_print `  FAIL resolve\n` ) = fails + fails 1 } {}
    // Pending marker cleared.
    ? ( mcp_session_is_pending store sid rpc_id ) { ( nurl_print `  FAIL still-pending\n` ) = fails + fails 1 } {}

    // Caller collects the result.
    ?? ( mcp_session_take_result store sid rpc_id ) {
        T j → {
            : ?Json ro ( json_obj_get j `result` )
            ? ?? ro { T _ → F F → T } { ( nurl_print `  FAIL result-shape\n` ) = fails + fails 1 } {}
            ( json_free j )
        }
        F → { ( nurl_print `  FAIL no-result\n` ) = fails + fails 1 }
    }
    // Taken once → gone.
    ?? ( mcp_session_take_result store sid rpc_id ) { T j → { ( nurl_print `  FAIL double-take\n` ) ( json_free j ) = fails + fails 1 } F → {} }

    // ── SSE frame format ──
    : Json sse_data ( json_str_lit `ok` )
    : String frame ( mcp_sse_frame `message` sse_data )
    ( json_free sse_data )   // mcp_sse_frame borrows its data
    ? ! ( string_starts_with frame `event: message\r\ndata: ` ) { ( nurl_print `  FAIL sse-prefix\n` ) = fails + fails 1 } {}
    ? ! ( string_ends_with frame `\r\n\r\n` ) { ( nurl_print `  FAIL sse-suffix\n` ) = fails + fails 1 } {}
    ( string_free frame )

    // ── Delete ──
    ? ! ( mcp_session_delete store sid ) { ( nurl_print `  FAIL delete\n` ) = fails + fails 1 } {}
    ? != ( mcp_session_count store ) 0 { ( nurl_print `  FAIL count-after-delete\n` ) = fails + fails 1 } {}
    ? ( mcp_session_valid store sid ) { ( nurl_print `  FAIL valid-after-delete\n` ) = fails + fails 1 } {}

    ( string_free id )
    ( mcp_session_store_free store )

    ? == fails 0 { ( nurl_print `mcp_session: all checks PASS\n` ) } {
        ( nurl_print `mcp_session: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
