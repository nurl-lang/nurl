// mcp_server_gated.nu — one server, many callers: the caller context
// (`mcp_server_dispatch_as` → `mcp_call_context`) and the tools whose
// existence depends on it (`mcp_server_add_tool_gated`).
//
//   * tools/list shows a gated tool only to a caller its predicate
//     accepts; ungated tools show to everyone.
//   * tools/call on a gated tool the caller may not see answers exactly
//     as for an unregistered name — the caller is not told it exists.
//   * the handler reads the same context the predicate did, so it acts
//     as the identity that let it be listed.
//   * the plain `mcp_server_dispatch` hands the predicate JSON null, and
//     a predicate written for that case decides it too.
//   * the context is borrowed: the host frees it after the call, and
//     the results carry no reference to it.

$ `stdlib/ext/mcp_server.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ label s tag s v → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ ctx_of s role → Json {
    : Json c ( json_obj_new )
    ( json_obj_set c `role` ( json_str_lit role ) )
    ^ c
}

@ role_of Json c → s {
    ? ( json_is_obj c ) {
        ^ ?? ( json_obj_get c `role` ) { T j → ( json_as_str j ) F → `?` }
    } { ^ `anonymous` }
}

@ req_of s method → Json {
    : Json req ( json_obj_new )
    ( json_obj_set req `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set req `method` ( json_str_lit method ) )
    ( json_obj_set req `params` ( json_obj_new ) )
    ^ req
}

@ call_req s tool → Json {
    : Json req ( req_of `tools/call` )
    ?? ( json_obj_get req `params` ) {
        T p → { ( json_obj_set p `name` ( json_str_lit tool ) ) }
        F → {}
    }
    ^ req
}

// Names in a tools/list result, comma-joined.
@ list_names McpServer srv Json ctx → String {
    : Json req ( req_of `tools/list` )
    : String out ( string_from `` )
    ?? ( mcp_server_dispatch_as srv req ctx ) {
        T res → {
            ?? ( json_obj_get res `tools` ) {
                T arr → {
                    : i n ( json_arr_len arr )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( json_arr_get arr k ) {
                            T e → {
                                ? > k 0 { ( string_push_str out `,` ) } {}
                                ?? ( json_obj_get e `name` ) {
                                    T nm → { ( string_push_str out ( json_as_str nm ) ) }
                                    F → {}
                                }
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                }
                F → {}
            }
            ( json_free res )
        }
        F e → { ( mcp_rpc_err_free e ) }
    }
    ( json_free req )
    ^ out
}

// First text block of a tool result, plus whether it was an error.
@ call_text McpServer srv s tool Json ctx → String {
    : Json req ( call_req tool )
    : String out ( string_from `` )
    ?? ( mcp_server_dispatch_as srv req ctx ) {
        T res → {
            ?? ( json_obj_get res `isError` ) {
                T ie → { ? ( json_bool_val ie ) { ( string_push_str out `ERR:` ) } {} }
                F → {}
            }
            ?? ( json_obj_get res `content` ) {
                T c → {
                    ?? ( json_arr_get c 0 ) {
                        T b0 → {
                            ?? ( json_obj_get b0 `text` ) {
                                T t → { ( string_push_str out ( json_as_str t ) ) }
                                F → {}
                            }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free res )
        }
        F e → { ( mcp_rpc_err_free e ) }
    }
    ( json_free req )
    ^ out
}

@ main → i {
    : McpServer srv ( mcp_server_new `gated` `0.1` )
    ( mcp_server_add_tool_full srv `whoami` `Who is calling.` ( mcp_schema_empty )
    T F T F
    \ Json a → Json { ^ ( mcp_tool_result_text `plain tool` ) } )
    // Visible to admins only; the handler names the role it saw.
    ( mcp_server_add_tool_gated srv `delete_everything` `Admin only.` ( mcp_schema_empty )
    F T F F
    \ Json c → b { ^ != 0 ( nurl_str_eq ( role_of c ) `admin` ) }
    \ Json a McpCall call → Json {
        : String t ( string_from `deleting as ` )
        ( string_push_str t ( role_of ( mcp_call_context call ) ) )
        : Json r ( mcp_tool_result_text ( string_data t ) )
        ( string_free t )
        ^ r
    } )
    // Visible to any authenticated caller — i.e. not to the null context.
    ( mcp_server_add_tool_gated srv `my_models` `Members only.` ( mcp_schema_empty )
    T F T F
    \ Json c → b { ^ ( json_is_obj c ) }
    \ Json a McpCall call → Json {
        : String t ( string_from `models of ` )
        ( string_push_str t ( role_of ( mcp_call_context call ) ) )
        : Json r ( mcp_tool_result_text ( string_data t ) )
        ( string_free t )
        ^ r
    } )

    : Json admin ( ctx_of `admin` )
    : Json viewer ( ctx_of `viewer` )
    : Json nobody ( json_null )

    : String l1 ( list_names srv admin )
    ( label `list.admin` ( string_data l1 ) )
    ( string_free l1 )
    : String l2 ( list_names srv viewer )
    ( label `list.viewer` ( string_data l2 ) )
    ( string_free l2 )
    : String l3 ( list_names srv nobody )
    ( label `list.null` ( string_data l3 ) )
    ( string_free l3 )

    : String c1 ( call_text srv `delete_everything` admin )
    ( label `call.admin.delete` ( string_data c1 ) )
    ( string_free c1 )
    : String c2 ( call_text srv `delete_everything` viewer )
    ( label `call.viewer.delete` ( string_data c2 ) )
    ( string_free c2 )
    : String c3 ( call_text srv `no_such_tool` viewer )
    ( label `call.viewer.unknown` ( string_data c3 ) )
    ( string_free c3 )
    : String c4 ( call_text srv `my_models` viewer )
    ( label `call.viewer.models` ( string_data c4 ) )
    ( string_free c4 )
    : String c5 ( call_text srv `my_models` nobody )
    ( label `call.null.models` ( string_data c5 ) )
    ( string_free c5 )
    : String c6 ( call_text srv `whoami` nobody )
    ( label `call.null.plain` ( string_data c6 ) )
    ( string_free c6 )

    // The plain dispatch is the null-context dispatch.
    : Json req ( req_of `tools/list` )
    ?? ( mcp_server_dispatch srv req ) {
        T res → {
            : i n ?? ( json_obj_get res `tools` ) { T a → ( json_arr_len a ) F → -1 }
            ( label `plain.count` ( nurl_str_int n ) )
            ( json_free res )
        }
        F e → { ( mcp_rpc_err_free e ) }
    }
    ( json_free req )

    // Contexts outlive nothing: free them after the calls, then the server.
    ( json_free admin )
    ( json_free viewer )
    ( json_free nobody )
    ( mcp_server_free srv )
    ^ 0
}
