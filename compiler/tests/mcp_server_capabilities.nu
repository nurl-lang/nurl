// mcp_server_capabilities.nu — the four things every hand-rolled MCP
// server in this tree had and ext/mcp_server.nu did not, which is a
// large part of why they were hand-rolled:
//
//   * ToolAnnotations. An ABSENT destructiveHint defaults to TRUE in
//     the spec, so a read-only tool listed without them is presented to
//     the user as if it could destroy state.
//   * `instructions` — how a model should approach this server, which
//     tool to reach for first. Both nurl-mcp and swarm-mcp wrote a
//     paragraph of it; the facade had no channel for one.
//   * the io.modelcontextprotocol/tasks extension, declared only when
//     a store is actually attached.
//   * the per-call context: what the CLIENT declared on this request,
//     reaching the tool handler without widening the frozen handler
//     type.

$ `stdlib/ext/mcp_server.nu`
$ `stdlib/ext/mcp_tasks.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ label s tag s v → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ label_b s tag b v → v { ( label tag ? v `T` `F` ) }

@ jstr Json o s key → s {
    ^ ?? ( json_obj_get o key ) { T j → ( json_as_str j ) F → `<absent>` }
}

@ jhas Json o s key → b {
    ^ ?? ( json_obj_get o key ) { T _ → T F → F }
}

// A request, optionally declaring the tasks extension in `_meta`.
@ req_of s method b with_tasks → Json {
    : Json req ( json_obj_new )
    ( json_obj_set req `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set req `method` ( json_str_lit method ) )
    : Json params ( json_obj_new )
    ? with_tasks {
        : Json ext ( json_obj_new )
        ( json_obj_set ext ( mcp_tasks_ext_id ) ( json_obj_new ) )
        : Json caps ( json_obj_new )
        ( json_obj_set caps `extensions` ext )
        : Json meta ( json_obj_new )
        ( json_obj_set meta `io.modelcontextprotocol/clientCapabilities` caps )
        ( json_obj_set params `_meta` meta )
    } {}
    ( json_obj_set req `params` params )
    ^ req
}

@ tools_call_req s tool b with_tasks → Json {
    : Json req ( req_of `tools/call` with_tasks )
    ?? ( json_obj_get req `params` ) {
        T p → { ( json_obj_set p `name` ( json_str_lit tool ) ) }
        F _ → {}
    }
    ^ req
}

@ dispatch McpServer srv Json req → Json {
    ?? ( mcp_server_dispatch srv req ) {
        T res → { ^ res }
        F e → {
            ( label `UNEXPECTED_ERR` ( mcp_rpc_err_message e ) )
            ( mcp_rpc_err_free e )
            ^ ( json_obj_new )
        }
    }
}

@ noop_tool Json args → Json { ^ ( mcp_tool_result_text `ok` ) }

// The `text` of a tool result's first content block.
@ first_text Json result → s {
    ?? ( json_obj_get result `content` ) {
        T arr → {
            ?? ( json_arr_get arr 0 ) {
                T c0 → { ^ ( jstr c0 `text` ) }
                F _ → { ^ `<no content>` }
            }
        }
        F _ → { ^ `<no content>` }
    }
}

// A tool that answers differently depending on what the client
// declared — the whole point of the per-call context.
@ ctx_tool Json args McpCall call → Json {
    ? ( mcp_call_wants_tasks call ) { ^ ( mcp_tool_result_text `would-defer` ) } {}
    ^ ( mcp_tool_result_text `answered-inline` )
}

