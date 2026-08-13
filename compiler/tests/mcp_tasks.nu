// Regression: stdlib/ext/mcp_tasks.nu — the io.modelcontextprotocol/tasks
// extension. Task store lifecycle, the CreateTaskResult / DetailedTask
// wire shapes, per-request capability negotiation and the tasks/get,
// tasks/update and tasks/cancel handlers. Pure in-memory; no sockets.
// Returns the failure count.

$ `stdlib/ext/mcp_tasks.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── helpers ─────────────────────────────────────────────────────────

@ jstr Json o s key → s {
    ^ ?? ( json_obj_get o key ) { T j → ( json_as_str j ) F → `` }
}

@ jint Json o s key → i {
    ^ ?? ( json_obj_get o key ) { T j → ( json_as_int j ) F → -1 }
}

// The `result` object of a JSON-RPC response envelope (borrowed).
@ resp_result Json env → Json {
    ^ ?? ( json_obj_get env `result` ) { T j → j F → env }
}

@ resp_err_code Json env → i {
    ?? ( json_obj_get env `error` ) {
        T e → { ^ ( jint e `code` ) }
        F → { ^ 0 }
    }
}

// A tools/call request that DOES declare the tasks extension.
@ req_with_caps s method → Json {
    : Json ext ( json_obj_new )
    ( json_obj_set ext ( mcp_tasks_ext_id ) ( json_obj_new ) )
    : Json caps ( json_obj_new )
    ( json_obj_set caps `extensions` ext )
    : Json meta ( json_obj_new )
    ( json_obj_set meta `io.modelcontextprotocol/clientCapabilities` caps )
    : Json params ( json_obj_new )
    ( json_obj_set params `_meta` meta )
    : Json req ( json_obj_new )
    ( json_obj_set req `method` ( json_str_lit method ) )
    ( json_obj_set req `params` params )
    ^ req
}

// The same request without any `_meta` — a legacy-era client.
@ req_bare s method → Json {
    : Json req ( json_obj_new )
    ( json_obj_set req `method` ( json_str_lit method ) )
    ( json_obj_set req `params` ( json_obj_new ) )
    ^ req
}

@ params_with_id s id → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `taskId` ( json_str_lit id ) )
    ^ p
}

@ main → i {
    : ~ i fails 0
    : Json id1 ( json_int 1 )

    // ── status names round-trip ──
    ? != 0 ( nurl_str_eq ( mcp_task_status_name mcp_task_working ) `working` ) {} {
        ( nurl_print `  FAIL name-working\n` ) = fails + fails 1
    }
    ? != 0 ( nurl_str_eq ( mcp_task_status_name mcp_task_input_required ) `input_required` ) {} {
        ( nurl_print `  FAIL name-input\n` ) = fails + fails 1
    }
    ? != ( mcp_task_status_from_name `cancelled` ) mcp_task_cancelled {
        ( nurl_print `  FAIL from-name\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_status_from_name `nope` ) -1 {
        ( nurl_print `  FAIL from-name-unknown\n` ) = fails + fails 1
    } {}
    ? ( mcp_task_status_is_terminal mcp_task_working ) {
        ( nurl_print `  FAIL terminal-working\n` ) = fails + fails 1
    } {}
    ? ( mcp_task_status_is_terminal mcp_task_input_required ) {
        ( nurl_print `  FAIL terminal-input\n` ) = fails + fails 1
    } {}
    ? ( mcp_task_status_is_terminal mcp_task_failed ) {} {
        ( nurl_print `  FAIL terminal-failed\n` ) = fails + fails 1
    }

    // ── capability negotiation ──
    : Json caps ( json_obj_new )
    ( mcp_caps_declare_tasks caps )
    ?? ( json_obj_get caps `extensions` ) {
        T ex → {
            ? ( json_obj_has ex ( mcp_tasks_ext_id ) ) {} {
                ( nurl_print `  FAIL caps-ext\n` ) = fails + fails 1
            }
        }
        F → { ( nurl_print `  FAIL caps-no-extensions\n` ) = fails + fails 1 }
    }
    // A second extension must merge into the same `extensions` object.
    ( mcp_caps_declare_extension caps `example.com/other` )
    ?? ( json_obj_get caps `extensions` ) {
        T ex → {
            ? & ( json_obj_has ex ( mcp_tasks_ext_id ) ) ( json_obj_has ex `example.com/other` ) {} {
                ( nurl_print `  FAIL caps-merge\n` ) = fails + fails 1
            }
        }
        F → { ( nurl_print `  FAIL caps-merge-none\n` ) = fails + fails 1 }
    }
    ( json_free caps )

    : Json req_ok ( req_with_caps `tools/call` )
    : Json req_no ( req_bare `tools/call` )
    ? ( mcp_request_declares_tasks req_ok ) {} {
        ( nurl_print `  FAIL declares-yes\n` ) = fails + fails 1
    }
    ? ( mcp_request_declares_tasks req_no ) {
        ( nurl_print `  FAIL declares-no\n` ) = fails + fails 1
    } {}

    // ── store + task creation ──
    : McpTaskStore store ( mcp_task_store_new )
    ? != ( mcp_task_store_count store ) 0 {
        ( nurl_print `  FAIL count0\n` ) = fails + fails 1
    } {}

    : Json args ( json_obj_new )
    ( json_obj_set args `city` ( json_str_lit `Helsinki` ) )
    : s tp ( mcp_task_create store `tools/call` `get_weather` args 3600000 5000 )
    ? != ( mcp_task_store_count store ) 1 {
        ( nurl_print `  FAIL count1\n` ) = fails + fails 1
    } {}
    // 16 CSPRNG bytes → 32 hex chars, unguessable per the spec.
    ? != ( nurl_str_len ( mcp_task_id tp ) ) 32 {
        ( nurl_print `  FAIL id-len\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_status tp ) mcp_task_working {
        ( nurl_print `  FAIL seed-status\n` ) = fails + fails 1
    } {}
    ? != 0 ( nurl_str_eq ( mcp_task_tool tp ) `get_weather` ) {} {
        ( nurl_print `  FAIL tool\n` ) = fails + fails 1
    }
    ? != 0 ( nurl_str_eq ( mcp_task_method tp ) `tools/call` ) {} {
        ( nurl_print `  FAIL method\n` ) = fails + fails 1
    }
    // The arguments survive into the task, borrowed.
    ? != 0 ( nurl_str_eq ( jstr ( mcp_task_args tp ) `city` ) `Helsinki` ) {} {
        ( nurl_print `  FAIL args\n` ) = fails + fails 1
    }
    ( mcp_task_set_link tp 42 )
    ? != ( mcp_task_link tp ) 42 { ( nurl_print `  FAIL link\n` ) = fails + fails 1 } {}

    // Distinct ids.
    : s tp2 ( mcp_task_create store `tools/call` `other` ( json_obj_new ) -1 0 )
    ? != 0 ( nurl_str_eq ( mcp_task_id tp ) ( mcp_task_id tp2 ) ) {
        ( nurl_print `  FAIL id-collision\n` ) = fails + fails 1
    } {}

    // ── lookup ──
    : String held ( string_from ( mcp_task_id tp ) )
    : s tid ( string_data held )
    ? != # i ( mcp_task_find store tid ) # i tp {
        ( nurl_print `  FAIL find\n` ) = fails + fails 1
    } {}
    ? != # i ( mcp_task_find store `deadbeef` ) 0 {
        ( nurl_print `  FAIL find-bogus\n` ) = fails + fails 1
    } {}
    ? != # i ( mcp_task_find store `` ) 0 {
        ( nurl_print `  FAIL find-empty\n` ) = fails + fails 1
    } {}

    // ── CreateTaskResult shape ──
    : Json ctr ( mcp_task_create_result tp )
    ? != 0 ( nurl_str_eq ( jstr ctr `resultType` ) `task` ) {} {
        ( nurl_print `  FAIL ctr-resultType\n` ) = fails + fails 1
    }
    ? != 0 ( nurl_str_eq ( jstr ctr `taskId` ) tid ) {} {
        ( nurl_print `  FAIL ctr-taskId\n` ) = fails + fails 1
    }
    ? != 0 ( nurl_str_eq ( jstr ctr `status` ) `working` ) {} {
        ( nurl_print `  FAIL ctr-status\n` ) = fails + fails 1
    }
    ? != ( jint ctr `ttlMs` ) 3600000 { ( nurl_print `  FAIL ctr-ttl\n` ) = fails + fails 1 } {}
    ? != ( jint ctr `pollIntervalMs` ) 5000 { ( nurl_print `  FAIL ctr-poll\n` ) = fails + fails 1 } {}
    // ISO 8601: 2026-08-13T09:41:00Z — 20 chars, trailing Z.
    ? != ( nurl_str_len ( jstr ctr `createdAt` ) ) 20 {
        ( nurl_print `  FAIL ctr-createdAt\n` ) = fails + fails 1
    } {}
    ? ( json_obj_has ctr `lastUpdatedAt` ) {} {
        ( nurl_print `  FAIL ctr-lastUpdatedAt\n` ) = fails + fails 1
    }
    // A working task carries no result / error / inputRequests.
    ? ( json_obj_has ctr `result` ) { ( nurl_print `  FAIL ctr-result\n` ) = fails + fails 1 } {}
    ? ( json_obj_has ctr `error` ) { ( nurl_print `  FAIL ctr-error\n` ) = fails + fails 1 } {}
    ( json_free ctr )

    // An unlimited TTL encodes as JSON null, and the poll hint is omitted.
    : Json ctr2 ( mcp_task_create_result tp2 )
    ?? ( json_obj_get ctr2 `ttlMs` ) {
        T tj → {
            ? ( json_is_null tj ) {} { ( nurl_print `  FAIL ttl-null\n` ) = fails + fails 1 }
        }
        F → { ( nurl_print `  FAIL ttl-missing\n` ) = fails + fails 1 }
    }
    ? ( json_obj_has ctr2 `pollIntervalMs` ) {
        ( nurl_print `  FAIL poll-omitted\n` ) = fails + fails 1
    } {}
    ( json_free ctr2 )

    // ── tasks/get on a working task ──
    : Json p_get ( params_with_id tid )
    : Json g1 ( mcp_tasks_handle_get store id1 p_get )
    // The standard envelope injects resultType "complete" on tasks/get.
    ? != 0 ( nurl_str_eq ( jstr ( resp_result g1 ) `resultType` ) `complete` ) {} {
        ( nurl_print `  FAIL get-resultType\n` ) = fails + fails 1
    }
    ? != 0 ( nurl_str_eq ( jstr ( resp_result g1 ) `status` ) `working` ) {} {
        ( nurl_print `  FAIL get-status\n` ) = fails + fails 1
    }
    ( json_free g1 )

    // Unknown id → -32602 (Invalid params), not a bare result.
    : Json p_bad ( params_with_id `nosuchtask` )
    : Json g2 ( mcp_tasks_handle_get store id1 p_bad )
    ? != ( resp_err_code g2 ) mcp_err_invalid_params {
        ( nurl_print `  FAIL get-unknown\n` ) = fails + fails 1
    } {}
    ( json_free g2 )
    ( json_free p_bad )

    // ── input_required → tasks/update → responses ──
    : Json elicit ( json_obj_new )
    ( json_obj_set elicit `method` ( json_str_lit `elicitation/create` ) )
    : Json reqs ( json_obj_new )
    ( json_obj_set reqs `name` elicit )
    ( mcp_task_request_input tp reqs )
    ? != ( mcp_task_status tp ) mcp_task_input_required {
        ( nurl_print `  FAIL input-status\n` ) = fails + fails 1
    } {}

    : Json g3 ( mcp_tasks_handle_get store id1 p_get )
    ?? ( json_obj_get ( resp_result g3 ) `inputRequests` ) {
        T ir → {
            ? ( json_obj_has ir `name` ) {} {
                ( nurl_print `  FAIL get-inputRequests-key\n` ) = fails + fails 1
            }
        }
        F → { ( nurl_print `  FAIL get-inputRequests\n` ) = fails + fails 1 }
    }
    ( json_free g3 )

    // Nothing delivered yet.
    ?? ( mcp_task_take_input_responses tp ) {
        T j → { ( nurl_print `  FAIL take-early\n` ) = fails + fails 1 ( json_free j ) }
        F → {}
    }

    // tasks/update carrying one answer plus one key that was never issued —
    // the unknown key must be ignored, the known one recorded.
    : Json answer ( json_obj_new )
    ( json_obj_set answer `action` ( json_str_lit `accept` ) )
    : Json responses ( json_obj_new )
    ( json_obj_set responses `name` answer )
    ( json_obj_set responses `bogus` ( json_str_lit `ignored` ) )
    : Json p_upd ( params_with_id tid )
    ( json_obj_set p_upd `inputResponses` responses )
    : Json u1 ( mcp_tasks_handle_update store id1 p_upd )
    // Empty acknowledgement — resultType "complete" and nothing else.
    ? != 0 ( nurl_str_eq ( jstr ( resp_result u1 ) `resultType` ) `complete` ) {} {
        ( nurl_print `  FAIL update-ack\n` ) = fails + fails 1
    }
    ( json_free u1 )
    ( json_free p_upd )

    ?? ( mcp_task_take_input_responses tp ) {
        T got → {
            ? ( json_obj_has got `name` ) {} {
                ( nurl_print `  FAIL take-name\n` ) = fails + fails 1
            }
            ? ( json_obj_has got `bogus` ) {
                ( nurl_print `  FAIL take-bogus-kept\n` ) = fails + fails 1
            } {}
            ( json_free got )
        }
        F → { ( nurl_print `  FAIL take-none\n` ) = fails + fails 1 }
    }
    // Draining is one-shot.
    ?? ( mcp_task_take_input_responses tp ) {
        T j → { ( nurl_print `  FAIL take-twice\n` ) = fails + fails 1 ( json_free j ) }
        F → {}
    }

    // tasks/update against an unknown task → -32602.
    : Json p_upd_bad ( params_with_id `nosuchtask` )
    : Json u2 ( mcp_tasks_handle_update store id1 p_upd_bad )
    ? != ( resp_err_code u2 ) mcp_err_invalid_params {
        ( nurl_print `  FAIL update-unknown\n` ) = fails + fails 1
    } {}
    ( json_free u2 )
    ( json_free p_upd_bad )

    // ── completion ──
    ( mcp_task_set_working tp `crunching` )
    ? != ( mcp_task_status tp ) mcp_task_working {
        ( nurl_print `  FAIL back-to-working\n` ) = fails + fails 1
    } {}
    : Json g4 ( mcp_tasks_handle_get store id1 p_get )
    ? != 0 ( nurl_str_eq ( jstr ( resp_result g4 ) `statusMessage` ) `crunching` ) {} {
        ( nurl_print `  FAIL statusMessage\n` ) = fails + fails 1
    }
    // Back in working, the outstanding requests are gone.
    ? ( json_obj_has ( resp_result g4 ) `inputRequests` ) {
        ( nurl_print `  FAIL working-inputRequests\n` ) = fails + fails 1
    } {}
    ( json_free g4 )

    ( mcp_task_complete tp ( mcp_tool_result_text `Hello, Luca!` ) )
    ? != ( mcp_task_status tp ) mcp_task_completed {
        ( nurl_print `  FAIL completed\n` ) = fails + fails 1
    } {}
    : Json g5 ( mcp_tasks_handle_get store id1 p_get )
    ?? ( json_obj_get ( resp_result g5 ) `result` ) {
        T r → {
            ? ( json_obj_has r `content` ) {} {
                ( nurl_print `  FAIL completed-content\n` ) = fails + fails 1
            }
        }
        F → { ( nurl_print `  FAIL completed-result\n` ) = fails + fails 1 }
    }
    ( json_free g5 )

    // The task detail must be re-readable (the stored result is cloned,
    // not moved out, so a second poll still sees it).
    : Json g6 ( mcp_tasks_handle_get store id1 p_get )
    ? ( json_obj_has ( resp_result g6 ) `result` ) {} {
        ( nurl_print `  FAIL completed-repoll\n` ) = fails + fails 1
    }
    ( json_free g6 )

    // ── failure carries a JSON-RPC error object ──
    : s tp3 ( mcp_task_create store `tools/call` `boom` ( json_obj_new ) -1 0 )
    ( mcp_task_fail tp3 mcp_err_internal_error `API rate limit exceeded` )
    ? != ( mcp_task_status tp3 ) mcp_task_failed {
        ( nurl_print `  FAIL failed-status\n` ) = fails + fails 1
    } {}
    : Json d3 ( mcp_task_detail tp3 )
    ?? ( json_obj_get d3 `error` ) {
        T e → {
            ? != ( jint e `code` ) mcp_err_internal_error {
                ( nurl_print `  FAIL failed-code\n` ) = fails + fails 1
            } {}
        }
        F → { ( nurl_print `  FAIL failed-error\n` ) = fails + fails 1 }
    }
    ? != 0 ( nurl_str_eq ( jstr d3 `statusMessage` ) `API rate limit exceeded` ) {} {
        ( nurl_print `  FAIL failed-message\n` ) = fails + fails 1
    }
    ( json_free d3 )

    // ── notifications/tasks carries the same DetailedTask ──
    : Json note ( mcp_task_notification tp3 )
    ? != 0 ( nurl_str_eq ( jstr note `method` ) `notifications/tasks` ) {} {
        ( nurl_print `  FAIL note-method\n` ) = fails + fails 1
    }
    ?? ( json_obj_get note `params` ) {
        T np → {
            ? != 0 ( nurl_str_eq ( jstr np `status` ) `failed` ) {} {
                ( nurl_print `  FAIL note-status\n` ) = fails + fails 1
            }
            ? ( json_obj_has np `error` ) {} {
                ( nurl_print `  FAIL note-error\n` ) = fails + fails 1
            }
        }
        F → { ( nurl_print `  FAIL note-params\n` ) = fails + fails 1 }
    }
    ( json_free note )

    // ── cancellation is cooperative ──
    : Json p_cancel ( params_with_id ( mcp_task_id tp2 ) )
    : Json c1 ( mcp_tasks_handle_cancel store id1 p_cancel )
    ? != 0 ( nurl_str_eq ( jstr ( resp_result c1 ) `resultType` ) `complete` ) {} {
        ( nurl_print `  FAIL cancel-ack\n` ) = fails + fails 1
    }
    ( json_free c1 )
    ( json_free p_cancel )
    ? ( mcp_task_cancel_requested tp2 ) {} {
        ( nurl_print `  FAIL cancel-flag\n` ) = fails + fails 1
    }
    // The ack does NOT force the status — the work may still finish.
    ? != ( mcp_task_status tp2 ) mcp_task_working {
        ( nurl_print `  FAIL cancel-status-forced\n` ) = fails + fails 1
    } {}
    ( mcp_task_cancel tp2 )
    ? != ( mcp_task_status tp2 ) mcp_task_cancelled {
        ( nurl_print `  FAIL cancelled\n` ) = fails + fails 1
    } {}

    // ── dispatch: routing + the capability gate ──
    ? ( mcp_tasks_is_method `tasks/get` ) {} {
        ( nurl_print `  FAIL is-method\n` ) = fails + fails 1
    }
    ? ( mcp_tasks_is_method `tools/call` ) {
        ( nurl_print `  FAIL is-method-tools\n` ) = fails + fails 1
    } {}

    // Not a tasks method → None, so the caller's own dispatch continues.
    ?? ( mcp_tasks_dispatch store req_ok id1 `tools/call` ) {
        T j → { ( nurl_print `  FAIL dispatch-passthrough\n` ) = fails + fails 1 ( json_free j ) }
        F → {}
    }

    // Declaring client → served.
    ( json_obj_set req_ok `params` ( params_with_id tid ) )
    ?? ( mcp_tasks_dispatch store req_ok id1 `tasks/get` ) {
        T j → {
            // `params` no longer carries `_meta`, so the gate must have
            // been consulted before it was replaced — re-declare below.
            ( json_free j )
        }
        F → { ( nurl_print `  FAIL dispatch-served\n` ) = fails + fails 1 }
    }

    // Non-declaring client issuing tasks/get → -32003.
    ( json_obj_set req_no `params` ( params_with_id tid ) )
    ?? ( mcp_tasks_dispatch store req_no id1 `tasks/get` ) {
        T j → {
            ? != ( resp_err_code j ) mcp_tasks_err_missing_capability {
                ( nurl_print `  FAIL dispatch-gate\n` ) = fails + fails 1
            } {}
            // …and it names the extension the client is missing.
            ?? ( json_obj_get j `error` ) {
                T e → {
                    ?? ( json_obj_get e `data` ) {
                        T d → {
                            ?? ( json_obj_get d `requiredCapabilities` ) {
                                T rc → {
                                    ?? ( json_obj_get rc `extensions` ) {
                                        T ex → {
                                            ? ( json_obj_has ex ( mcp_tasks_ext_id ) ) {} {
                                                ( nurl_print `  FAIL gate-ext\n` ) = fails + fails 1
                                            }
                                        }
                                        F → { ( nurl_print `  FAIL gate-extensions\n` ) = fails + fails 1 }
                                    }
                                }
                                F → { ( nurl_print `  FAIL gate-required\n` ) = fails + fails 1 }
                            }
                        }
                        F → { ( nurl_print `  FAIL gate-data\n` ) = fails + fails 1 }
                    }
                }
                F → { ( nurl_print `  FAIL gate-error\n` ) = fails + fails 1 }
            }
            ( json_free j )
        }
        F → { ( nurl_print `  FAIL dispatch-gate-none\n` ) = fails + fails 1 }
    }

    // ── subscriptions/listen task ids ──
    : Json ids_arr ( json_arr_new )
    ( json_arr_push ids_arr ( json_str_lit `aaa` ) )
    ( json_arr_push ids_arr ( json_str_lit `bbb` ) )
    : Json notifs ( json_obj_new )
    ( json_obj_set notifs `taskIds` ids_arr )
    : Json listen ( json_obj_new )
    ( json_obj_set listen `notifications` notifs )
    : ( Vec String ) want ( mcp_tasks_listen_ids listen )
    ? != ( vec_len [String] want ) 2 {
        ( nurl_print `  FAIL listen-count\n` ) = fails + fails 1
    } {}
    ( json_free listen )
    : Json ack ( mcp_tasks_subscribed_notification want )
    ? != 0 ( nurl_str_eq ( jstr ack `method` ) `notifications/subscriptions/acknowledged` ) {} {
        ( nurl_print `  FAIL ack-method\n` ) = fails + fails 1
    }
    ( json_free ack )
    // No `notifications` member at all → empty list, no crash.
    : Json empty_listen ( json_obj_new )
    : ( Vec String ) none ( mcp_tasks_listen_ids empty_listen )
    ? != ( vec_len [String] none ) 0 {
        ( nurl_print `  FAIL listen-empty\n` ) = fails + fails 1
    } {}
    ( vec_free [String] none )
    ( json_free empty_listen )

    // ── TTL sweep ──
    // The store now holds tp (ttl 3600000), tp2 and tp3 (both unlimited).
    : s tp4 ( mcp_task_create store `tools/call` `short` ( json_obj_new ) 0 0 )
    : String held4 ( string_from ( mcp_task_id tp4 ) )
    ? != ( mcp_task_store_count store ) 4 {
        ( nurl_print `  FAIL sweep-before\n` ) = fails + fails 1
    } {}
    // A `now` far past every finite deadline: tp and tp4 go, the two
    // unlimited ones stay. Terminal status is irrelevant — only the TTL is.
    ? != ( mcp_task_store_sweep store 99999999999999 ) 2 {
        ( nurl_print `  FAIL sweep-count\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_store_count store ) 2 {
        ( nurl_print `  FAIL sweep-remaining\n` ) = fails + fails 1
    } {}
    // A swept id reads as unknown.
    : Json p_gone ( params_with_id ( string_data held4 ) )
    : Json g7 ( mcp_tasks_handle_get store id1 p_gone )
    ? != ( resp_err_code g7 ) mcp_err_invalid_params {
        ( nurl_print `  FAIL sweep-get\n` ) = fails + fails 1
    } {}
    ( json_free g7 )
    ( json_free p_gone )
    ( string_free held4 )

    // An unlimited-TTL task must survive any sweep.
    : s tp5 ( mcp_task_create store `tools/call` `forever` ( json_obj_new ) -1 0 )
    ? != ( mcp_task_store_sweep store 99999999999999 ) 0 {
        ( nurl_print `  FAIL sweep-unlimited\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_store_count store ) 3 {
        ( nurl_print `  FAIL sweep-unlimited-count\n` ) = fails + fails 1
    } {}

    ( json_free p_get )
    ( string_free held )
    ( json_free req_ok )
    ( json_free req_no )
    ( json_free id1 )
    ( mcp_task_store_free store )

    ? == fails 0 { ( nurl_print `mcp_tasks: all checks PASS\n` ) }
    { ( nurl_print `mcp_tasks: FAILURES\n` ) }
    ^ fails
}
