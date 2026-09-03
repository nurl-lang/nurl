// mcp_server.nu — offline regression for the MCP server framework.
//
// Builds a minimal registry, runs each dispatch path, and prints the
// salient bits of every result Json so the baseline locks in the
// spec-shaped wire output. No sockets, no stdio — pure dispatcher
// exercises.

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_server.nu`

// The dispatcher returns `!Json McpRpcErr` — these tests drive it
// directly, so unwrap the success side here and let a failure print
// itself rather than vanishing into a golden that still looks right.
@ dispatch_ok McpServer r s method ? Json params → Json {
    ?? ( mcp_server_dispatch r method params ) {
        T res → { ^ res }
        F e → {
            ( nurl_print `UNEXPECTED RPC ERROR: ` )
            ( nurl_print ( mcp_rpc_err_message e ) )
            ( nurl_print `\n` )
            ( mcp_rpc_err_free e )
            ^ ( json_obj_new )
        }
    }
}

@ print_label s tag s value → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ print_label_i s tag i value → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print_int value ) ( nurl_print `\n` )
}

// Dispatch expecting FAILURE: prints the code and message under `tag`.
// CONSUMES `params`.
@ expect_err McpServer r s method Json params s tag → v {
    ?? ( mcp_server_dispatch r method @ ?Json { T params } ) {
        T res → {
            ( print_label tag `UNEXPECTED SUCCESS` )
            ( json_free res )
        }
        F e → {
            ( print_label_i ( nurl_str_cat tag `_code` ) ( mcp_rpc_err_code e ) )
            ( print_label ( nurl_str_cat tag `_msg` ) ( mcp_rpc_err_message e ) )
            ( mcp_rpc_err_free e )
        }
    }
    ( json_free params )
}

// Tool: echoes the `text` argument back wrapped in the standard
// tool-result envelope.
@ echo_tool Json args → Json {
    : ?Json t ( json_obj_get args `text` )
    : ~ s text `(none)`
    ?? t {
        T jt → { = text ( json_as_str jt ) }
        F _ → {}
    }
    ^ ( mcp_tool_result_text text )
}

// Tool: adds two ints `a` + `b`, returns the sum as text.
@ add_tool Json args → Json {
    : ~ i a 0
    : ~ i b 0
    : ?Json ja ( json_obj_get args `a` )
    ?? ja { T j → { = a ( json_as_int j ) } F _ → {} }
    : ?Json jb ( json_obj_get args `b` )
    ?? jb { T j → { = b ( json_as_int j ) } F _ → {} }
    : String s ( string_from `sum=` )
    ( string_push_str s ( nurl_str_int + a b ) )
    : Json r ( mcp_tool_result_text ( string_data s ) )
    ( string_free s )
    ^ r
}

// Prompt: returns a single user-role message with the rendered template.
@ greet_prompt Json args → Json {
    : ?Json n ( json_obj_get args `name` )
    : ~ s name `world`
    ?? n {
        T jn → { = name ( json_as_str jn ) }
        F _ → {}
    }
    : String text ( string_from `Hello, ` )
    ( string_push_str text name )
    ( string_push_str text `!` )

    : Json content ( json_obj_new )
    ( json_obj_set content `type` ( json_str_lit `text` ) )
    ( json_obj_set content `text` ( json_str_lit ( string_data text ) ) )
    ( string_free text )

    : Json msg ( json_obj_new )
    ( json_obj_set msg `role` ( json_str_lit `user` ) )
    ( json_obj_set msg `content` content )

    : Json msgs ( json_arr_new )
    ( json_arr_push msgs msg )

    : Json out ( json_obj_new )
    ( json_obj_set out `description` ( json_str_lit `A friendly greeting` ) )
    ( json_obj_set out `messages` msgs )
    ^ out
}

// Resource: returns a fixed string `text` content.
@ hello_resource → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `text` ( json_str_lit `hello from MCP resource` ) )
    ^ out
}

@ build_registry → McpServer {
    : McpServer r ( mcp_server_new `nurl-test-server` `1.0.0` )

    : Json echo_schema ( json_obj_new )
    ( json_obj_set echo_schema `type` ( json_str_lit `object` ) )
    : Json echo_props ( json_obj_new )
    : Json text_prop ( json_obj_new )
    ( json_obj_set text_prop `type` ( json_str_lit `string` ) )
    ( json_obj_set echo_props `text` text_prop )
    ( json_obj_set echo_schema `properties` echo_props )
    ( mcp_server_add_tool r `echo` `Echo input` echo_schema
    \ Json a → Json { ^ ( echo_tool a ) } )

    : Json add_schema ( json_obj_new )
    ( json_obj_set add_schema `type` ( json_str_lit `object` ) )
    ( mcp_server_add_tool r `add` `Add two numbers` add_schema
    \ Json a → Json { ^ ( add_tool a ) } )

    : Json greet_args ( json_arr_new )
    : Json greet_arg ( json_obj_new )
    ( json_obj_set greet_arg `name` ( json_str_lit `name` ) )
    ( json_obj_set greet_arg `required` ( json_bool F ) )
    ( json_arr_push greet_args greet_arg )
    ( mcp_server_add_prompt r `greet` `Friendly greeting` greet_args
    \ Json a → Json { ^ ( greet_prompt a ) } )

    ( mcp_server_add_resource r
    `mcp://hello`
    `Hello`
    `text/plain`
    `A friendly hello`
    \ → Json { ^ ( hello_resource ) } )

    ^ r
}

