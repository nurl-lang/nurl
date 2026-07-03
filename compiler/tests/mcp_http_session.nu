// Regression: stdlib/ext/mcp_http.nu session-aware handler
// (mcp_http_handler_session). Builds synthetic HttpRequests in-memory
// and drives them through the handler — no socket — checking: session
// issuance on initialize, echo + validation of Mcp-Session-Id, 404 on
// an unknown id, GET draining the outbound queue as SSE events, the
// reverse-RPC response settling path, and DELETE teardown. Returns the
// failure count.

$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/mcp_session.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Build a synthetic request; sid == "" omits the session header.
@ make_req s method s body s sid → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path `/mcp` )
    ? > ( nurl_str_len sid ) 0 {
        ( vec_push [Header] . req headers ( header_new `Mcp-Session-Id` sid ) )
    } {}
    ? > ( nurl_str_len body ) 0 { ( bytes_extend_str . req body body ) } {}
    ^ req
}

@ resp_body_str HttpResponse r → String {
    ^ ( bytes_to_str . r body )
}

// Minimal dispatcher: initialize → result envelope; ping → {ok:true};
// anything with no id → notification (None).
@ test_dispatch Json req → ?Json {
    : ?Json ido ( json_obj_get req `id` )
    : b has_id ?? ido { T _ → T F → F }
    ? ! has_id { ^ @ ?Json { F # Json 0 } } {}
    : ?Json mo ( json_obj_get req `method` )
    : s method ?? mo { T mj → ( json_str_data mj ) F → `` }
    : ?Json idc ( json_obj_get req `id` )
    : Json id ?? idc { T j → ( json_clone j ) F → ( json_null ) }
    ? == 1 ( nurl_str_eq method `initialize` ) {
        : Json res ( mcp_initialize_result `test` `0.1` )
        // Advertise a resources capability so the SESSION transport's
        // `subscribe: true` upgrade is observable in the reply.
        : ?Json co ( json_obj_get res `capabilities` )
        ?? co {
            T caps → ( json_obj_set caps `resources` ( json_obj_new ) )
            F _ → {}
        }
        : Json out ( mcp_response_result id res )
        ( json_free id )
        ^ @ ?Json { T out }
    } {}
    : Json res ( json_obj_new )
    ( json_obj_set res `ok` ( json_bool T ) )
    : Json out ( mcp_response_result id res )
    ( json_free id )
    ^ @ ?Json { T out }
}

@ main → i {
    : ~ i fails 0
    : McpSessionStore store ( mcp_session_store_new )
    : ( @ HttpResponse HttpRequest ) handler ( mcp_http_handler_session store \ Json req → ?Json { ^ ( test_dispatch req ) } )

    // 1. initialize → 200, and a Mcp-Session-Id is minted.
    : HttpRequest r1 ( make_req `POST` `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}` `` )
    : HttpResponse resp1 ( handler r1 )
    ? != . resp1 status 200 { ( nurl_print `  FAIL init status\n` ) = fails + fails 1 } {}
    : String sid ( string_new )
    : ?String sido ( header_get . resp1 headers `Mcp-Session-Id` )
    ?? sido { T s → { ( string_push_str sid ( string_data s ) ) ( string_free s ) } F _ → {} }
    ? != ( string_len sid ) 32 { ( nurl_print `  FAIL no session id minted\n` ) = fails + fails 1 } {}
    ? != ( mcp_session_count store ) 1 { ( nurl_print `  FAIL store count\n` ) = fails + fails 1 } {}
    // The session transport upgrades the resources capability with
    // `"subscribe": true` (SSE stream = the delivery channel).
    : String ib ( resp_body_str resp1 )
    ? < ( nurl_str_find ( string_data ib ) `"subscribe":true` ) 0 { ( nurl_print `  FAIL init subscribe cap\n` ) = fails + fails 1 } {}
    ( string_free ib )
    ( request_free r1 )
    ( http_response_free resp1 )

    // 2. follow-up with the valid session id → 200, echoed back.
    : HttpRequest r2 ( make_req `POST` `{"jsonrpc":"2.0","id":2,"method":"ping"}` ( string_data sid ) )
    : HttpResponse resp2 ( handler r2 )
    ? != . resp2 status 200 { ( nurl_print `  FAIL ping status\n` ) = fails + fails 1 } {}
    : ?String echo ( header_get . resp2 headers `Mcp-Session-Id` )
    ?? echo { T s → { ? != 1 ( nurl_str_eq ( string_data s ) ( string_data sid ) ) { ( nurl_print `  FAIL echo mismatch\n` ) = fails + fails 1 } {} ( string_free s ) } F _ → { ( nurl_print `  FAIL no echo\n` ) = fails + fails 1 } }
    ( request_free r2 )
    ( http_response_free resp2 )

    // 3. unknown session id → 404.
    : HttpRequest r3 ( make_req `POST` `{"jsonrpc":"2.0","id":3,"method":"ping"}` `deadbeefdeadbeefdeadbeefdeadbeef` )
    : HttpResponse resp3 ( handler r3 )
    ? != . resp3 status 404 { ( nurl_print `  FAIL unknown-session status\n` ) = fails + fails 1 } {}
    ( request_free r3 )
    ( http_response_free resp3 )

    // 4. queue a server→client message, then GET drains it as SSE.
    ( mcp_session_push_notify store ( string_data sid ) ( mcp_notification `notifications/message` ( json_str_lit `ping-from-server` ) ) )
    : HttpRequest r4 ( make_req `GET` `` ( string_data sid ) )
    : HttpResponse resp4 ( handler r4 )
    ? != . resp4 status 200 { ( nurl_print `  FAIL get status\n` ) = fails + fails 1 } {}
    : String sse ( resp_body_str resp4 )
    ? ! ( string_starts_with sse `id: 1\r\nevent: message\r\ndata: ` ) { ( nurl_print `  FAIL sse not drained\n` ) = fails + fails 1 } {}
    ? < ( nurl_str_find ( string_data sse ) `ping-from-server` ) 0 { ( nurl_print `  FAIL sse payload\n` ) = fails + fails 1 } {}
    ( string_free sse )
    ( request_free r4 )
    ( http_response_free resp4 )
    // Queue is now empty: a second GET yields the ready stub.
    : HttpRequest r4b ( make_req `GET` `` ( string_data sid ) )
    : HttpResponse resp4b ( handler r4b )
    : String sse2 ( resp_body_str resp4b )
    ? < ( nurl_str_find ( string_data sse2 ) `event: message` ) 0 {} { ( nurl_print `  FAIL queue not cleared\n` ) = fails + fails 1 }
    ( string_free sse2 )
    ( request_free r4b )
    ( http_response_free resp4b )
    // 4c. reconnect with Last-Event-ID: 0 → event 1 replayed from the
    // backlog even though the queue is empty.
    : HttpRequest r4c ( make_req `GET` `` ( string_data sid ) )
    ( vec_push [Header] . r4c headers ( header_new `Last-Event-ID` `0` ) )
    : HttpResponse resp4c ( handler r4c )
    : String sse3 ( resp_body_str resp4c )
    ? < ( nurl_str_find ( string_data sse3 ) `id: 1\r\nevent: message` ) 0 { ( nurl_print `  FAIL replay missing\n` ) = fails + fails 1 } {}
    ? < ( nurl_str_find ( string_data sse3 ) `ping-from-server` ) 0 { ( nurl_print `  FAIL replay payload\n` ) = fails + fails 1 } {}
    ( string_free sse3 )
    ( request_free r4c )
    ( http_response_free resp4c )
    // 4d. Last-Event-ID current (lowercase header — case-insensitive
    // match) → nothing replayed.
    : HttpRequest r4d ( make_req `GET` `` ( string_data sid ) )
    ( vec_push [Header] . r4d headers ( header_new `last-event-id` `1` ) )
    : HttpResponse resp4d ( handler r4d )
    : String sse4 ( resp_body_str resp4d )
    ? < ( nurl_str_find ( string_data sse4 ) `event: message` ) 0 {} { ( nurl_print `  FAIL replay not idle\n` ) = fails + fails 1 }
    ( string_free sse4 )
    ( request_free r4d )
    ( http_response_free resp4d )

    // 5. reverse-RPC response (no method, has result) → 202 + resolved.
    : i rid ( mcp_session_begin_rpc store ( string_data sid ) `sampling/createMessage` ( json_obj_new ) )
    ? != rid 1 { ( nurl_print `  FAIL begin_rpc id\n` ) = fails + fails 1 } {}
    : HttpRequest r5 ( make_req `POST` `{"jsonrpc":"2.0","id":1,"result":{"role":"assistant"}}` ( string_data sid ) )
    : HttpResponse resp5 ( handler r5 )
    ? != . resp5 status 202 { ( nurl_print `  FAIL rpc-response status\n` ) = fails + fails 1 } {}
    ? ( mcp_session_is_pending store ( string_data sid ) rid ) { ( nurl_print `  FAIL rpc still pending\n` ) = fails + fails 1 } {}
    ?? ( mcp_session_take_result store ( string_data sid ) rid ) { T j → ( json_free j ) F → { ( nurl_print `  FAIL rpc not resolved\n` ) = fails + fails 1 } }
    ( request_free r5 )
    ( http_response_free resp5 )
    // begin_rpc also enqueued an outbound request frame — drain + drop it.
    : ( Vec Json ) leftover ( mcp_session_drain_notify store ( string_data sid ) )
    : ~ i li 0
    ~ < li ( vec_len [Json] leftover ) { ?? ( vec_get [Json] leftover li ) { T j → ( json_free j ) F → {} } = li + li 1 }
    ( vec_free [Json] leftover )

    // 6. batch POST: two requests → ordered JSON array of responses.
    : HttpRequest rb ( make_req `POST` `[{"jsonrpc":"2.0","id":10,"method":"ping"},{"jsonrpc":"2.0","id":11,"method":"ping"}]` ( string_data sid ) )
    : HttpResponse respb ( handler rb )
    ? != . respb status 200 { ( nurl_print `  FAIL batch status\n` ) = fails + fails 1 } {}
    : String bb ( resp_body_str respb )
    : !Json JsonError pb ( json_parse ( string_data bb ) )
    ?? pb {
        T ja → {
            ? ! ( json_is_arr ja ) { ( nurl_print `  FAIL batch not array\n` ) = fails + fails 1 } {}
            ? != ( json_arr_len ja ) 2 { ( nurl_print `  FAIL batch arity\n` ) = fails + fails 1 } {}
            ?? ( json_arr_get ja 0 ) {
                T e0 → { ?? ( json_obj_get e0 `id` ) { T i0 → { ? != ( json_as_int i0 ) 10 { ( nurl_print `  FAIL batch order 0\n` ) = fails + fails 1 } {} } F → { ( nurl_print `  FAIL batch id 0\n` ) = fails + fails 1 } } }
                F → { ( nurl_print `  FAIL batch elem 0\n` ) = fails + fails 1 }
            }
            ?? ( json_arr_get ja 1 ) {
                T e1 → { ?? ( json_obj_get e1 `id` ) { T i1 → { ? != ( json_as_int i1 ) 11 { ( nurl_print `  FAIL batch order 1\n` ) = fails + fails 1 } {} } F → { ( nurl_print `  FAIL batch id 1\n` ) = fails + fails 1 } } }
                F → { ( nurl_print `  FAIL batch elem 1\n` ) = fails + fails 1 }
            }
            ( json_free ja )
        }
        F _ → { ( nurl_print `  FAIL batch body parse\n` ) = fails + fails 1 }
    }
    ( string_free bb )
    ( request_free rb )
    ( http_response_free respb )
    // 6b. batch with an unknown session id → 404 (validated once).
    : HttpRequest rb404 ( make_req `POST` `[{"jsonrpc":"2.0","id":12,"method":"ping"}]` `deadbeefdeadbeefdeadbeefdeadbeef` )
    : HttpResponse respb404 ( handler rb404 )
    ? != . respb404 status 404 { ( nurl_print `  FAIL batch-unknown status\n` ) = fails + fails 1 } {}
    ( request_free rb404 )
    ( http_response_free respb404 )
    // 6c. empty batch → JSON-RPC invalid_request error (HTTP 200).
    : HttpRequest rbe ( make_req `POST` `[]` ( string_data sid ) )
    : HttpResponse respbe ( handler rbe )
    ? != . respbe status 200 { ( nurl_print `  FAIL empty-batch status\n` ) = fails + fails 1 } {}
    : String be ( resp_body_str respbe )
    ? < ( nurl_str_find ( string_data be ) `-32600` ) 0 { ( nurl_print `  FAIL empty-batch code\n` ) = fails + fails 1 } {}
    ( string_free be )
    ( request_free rbe )
    ( http_response_free respbe )
    // 6d. all-notification batch (no ids) → 202 Accepted, no body.
    : HttpRequest rbn ( make_req `POST` `[{"jsonrpc":"2.0","method":"note"},{"jsonrpc":"2.0","method":"note2"}]` ( string_data sid ) )
    : HttpResponse respbn ( handler rbn )
    ? != . respbn status 202 { ( nurl_print `  FAIL notif-batch status\n` ) = fails + fails 1 } {}
    ( request_free rbn )
    ( http_response_free respbn )

    // 6e. resources/subscribe end to end: subscribe over the handler,
    // a server-side update lands on the session's SSE stream, and
    // unsubscribe stops delivery.
    : HttpRequest rs1 ( make_req `POST` `{"jsonrpc":"2.0","id":20,"method":"resources/subscribe","params":{"uri":"file:///w.txt"}}` ( string_data sid ) )
    : HttpResponse resps1 ( handler rs1 )
    ? != . resps1 status 200 { ( nurl_print `  FAIL sub status\n` ) = fails + fails 1 } {}
    : String sb ( resp_body_str resps1 )
    ? < ( nurl_str_find ( string_data sb ) `"result"` ) 0 { ( nurl_print `  FAIL sub ack\n` ) = fails + fails 1 } {}
    ( string_free sb )
    ( request_free rs1 )
    ( http_response_free resps1 )
    ? ! ( mcp_session_is_subscribed store ( string_data sid ) `file:///w.txt` ) { ( nurl_print `  FAIL sub recorded\n` ) = fails + fails 1 } {}
    ? != ( mcp_session_notify_resource_updated store `file:///w.txt` ) 1 { ( nurl_print `  FAIL http notify count\n` ) = fails + fails 1 } {}
    : HttpRequest rs2 ( make_req `GET` `` ( string_data sid ) )
    : HttpResponse resps2 ( handler rs2 )
    : String ub ( resp_body_str resps2 )
    ? < ( nurl_str_find ( string_data ub ) `notifications/resources/updated` ) 0 { ( nurl_print `  FAIL updated missing\n` ) = fails + fails 1 } {}
    ? < ( nurl_str_find ( string_data ub ) `file:///w.txt` ) 0 { ( nurl_print `  FAIL updated uri\n` ) = fails + fails 1 } {}
    ( string_free ub )
    ( request_free rs2 )
    ( http_response_free resps2 )
    : HttpRequest rs3 ( make_req `POST` `{"jsonrpc":"2.0","id":21,"method":"resources/unsubscribe","params":{"uri":"file:///w.txt"}}` ( string_data sid ) )
    : HttpResponse resps3 ( handler rs3 )
    ? != . resps3 status 200 { ( nurl_print `  FAIL unsub status\n` ) = fails + fails 1 } {}
    ( request_free rs3 )
    ( http_response_free resps3 )
    ? != ( mcp_session_notify_resource_updated store `file:///w.txt` ) 0 { ( nurl_print `  FAIL notify after unsub\n` ) = fails + fails 1 } {}

    // 7. DELETE tears the session down.
    : HttpRequest r6 ( make_req `DELETE` `` ( string_data sid ) )
    : HttpResponse resp6 ( handler r6 )
    ? != . resp6 status 204 { ( nurl_print `  FAIL delete status\n` ) = fails + fails 1 } {}
    ? != ( mcp_session_count store ) 0 { ( nurl_print `  FAIL not deleted\n` ) = fails + fails 1 } {}
    ( request_free r6 )
    ( http_response_free resp6 )

    ( string_free sid )
    ( mcp_session_store_free store )

    ? == fails 0 { ( nurl_print `mcp_http_session: all checks PASS\n` ) } {
        ( nurl_print `mcp_http_session: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
