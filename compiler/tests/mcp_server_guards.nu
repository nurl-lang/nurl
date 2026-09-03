// mcp_server_guards.nu — registration-time guards on McpServer.
//
// Both guards protect against a failure that is silent otherwise:
//
//   * a DUPLICATE name shadows. `tools/list` advertises two entries,
//     `tools/call` only ever reaches the first, and the tool that does
//     nothing is the one the author just wrote.
//   * a LATE registration (after the first dispatch) can realloc a Vec
//     that an in-flight dispatch holds a `vec_data` pointer into — a
//     use-after-free that surfaces as corruption under load, nowhere
//     near its cause.
//
// Both are bugs in the server, not in any request, so both abort at the
// `add` with a message naming the offending registration. `recover`
// lets one test observe all of them.

$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_server.nu`

@ noop_tool Json args → Json { ^ ( mcp_tool_result_text `ok` ) }

@ empty_schema → Json {
    : Json sc ( json_obj_new )
    ( json_obj_set sc `type` ( json_str_lit `object` ) )
    ^ sc
}

// Run `body`, print whether it panicked and with what message.
@ expect_panic s tag ( @ v ) body → v {
    ?? ( recover body ) {
        T _ → {
            ( nurl_print tag )
            ( nurl_print `=NO PANIC (guard missing)\n` )
        }
        F p → {
            ( nurl_print tag )
            ( nurl_print `=` )
            ( nurl_print ( string_data . p msg ) )
            ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }
}

@ main → i {
    : McpServer srv ( mcp_server_new `guards` `1.0.0` )
    ( mcp_server_add_tool srv `echo` `Echo.` ( empty_schema )
    \ Json a → Json { ^ ( noop_tool a ) } )
    ( mcp_server_add_prompt srv `greet` `Greet.` ( empty_schema )
    \ Json a → Json { ^ ( noop_tool a ) } )
    ( mcp_server_add_resource srv `mcp://a` `A` `text/plain` `A.`
    \ → Json { ^ ( json_obj_new ) } )

    ( nurl_print `--- accessors ---\n` )
    ( nurl_print `name=` ) ( nurl_print ( mcp_server_name srv ) ) ( nurl_print `\n` )
    ( nurl_print `version=` ) ( nurl_print ( mcp_server_version srv ) ) ( nurl_print `\n` )
    ( nurl_print `tools=` ) ( nurl_print_int ( mcp_server_tool_count srv ) ) ( nurl_print `\n` )
    ( nurl_print `has_echo=` )
    ( nurl_print ? ( mcp_server_has_tool srv `echo` ) `T` `F` ) ( nurl_print `\n` )
    ( nurl_print `has_ghost=` )
    ( nurl_print ? ( mcp_server_has_tool srv `ghost` ) `T` `F` ) ( nurl_print `\n` )
    ( nurl_print `serving=` )
    ( nurl_print ? ( mcp_server_is_serving srv ) `T` `F` ) ( nurl_print `\n` )

    ( nurl_print `--- duplicate names ---\n` )
    ( expect_panic `dup_tool` \ → v {
        ( mcp_server_add_tool srv `echo` `Shadow.` ( empty_schema )
        \ Json a → Json { ^ ( noop_tool a ) } )
    } )
    ( expect_panic `dup_prompt` \ → v {
        ( mcp_server_add_prompt srv `greet` `Shadow.` ( empty_schema )
        \ Json a → Json { ^ ( noop_tool a ) } )
    } )
    ( expect_panic `dup_resource` \ → v {
        ( mcp_server_add_resource srv `mcp://a` `A2` `text/plain` `Shadow.`
        \ → Json { ^ ( json_obj_new ) } )
    } )

    // A distinct name still registers — the guard rejects collisions,
    // not registration.
    ( mcp_server_add_tool srv `echo2` `Echo.` ( empty_schema )
    \ Json a → Json { ^ ( noop_tool a ) } )
    ( nurl_print `tools_after=` )
    ( nurl_print_int ( mcp_server_tool_count srv ) ) ( nurl_print `\n` )

    ( nurl_print `--- registration after serving ---\n` )
    : Json ping_req ( json_obj_new )
    ( json_obj_set ping_req `method` ( json_str_lit `ping` ) )
    ?? ( mcp_server_dispatch srv ping_req ) {
        T res → { ( json_free res ) }
        F e → { ( mcp_rpc_err_free e ) }
    }
    ( json_free ping_req )
    ( nurl_print `serving_after_dispatch=` )
    ( nurl_print ? ( mcp_server_is_serving srv ) `T` `F` ) ( nurl_print `\n` )
    ( expect_panic `late_tool` \ → v {
        ( mcp_server_add_tool srv `late` `Too late.` ( empty_schema )
        \ Json a → Json { ^ ( noop_tool a ) } )
    } )

    ( mcp_server_free srv )
    ^ 0
}
