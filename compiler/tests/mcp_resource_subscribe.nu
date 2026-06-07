// mcp_resource_subscribe.nu — regression for MCP resources/subscribe
// (spec §6.5): per-session resource subscriptions + the
// notifications/resources/updated fan-out. Pure in-memory; no sockets.
// Returns the failure count.

$ `stdlib/ext/mcp_session.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ notif_method Json j → s {
    : ?Json m ( json_obj_get j `method` )
    ^ ?? m { T x → ( json_as_str x ) F → `` }
}

@ notif_uri Json j → s {
    : ?Json p ( json_obj_get j `params` )
    ^ ?? p {
        T pj → {
            : ?Json u ( json_obj_get pj `uri` )
            ^ ?? u { T x → ( json_as_str x ) F → `` }
        }
        F → ``
    }
}

// Count the messages in a drained queue that target `uri`, freeing the
// queue (and its Json elements) as it goes.
@ drain_count_uri ( Vec Json ) q s uri → i {
    : i n ( vec_len [Json] q )
    : ~ i k 0
    : ~ i hits 0
    ~ < k n {
        : ?Json e ( vec_get [Json] q k )
        ?? e {
            T j → {
                ? & != 0 ( nurl_str_eq ( notif_method j ) `notifications/resources/updated` )
                != 0 ( nurl_str_eq ( notif_uri j ) uri )
                { = hits + hits 1 } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [Json] q \ Json j → v { ( json_free j ) } )
    ^ hits
}

@ main → i {
    : ~ i fails 0

    : McpSessionStore store ( mcp_session_store_new )
    : String id1 ( mcp_session_create store )
    : String id2 ( mcp_session_create store )
    : s s1 ( string_data id1 )
    : s s2 ( string_data id2 )

    : s uriA `file:///a.txt`
    : s uriB `file:///b.txt`

    // ── subscribe ──
    ? ! ( mcp_session_subscribe store s1 uriA ) { ( nurl_print `  FAIL sub s1 A\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_subscribe store s1 uriB ) { ( nurl_print `  FAIL sub s1 B\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_subscribe store s2 uriA ) { ( nurl_print `  FAIL sub s2 A\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_subscribe store `bogus` uriA ) {} { ( nurl_print `  FAIL sub bogus should be F\n` ) = fails + fails 1 }

    // ── is_subscribed ──
    ? ! ( mcp_session_is_subscribed store s1 uriA ) { ( nurl_print `  FAIL is_sub s1 A\n` ) = fails + fails 1 } {}
    ? ( mcp_session_is_subscribed store s2 uriB ) { ( nurl_print `  FAIL s2 not sub B\n` ) = fails + fails 1 } {}

    // ── notify uriA → both sessions; uriB → only s1 ──
    ? != ( mcp_session_notify_resource_updated store uriA ) 2 { ( nurl_print `  FAIL notifyA count\n` ) = fails + fails 1 } {}
    ? != ( mcp_session_notify_resource_updated store uriB ) 1 { ( nurl_print `  FAIL notifyB count\n` ) = fails + fails 1 } {}

    // s1 queue: one A + one B. s2 queue: one A.
    : ( Vec Json ) q1 ( mcp_session_drain_notify store s1 )
    : i q1n ( vec_len [Json] q1 )
    ? != q1n 2 { ( nurl_print `  FAIL s1 queue len\n` ) = fails + fails 1 } {}
    ? != ( drain_count_uri q1 uriA ) 1 { ( nurl_print `  FAIL s1 got A\n` ) = fails + fails 1 } {}

    : ( Vec Json ) q2 ( mcp_session_drain_notify store s2 )
    ? != ( vec_len [Json] q2 ) 1 { ( nurl_print `  FAIL s2 queue len\n` ) = fails + fails 1 } {}
    ? != ( drain_count_uri q2 uriA ) 1 { ( nurl_print `  FAIL s2 got A\n` ) = fails + fails 1 } {}

    // ── unsubscribe s1 from A ──
    ? ! ( mcp_session_unsubscribe store s1 uriA ) { ( nurl_print `  FAIL unsub s1 A\n` ) = fails + fails 1 } {}
    ? ( mcp_session_unsubscribe store s1 uriA ) { ( nurl_print `  FAIL unsub twice should be F\n` ) = fails + fails 1 } {}
    ? ( mcp_session_is_subscribed store s1 uriA ) { ( nurl_print `  FAIL s1 still sub A\n` ) = fails + fails 1 } {}
    ? ! ( mcp_session_is_subscribed store s1 uriB ) { ( nurl_print `  FAIL s1 lost B\n` ) = fails + fails 1 } {}

    // Now only s2 is subscribed to A.
    ? != ( mcp_session_notify_resource_updated store uriA ) 1 { ( nurl_print `  FAIL notifyA after unsub\n` ) = fails + fails 1 } {}
    : ( Vec Json ) q3 ( mcp_session_drain_notify store s2 )
    ? != ( drain_count_uri q3 uriA ) 1 { ( nurl_print `  FAIL s2 got A again\n` ) = fails + fails 1 } {}

    // ── idempotent subscribe: double-subscribe then single unsubscribe
    //    must fully remove it (proves no duplicate entry). ──
    ( mcp_session_subscribe store s2 uriA )
    ( mcp_session_subscribe store s2 uriA )
    ( mcp_session_unsubscribe store s2 uriA )
    ? ( mcp_session_is_subscribed store s2 uriA ) { ( nurl_print `  FAIL idempotent sub\n` ) = fails + fails 1 } {}

    ( string_free id1 )
    ( string_free id2 )
    ( mcp_session_store_free store )

    ? == fails 0 { ( nurl_print `all ok\n` ) } {}
    ^ fails
}
