// mcp_completion.nu — offline regression for MCP completion/complete
// (spec §6.7) on the server registry.
//
// Registers a prompt-argument completer and a resource completer, then
// drives completion/complete through mcp_server_dispatch and prints the
// spec-shaped {completion: {values, total, hasMore}} envelope. Also
// checks that `initialize` now advertises the `completions` capability.
// No sockets — pure dispatcher exercise (mirrors mcp_server.nu).

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
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

// Push `cand` onto `arr` iff it starts with `prefix`. Frees the
// temporary String it builds for the prefix test.
@ push_if_prefix Json arr s cand s prefix → v {
    : String cs ( string_from cand )
    ? ( string_starts_with cs prefix )
    { ( json_arr_push arr ( json_str_lit cand ) ) } {}
    ( string_free cs )
}

// Completion provider for the `language` prompt argument: prefix-filter a
// fixed candidate list against the partial `value` the client typed.
@ lang_completion Json arg → Json {
    : ~ s prefix ``
    : ?Json v ( json_obj_get arg `value` )
    ?? v {
        T jv → { = prefix ( json_as_str jv ) }
        F _ → {}
    }
    : Json out ( json_arr_new )
    ( push_if_prefix out `python` prefix )
    ( push_if_prefix out `ruby` prefix )
    ( push_if_prefix out `rust` prefix )
    ( push_if_prefix out `go` prefix )
    ^ out
}

// Completion provider for a resource URI argument: returns a fixed list.
@ branch_completion Json arg → Json {
    : Json out ( json_arr_new )
    ( json_arr_push out ( json_str_lit `main` ) )
    ( json_arr_push out ( json_str_lit `develop` ) )
    ^ out
}

@ build_registry → McpServer {
    : McpServer r ( mcp_server_new `nurl-completion-test` `1.0.0` )

    // A prompt the completion is attached to.
    : Json greet_args ( json_arr_new )
    ( mcp_server_add_prompt r `greet` `Greeting` greet_args
    \ Json a → Json { ^ ( json_obj_new ) } )

    // completion for the prompt's `language` argument.
    ( mcp_server_add_completion r `ref/prompt` `greet`
    \ Json a → Json { ^ ( lang_completion a ) } )

    // completion for a resource template argument.
    ( mcp_server_add_completion r `ref/resource` `git://repo`
    \ Json a → Json { ^ ( branch_completion a ) } )

    ^ r
}

// Print values count, total, hasMore, and the first value (if any).
@ report_completion s tag Json result → v {
    : ?Json comp ( json_obj_get result `completion` )
    ?? comp {
        T c → {
            : ?Json vals ( json_obj_get c `values` )
            ?? vals {
                T arr → {
                    ( print_label ( nurl_str_cat tag `.count` ) ( nurl_str_int ( json_arr_len arr ) ) )
                    : ?Json v0 ( json_arr_get arr 0 )
                    ?? v0 {
                        T jv → ( print_label ( nurl_str_cat tag `.first` ) ( json_as_str jv ) )
                        F _ → ( print_label ( nurl_str_cat tag `.first` ) `(none)` )
                    }
                }
                F _ → ( nurl_print `no values array\n` )
            }
            : ?Json tot ( json_obj_get c `total` )
            ?? tot { T jt → ( print_label ( nurl_str_cat tag `.total` ) ( nurl_str_int ( json_as_int jt ) ) ) F _ → {} }
            : ?Json hm ( json_obj_get c `hasMore` )
            ?? hm { T jh → ( print_label ( nurl_str_cat tag `.hasMore` ) ? ( json_as_bool jh ) `T` `F` ) F _ → {} }
        }
        F _ → ( nurl_print `no completion object\n` )
    }
}

@ complete_params s ref_type s ref_id s arg_name s arg_value → Json {
    : Json ref ( json_obj_new )
    ( json_obj_set ref `type` ( json_str_lit ref_type ) )
    ? != 0 ( nurl_str_eq ref_type `ref/resource` )
    { ( json_obj_set ref `uri` ( json_str_lit ref_id ) ) }
    { ( json_obj_set ref `name` ( json_str_lit ref_id ) ) }
    : Json argo ( json_obj_new )
    ( json_obj_set argo `name` ( json_str_lit arg_name ) )
    ( json_obj_set argo `value` ( json_str_lit arg_value ) )
    : Json params ( json_obj_new )
    ( json_obj_set params `ref` ref )
    ( json_obj_set params `argument` argo )
    ^ params
}

@ main → i {
    : McpServer reg ( build_registry )

    // ── initialize advertises the completions capability ───────────────
    ( nurl_print `--- initialize ---\n` )
    : Json init ( dispatch_ok reg `initialize` @ ?Json { F ( json_null ) } )
    : ?Json caps ( json_obj_get init `capabilities` )
    ?? caps {
        T cp → {
            : ?Json comp_cap ( json_obj_get cp `completions` )
            ?? comp_cap {
                T _ → ( print_label `completions_capability` `present` )
                F _ → ( print_label `completions_capability` `absent` )
            }
        }
        F _ → {}
    }
    ( json_free init )

    // ── completion/complete: prompt arg, prefix "r" → ruby, rust ───────
    ( nurl_print `--- completion prompt (prefix r) ---\n` )
    : Json p1 ( complete_params `ref/prompt` `greet` `language` `r` )
    : Json r1 ( dispatch_ok reg `completion/complete` @ ?Json { T p1 } )
    ( report_completion `prompt_r` r1 )
    ( json_free r1 )
    ( json_free p1 )

    // ── completion/complete: prompt arg, empty prefix → all 4 ──────────
    ( nurl_print `--- completion prompt (empty prefix) ---\n` )
    : Json p2 ( complete_params `ref/prompt` `greet` `language` `` )
    : Json r2 ( dispatch_ok reg `completion/complete` @ ?Json { T p2 } )
    ( report_completion `prompt_all` r2 )
    ( json_free r2 )
    ( json_free p2 )

    // ── completion/complete: resource ref ──────────────────────────────
    ( nurl_print `--- completion resource ---\n` )
    : Json p3 ( complete_params `ref/resource` `git://repo` `branch` `` )
    : Json r3 ( dispatch_ok reg `completion/complete` @ ?Json { T p3 } )
    ( report_completion `resource` r3 )
    ( json_free r3 )
    ( json_free p3 )

    // ── completion/complete: unknown ref → empty list ──────────────────
    ( nurl_print `--- completion unknown ref ---\n` )
    : Json p4 ( complete_params `ref/prompt` `nonexistent` `x` `a` )
    : Json r4 ( dispatch_ok reg `completion/complete` @ ?Json { T p4 } )
    ( report_completion `unknown` r4 )
    ( json_free r4 )
    ( json_free p4 )

    ( mcp_server_free reg )
    ^ 0
}