@ main → i {
    : McpServer reg ( build_registry )

    // ── initialize ───────────────────────────────────────────────────
    ( nurl_print `--- initialize ---\n` )
    : Json init ( dispatch_ok reg `initialize` @ ?Json { F ( json_null ) } )
    : ?Json proto ( json_obj_get init `protocolVersion` )
    ?? proto {
        T jp → ( print_label `protocolVersion` ( json_as_str jp ) )
        F _ → ( nurl_print `no protocol\n` )
    }
    : ?Json info ( json_obj_get init `serverInfo` )
    ?? info {
        T ji → {
            : ?Json nm ( json_obj_get ji `name` )
            ?? nm { T jn → ( print_label `serverInfo.name` ( json_as_str jn ) ) F _ → {} }
        }
        F _ → {}
    }
    ( json_free init )

    // ── tools/list ───────────────────────────────────────────────────
    ( nurl_print `--- tools/list ---\n` )
    : Json tl ( dispatch_ok reg `tools/list` @ ?Json { F ( json_null ) } )
    : ?Json tools_arr ( json_obj_get tl `tools` )
    ?? tools_arr {
        T arr → ( print_label `tools_count` ( nurl_str_int ( json_arr_len arr ) ) )
        F _ → {}
    }
    ( json_free tl )

    // ── tools/call echo ──────────────────────────────────────────────
    ( nurl_print `--- tools/call echo ---\n` )
    : Json call_params ( json_obj_new )
    ( json_obj_set call_params `name` ( json_str_lit `echo` ) )
    : Json args ( json_obj_new )
    ( json_obj_set args `text` ( json_str_lit `hello world` ) )
    ( json_obj_set call_params `arguments` args )
    : Json call_result ( dispatch_ok reg `tools/call` @ ?Json { T call_params } )
    : ?Json content ( json_obj_get call_result `content` )
    ?? content {
        T arr → {
            : ?Json e0 ( json_arr_get arr 0 )
            ?? e0 {
                T elem → {
                    : ?Json t ( json_obj_get elem `text` )
                    ?? t { T jt → ( print_label `echo_result` ( json_as_str jt ) ) F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( json_free call_result )

    // ── tools/call add ───────────────────────────────────────────────
    ( nurl_print `--- tools/call add ---\n` )
    : Json add_params ( json_obj_new )
    ( json_obj_set add_params `name` ( json_str_lit `add` ) )
    : Json add_args ( json_obj_new )
    ( json_obj_set add_args `a` ( json_int 17 ) )
    ( json_obj_set add_args `b` ( json_int 25 ) )
    ( json_obj_set add_params `arguments` add_args )
    : Json add_result ( dispatch_ok reg `tools/call` @ ?Json { T add_params } )
    : ?Json content2 ( json_obj_get add_result `content` )
    ?? content2 {
        T arr → {
            : ?Json e0 ( json_arr_get arr 0 )
            ?? e0 {
                T elem → {
                    : ?Json t ( json_obj_get elem `text` )
                    ?? t { T jt → ( print_label `add_result` ( json_as_str jt ) ) F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( json_free add_result )

    // ── tools/call unknown ───────────────────────────────────────────
    ( nurl_print `--- tools/call unknown ---\n` )
    : Json u_params ( json_obj_new )
    ( json_obj_set u_params `name` ( json_str_lit `nonexistent` ) )
    : Json u_args ( json_obj_new )
    ( json_obj_set u_params `arguments` u_args )
    : Json u_result ( dispatch_ok reg `tools/call` @ ?Json { T u_params } )
    : ?Json is_err ( json_obj_get u_result `isError` )
    ?? is_err {
        T je → ( print_label `unknown_isError` ? ( json_as_bool je ) `T` `F` )
        F _ → {}
    }
    ( json_free u_result )

    // ── prompts/list ─────────────────────────────────────────────────
    ( nurl_print `--- prompts/list ---\n` )
    : Json pl ( dispatch_ok reg `prompts/list` @ ?Json { F ( json_null ) } )
    : ?Json pa ( json_obj_get pl `prompts` )
    ?? pa { T arr → ( print_label `prompts_count` ( nurl_str_int ( json_arr_len arr ) ) ) F _ → {} }
    ( json_free pl )

    // ── prompts/get ──────────────────────────────────────────────────
    ( nurl_print `--- prompts/get ---\n` )
    : Json gp ( json_obj_new )
    ( json_obj_set gp `name` ( json_str_lit `greet` ) )
    : Json gargs ( json_obj_new )
    ( json_obj_set gargs `name` ( json_str_lit `NURL` ) )
    ( json_obj_set gp `arguments` gargs )
    : Json gr ( dispatch_ok reg `prompts/get` @ ?Json { T gp } )
    : ?Json gm ( json_obj_get gr `messages` )
    ?? gm {
        T arr → {
            : ?Json m0 ( json_arr_get arr 0 )
            ?? m0 {
                T msg → {
                    : ?Json c ( json_obj_get msg `content` )
                    ?? c {
                        T cc → {
                            : ?Json t ( json_obj_get cc `text` )
                            ?? t { T jt → ( print_label `prompt_text` ( json_as_str jt ) ) F _ → {} }
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( json_free gr )

    // ── resources/list ───────────────────────────────────────────────
    ( nurl_print `--- resources/list ---\n` )
    : Json rl ( dispatch_ok reg `resources/list` @ ?Json { F ( json_null ) } )
    : ?Json ra ( json_obj_get rl `resources` )
    ?? ra { T arr → ( print_label `resources_count` ( nurl_str_int ( json_arr_len arr ) ) ) F _ → {} }
    ( json_free rl )

    // ── resources/read ───────────────────────────────────────────────
    ( nurl_print `--- resources/read ---\n` )
    : Json rp ( json_obj_new )
    ( json_obj_set rp `uri` ( json_str_lit `mcp://hello` ) )
    : Json rr ( dispatch_ok reg `resources/read` @ ?Json { T rp } )
    : ?Json carr ( json_obj_get rr `contents` )
    ?? carr {
        T arr → {
            : ?Json c0 ( json_arr_get arr 0 )
            ?? c0 {
                T cc → {
                    : ?Json u ( json_obj_get cc `uri` )
                    ?? u { T ju → ( print_label `resource_uri` ( json_as_str ju ) ) F _ → {} }
                    : ?Json t ( json_obj_get cc `text` )
                    ?? t { T jt → ( print_label `resource_text` ( json_as_str jt ) ) F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( json_free rr )

    // ── unknown method ───────────────────────────────────────────────
    ( nurl_print `--- unknown method ---\n` )
    ?? ( mcp_server_dispatch reg `nonexistent/method` @ ?Json { F ( json_null ) } ) {
        T res → {
            ( nurl_print `expected an RPC error\n` )
            ( json_free res )
        }
        F e → {
            ( print_label `unknown_method_err` ( mcp_rpc_err_message e ) )
            ( print_label_i `unknown_method_code` ( mcp_rpc_err_code e ) )
            ( mcp_rpc_err_free e )
        }
    }

    // ── failure codes are not all -32601 ─────────────────────────────
    //
    // Before the Result split every dispatch failure went out as
    // "method not found", so a client that got one for a malformed
    // prompts/get concluded the method did not exist and stopped
    // calling it. Each of these must carry its own code.
    ( nurl_print `--- error codes ---\n` )
    ( expect_err reg `prompts/get` ( json_obj_new ) `prompts_get_no_name` )
    : Json unknown_prompt ( json_obj_new )
    ( json_obj_set unknown_prompt `name` ( json_str_lit `nope` ) )
    ( expect_err reg `prompts/get` unknown_prompt `prompts_get_unknown` )
    ( expect_err reg `resources/read` ( json_obj_new ) `resources_read_no_uri` )
    : Json unknown_res ( json_obj_new )
    ( json_obj_set unknown_res `uri` ( json_str_lit `mcp://absent` ) )
    ( expect_err reg `resources/read` unknown_res `resources_read_unknown` )

    // ── ping ─────────────────────────────────────────────────────────
    ( nurl_print `--- ping ---\n` )
    : Json png ( dispatch_ok reg `ping` @ ?Json { F ( json_null ) } )
    ( print_label `ping_obj_kind` ? ( json_is_obj png ) `obj` `other` )
    ( json_free png )

    ( mcp_server_free reg )
    ^ 0
}