@ main → i {
    : McpServer srv ( mcp_server_new `caps` `2.0.0` )
    ( mcp_server_set_instructions srv
    `Start with search; read is cheap, build is not.` )
    ( mcp_server_add_tool_full srv `read` `Read a file.`
    ( mcp_schema_of1 `path` `string` `File to read.` T )
    T F T F \ Json a → Json { ^ ( noop_tool a ) } )
    ( mcp_server_add_tool srv `plain` `No annotations.` ( mcp_schema_empty )
    \ Json a → Json { ^ ( noop_tool a ) } )
    ( mcp_server_add_tool_ctx srv `defer` `Maybe a task.` ( mcp_schema_empty )
    F F F F \ Json a McpCall c → Json { ^ ( ctx_tool a c ) } )

    ( nurl_print `--- schema builder ---\n` )
    : Json tl ( dispatch srv ( req_of `tools/list` F ) )
    ?? ( json_obj_get tl `tools` ) {
        T arr → {
            ?? ( json_arr_get arr 0 ) {
                T t0 → {
                    ( label `tool0` ( jstr t0 `name` ) )
                    ?? ( json_obj_get t0 `inputSchema` ) {
                        T sc → {
                            ( label `schema_type` ( jstr sc `type` ) )
                            ( label_b `schema_has_props` ( jhas sc `properties` ) )
                            ( label_b `schema_has_required` ( jhas sc `required` ) )
                        }
                        F _ → {}
                    }
                    ( nurl_print `--- annotations ---\n` )
                    ?? ( json_obj_get t0 `annotations` ) {
                        T an → {
                            ( label_b `read_only`
                            ?? ( json_obj_get an `readOnlyHint` ) {
                                T v → ( json_as_bool v ) F → F
                            } )
                            ( label_b `destructive`
                            ?? ( json_obj_get an `destructiveHint` ) {
                                T v → ( json_as_bool v ) F → F
                            } )
                        }
                        F _ → { ( nurl_print `annotations MISSING\n` ) }
                    }
                }
                F _ → {}
            }
            // A tool registered without annotations must not grow an
            // empty `annotations` object — absent means absent.
            ?? ( json_arr_get arr 1 ) {
                T t1 → { ( label_b `plain_has_annotations` ( jhas t1 `annotations` ) ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( json_free tl )

    ( nurl_print `--- instructions ---\n` )
    : Json dj ( dispatch srv ( req_of `server/discover` F ) )
    ( label `discover_instructions` ( jstr dj `instructions` ) )
    ( json_free dj )
    : Json ij ( dispatch srv ( req_of `initialize` F ) )
    ( label `initialize_instructions` ( jstr ij `instructions` ) )
    ( json_free ij )

    ( nurl_print `--- per-call context ---\n` )
    : Json c1 ( dispatch srv ( tools_call_req `defer` F ) )
    ( label `no_tasks_declared` ( first_text c1 ) )
    ( json_free c1 )
    : Json c2 ( dispatch srv ( tools_call_req `defer` T ) )
    ( label `tasks_declared` ( first_text c2 ) )
    ( json_free c2 )

    ( nurl_print `--- tasks: not declared without a store ---\n` )
    : Json d0 ( dispatch srv ( req_of `server/discover` F ) )
    ?? ( json_obj_get d0 `capabilities` ) {
        T caps → { ( label_b `caps_has_extensions` ( jhas caps `extensions` ) ) }
        F _ → {}
    }
    ( json_free d0 )
    : Json tg ( req_of `tasks/get` T )
    ?? ( mcp_server_dispatch srv tg ) {
        T res → { ( nurl_print `tasks/get answered WITHOUT a store\n` ) ( json_free res ) }
        F e → {
            ( label `tasks_get_no_store` ( mcp_rpc_err_message e ) )
            ( mcp_rpc_err_free e )
        }
    }
    ( json_free tg )
    ( mcp_server_free srv )

    ( nurl_print `--- tasks: declared with a store ---\n` )
    : McpServer srv2 ( mcp_server_new `caps` `2.0.0` )
    : McpTaskStore store ( mcp_task_store_new )
    ( mcp_server_set_task_store srv2 store \ → v { ( nurl_print `hook ran\n` ) } )
    ( mcp_server_add_tool srv2 `plain` `No annotations.` ( mcp_schema_empty )
    \ Json a → Json { ^ ( noop_tool a ) } )
    : Json d1 ( dispatch srv2 ( req_of `server/discover` F ) )
    ?? ( json_obj_get d1 `capabilities` ) {
        T caps → { ( label_b `caps_has_extensions` ( jhas caps `extensions` ) ) }
        F _ → {}
    }
    ( json_free d1 )
    // An unknown task id: the hook must run first, then mcp_tasks
    // rejects the lookup — and the code it chose survives the trip.
    : Json tg2 ( req_of `tasks/get` T )
    ?? ( json_obj_get tg2 `params` ) {
        T p → { ( json_obj_set p `taskId` ( json_str_lit `nope` ) ) }
        F _ → {}
    }
    ?? ( mcp_server_dispatch srv2 tg2 ) {
        T res → { ( nurl_print `unexpected success\n` ) ( json_free res ) }
        F e → {
            ( nurl_print `tasks_get_unknown_code=` )
            ( nurl_print ( nurl_str_int ( mcp_rpc_err_code e ) ) )
            ( nurl_print `\n` )
            ( mcp_rpc_err_free e )
        }
    }
    ( json_free tg2 )
    ( mcp_task_store_free store )
    ( mcp_server_free srv2 )
    ^ 0
}
