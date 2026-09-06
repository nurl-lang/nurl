// mcp_test.nu — the MCP surface, golden-tested through router_handle:
//
//   transport — OPTIONS preflight, initialize, tools/list, tools/call.
//   simple    — with authentication off every tool is on the list and the
//               protected-resource metadata is a 404: nothing to sign in to.
//   reading   — list_models, anomalies, anomaly_summary, points, point,
//               calibration answer over a model fed through the API.
//   scratch   — fork_model builds an llm_… model; delete_model insists on
//               confirm=true and then removes it.
//   oidc      — a call with no credential gets the 401 challenge that
//               names the metadata document, and that document names the
//               issuer; an ingest key sees the member and ingest tools but
//               none of the organisation's, is refused on a production
//               model and not on its own llm_…; an admin key sees it all.
//               (A viewer is a person with a token, not a key: the viewer
//               path runs in tests/authflow_test.sh against a provider.)
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_mcp_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`
$ `src/authz.nu`
$ `src/service.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( pline label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( pline label )
        = g_fail + g_fail 1
    }
}

@ streq s a s b → b { ^ == ( nurl_str_eq a b ) 1 }

// A request with an optional API key header. The MCP handler replays the
// credential it received into the API it calls, so the header on the
// outer request is what every tool acts with.
@ mk_req s method s path s query s body s key → HttpRequest {
    : ( Vec Header ) hs ( vec_new [Header] )
    ? > ( nurl_str_len key ) 0 { ( vec_push [Header] hs ( header_new `X-API-Key` key ) ) } {}
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( string_from `HTTP/1.1` )
        hs
        ( bytes_from_str body )
    }
}

// One response: status, parsed body (JNull when not JSON), and the
// WWW-Authenticate header if there was one.
: Out {
    i status
    Json body
    String www
}

@ out_free Out o → v {
    ( json_free . o body )
    ( string_free . o www )
}

@ fire Router r s method s path s query s body s key → Out {
    : HttpRequest req ( mk_req method path query body key )
    : HttpResponse resp ( router_handle r req )
    : i status . resp status
    : String txt ( bytes_to_str . resp body )
    : ~ Json parsed ( json_null )
    ?? ( json_parse ( string_data txt ) ) {
        T j → { ( json_free parsed ) = parsed j }
        F _ → {}
    }
    : ~ String www ( string_new )
    ?? ( header_get . resp headers `www-authenticate` ) {
        T v → { ( string_free www ) = www v }
        F → {}
    }
    ( string_free txt )
    ( http_response_free resp )
    ( request_free req )
    ^ @ Out { status parsed www }
}

// A JSON-RPC request to /mcp. `params` is JSON text.
@ rpc Router r s method s params s key → Out {
    : String body ( string_from `{"jsonrpc":"2.0","id":7,"method":"` )
    ( string_push_str body method )
    ( string_push_str body `","params":` )
    ( string_push_str body params )
    ( string_push_str body `}` )
    : Out o ( fire r `POST` `/mcp` `` ( string_data body ) key )
    ( string_free body )
    ^ o
}

// The `result` object of a JSON-RPC reply, or JNull.
@ rpc_result Json body → Json {
    ?? ( json_obj_get body `result` ) {
        T v → { ^ v }
        F _ → { ^ ( json_null ) }
    }
}

// Does the tools/list reply name this tool?
@ tools_has Json body s name → b {
    : Json res ( rpc_result body )
    ?? ( json_obj_get res `tools` ) {
        T ts → {
            : i n ( json_arr_len ts )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get ts k ) {
                    T t → {
                        ?? ( json_obj_get t `name` ) {
                            T nm → { ? ( streq ( json_as_str nm ) name ) { ^ T } {} }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ^ F
        }
        F _ → { ^ F }
    }
}

@ tools_count Json body → i {
    : Json res ( rpc_result body )
    ?? ( json_obj_get res `tools` ) {
        T ts → { ^ ( json_arr_len ts ) }
        F _ → { ^ -1 }
    }
}

// What a tool call came back with: the text of the first content block,
// that text parsed as JSON when it is JSON, and whether it was an error.
: Call {
    b ok
    String text
    Json data
}

@ call_free Call c → v {
    ( string_free . c text )
    ( json_free . c data )
}

@ call Router r s tool s args s key → Call {
    : String params ( string_from `{"name":"` )
    ( string_push_str params tool )
    ( string_push_str params `","arguments":` )
    ( string_push_str params args )
    ( string_push_str params `}` )
    : Out o ( rpc r `tools/call` ( string_data params ) key )
    ( string_free params )
    : ~ b ok F
    : ~ String text ( string_new )
    : ~ Json data ( json_null )
    ? == . o status 200 {
        : Json res ( rpc_result . o body )
        : ~ b is_err T
        ?? ( json_obj_get res `isError` ) {
            T e → { = is_err ( json_as_bool e ) }
            F _ → {}
        }
        = ok ! is_err
        ?? ( json_obj_get res `content` ) {
            T cs → {
                ?? ( json_arr_get cs 0 ) {
                    T c0 → {
                        ?? ( json_obj_get c0 `text` ) {
                            T t → {
                                ( string_free text )
                                = text ( string_from ( json_as_str t ) )
                                ?? ( json_parse ( string_data text ) ) {
                                    T j → { ( json_free data ) = data j }
                                    F _ → {}
                                }
                            }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
    } {}
    ( out_free o )
    ^ @ Call { ok text data }
}

@ jint_of Json o s key → i {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( json_as_int e ) }
        F _ → { ^ -1 }
    }
}

@ jstr_eq Json o s key s want → b {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( streq ( json_str_data e ) want ) }
        F _ → { ^ F }
    }
}

// Is the field under `key` an object?
@ jobj_at Json o s key → b {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( json_is_obj e ) }
        F _ → { ^ F }
    }
}

@ jf_of Json o s key → f {
    ?? ( json_obj_get o key ) {
        T e → {
            ?? ( json_num_as_f e ) {
                T x → { ^ x }
                F _ → { ^ -1.0 }
            }
        }
        F _ → { ^ -1.0 }
    }
}

@ jarr_len Json o s key → i {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( json_arr_len e ) }
        F _ → { ^ -1 }
    }
}

// Feed a model N points through the API, with one obvious outlier near the
// end so a scan has something to flag.
@ feed Router r s model i n s key → v {
    : String path ( string_from `/detect/` )
    ( string_push_str path model )
    : ~ i k 1
    ~ <= k n {
        : String body ( string_from `{"temp": ` )
        ? == k - n 3 { ( string_push_str body `99` ) } {
            ( string_push_str body `2` )
            ( string_push_int body % k 10 )
            ( string_push_str body `.5` )
        }
        ( string_push_str body `, "load": 1.` )
        ( string_push_int body % k 7 )
        ( string_push_str body `}` )
        : Out o ( fire r `POST` ( string_data path ) `` ( string_data body ) key )
        ( out_free o )
        ( string_free body )
        = k + k 1
    }
    ( string_free path )
}

// ── Simple mode: no sign-in, every tool ─────────────────────────────────

@ test_transport Router r → v {
    : Out pre ( fire r `OPTIONS` `/mcp` `` `` `` )
    ( check == . pre status 204 `mcp: OPTIONS /mcp -> 204 preflight` )
    ( out_free pre )

    : Out md ( fire r `GET` `/.well-known/oauth-protected-resource/mcp` `` `` `` )
    ( check == . md status 404 `mcp: no protected-resource metadata while sign-in is off` )
    ( out_free md )

    : Out ini ( rpc r `initialize` `{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}` `` )
    ( check == . ini status 200 `mcp: initialize -> 200` )
    : Json res ( rpc_result . ini body )
    : ~ b named F
    : ~ b instructed F
    ?? ( json_obj_get res `serverInfo` ) {
        T si → { = named ( jstr_eq si `name` `anomaly` ) }
        F _ → {}
    }
    ?? ( json_obj_get res `instructions` ) {
        T ins → { = instructed > ( nurl_str_len ( json_as_str ins ) ) 100 }
        F _ → {}
    }
    ( check named `mcp: the server calls itself anomaly` )
    ( check instructed `mcp: initialize carries instructions for the agent` )
    ( out_free ini )

    : Out ls ( rpc r `tools/list` `{}` `` )
    ( check == . ls status 200 `mcp: tools/list -> 200` )
    ( check ( tools_has . ls body `list_models` ) `mcp: list_models is a tool` )
    ( check ( tools_has . ls body `anomalies` ) `mcp: anomalies is a tool` )
    ( check ( tools_has . ls body `fork_model` ) `mcp: fork_model is a tool` )
    ( check ( tools_has . ls body `ingest_point` ) `mcp: sign-in off = admin: ingest_point listed` )
    ( check ( tools_has . ls body `set_role` ) `mcp: sign-in off = admin: set_role listed` )
    ( check ( tools_has . ls body `org_keys` ) `mcp: sign-in off = admin: org_keys listed` )
    ( check == ( tools_count . ls body ) 26 `mcp: every one of the 26 tools is listed` )
    ( out_free ls )

    // A tool that does not exist is refused in the tool-result envelope.
    : Call nope ( call r `no_such_tool` `{}` `` )
    ( check ! . nope ok `mcp: an unknown tool is an error` )
    ( check ( string_contains . nope text `unknown tool` ) `mcp: and says so` )
    ( call_free nope )
}

@ test_reading Router r → v {
    ( feed r `pub` 61 `` )

    : Call who ( call r `whoami` `{}` `` )
    ( check . who ok `mcp: whoami answers` )
    ( check ( jstr_eq . who data `role` `admin` ) `mcp: sign-in off: whoami says admin` )
    ( check ( jstr_eq . who data `scratch_prefix` `llm_` ) `mcp: whoami names the scratch prefix` )
    ( check > ( jarr_len . who data `may` ) 2 `mcp: whoami lists what the role may do` )
    ( call_free who )

    : Call lm ( call r `list_models` `{}` `` )
    ( check . lm ok `mcp: list_models answers` )
    ( check == ( jint_of . lm data `count` ) 1 `mcp: list_models counts the one model` )
    : ~ b saw F
    ?? ( json_obj_get . lm data `models` ) {
        T ms → {
            ?? ( json_arr_get ms 0 ) {
                T m0 → {
                    = saw & ( jstr_eq m0 `name` `pub` ) & == ( jarr_len m0 `columns` ) 2 == ( jint_of m0 `n_points_seen` ) 61
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check saw `mcp: the brief has name, columns and points seen` )
    ( call_free lm )

    : Call dm ( call r `describe_model` `{"model":"pub"}` `` )
    ( check . dm ok `mcp: describe_model answers` )
    ( check ( jstr_eq . dm data `model_name` `pub` ) `mcp: describe_model names the model` )
    ( check > ( jarr_len . dm data `editable_fields` ) 0 `mcp: describe_model says what edit_model may change` )
    ( call_free dm )

    : Call miss ( call r `describe_model` `{}` `` )
    ( check ! . miss ok `mcp: a missing model argument is an error` )
    ( check ( string_contains . miss text `list_models` ) `mcp: that points at list_models` )
    ( call_free miss )

    : Call gone ( call r `describe_model` `{"model":"nosuch"}` `` )
    ( check ! . gone ok `mcp: an unknown model is an error` )
    ( check ( string_contains . gone text `404` ) `mcp: carrying the API's status` )
    ( call_free gone )

    : Call an ( call r `anomalies` `{"model":"pub","count":5}` `` )
    ( check . an ok `mcp: anomalies answers` )
    ( check == ( jint_of . an data `points_stored` ) 61 `mcp: anomalies reports the points stored` )
    ( check == ( jint_of . an data `points_in_window` ) 61 `mcp: no window = everything stored` )
    ( check >= ( jint_of . an data `anomalies_in_window` ) 1 `mcp: the outlier is flagged` )
    ( check <= ( jarr_len . an data `rows` ) 5 `mcp: count caps the rows` )
    ( check == ( jarr_len . an data `rows` ) ( jint_of . an data `returned` ) `mcp: returned counts the rows` )
    : ~ b row_ok F
    ?? ( json_obj_get . an data `rows` ) {
        T rows → {
            ?? ( json_arr_get rows 0 ) {
                T r0 → {
                    : ~ b has_vals F
                    ?? ( json_obj_get r0 `values` ) {
                        T vs → { = has_vals ( json_is_obj vs ) }
                        F _ → {}
                    }
                    = row_ok & >= ( jint_of r0 `index` ) 0 & has_vals ( json_is_obj r0 )
                }
                F _ → {}
            }
        }
        F _ → { ( check F `mcp: anomalies has rows` ) }
    }
    ( check row_ok `mcp: a row carries its index and every value` )
    ( call_free an )

    : Call all ( call r `anomalies` `{"model":"pub","all_points":true,"count":200}` `` )
    ( check . all ok `mcp: anomalies all_points answers` )
    ( check == ( jarr_len . all data `rows` ) 61 `mcp: all_points lists every row` )
    ( call_free all )

    : Call bad ( call r `anomalies` `{"model":"pub","last":"yesterdayish"}` `` )
    ( check ! . bad ok `mcp: an unreadable window is an error` )
    ( call_free bad )

    : Call su ( call r `anomaly_summary` `{"model":"pub","buckets":4}` `` )
    ( check . su ok `mcp: anomaly_summary answers` )
    ( check == ( jint_of . su data `points_in_window` ) 61 `mcp: summary counts the points` )
    ( check >= ( jint_of . su data `anomalies_in_window` ) 1 `mcp: summary counts the anomalies` )
    ( check <= ( jarr_len . su data `timeline` ) 4 `mcp: the timeline has at most the buckets asked` )
    ( check > ( jf_of . su data `anomaly_rate` ) 0.0 `mcp: summary has an anomaly rate` )
    : ~ b worst_ok F
    ?? ( json_obj_get . su data `worst` ) {
        T w → { = worst_ok >= ( jint_of w `index` ) 0 }
        F _ → {}
    }
    ( check worst_ok `mcp: summary names the worst anomaly by index` )
    ( check ( jobj_at . su data `by_version` ) `mcp: summary counts per version` )
    ( call_free su )

    : Call pt ( call r `points` `{"model":"pub","count":3}` `` )
    ( check . pt ok `mcp: points answers` )
    ( check == ( jarr_len . pt data `rows` ) 3 `mcp: points returns count rows` )
    ( check == ( jint_of . pt data `points_stored` ) 61 `mcp: points reports the points stored` )
    : ~ i idx -1
    ?? ( json_obj_get . pt data `rows` ) {
        T rows → {
            ?? ( json_arr_get rows 0 ) {
                T r0 → { = idx ( jint_of r0 `index` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check >= idx 0 `mcp: a points row carries its ring index` )
    ( call_free pt )

    : String pargs ( string_from `{"model":"pub","index":` )
    ( string_push_int pargs idx )
    ( string_push_str pargs `}` )
    : Call one ( call r `point` ( string_data pargs ) `` )
    ( string_free pargs )
    ( check . one ok `mcp: point answers for that index` )
    ( check ( jstr_eq . one data `model_name` `pub` ) `mcp: point names the model` )
    ( check ( jobj_at . one data `point` ) `mcp: point carries the row` )
    ?? ( json_obj_get . one data `point` ) {
        T prow → {
            ( check ( jobj_at prow `values` ) `mcp: the row keeps its columns under values` )
            ( check ! ( jobj_at prow `temp` ) `mcp: and not beside index and time` )
        }
        F _ → {}
    }
    ( call_free one )

    : Call far ( call r `point` `{"model":"pub","index":100000}` `` )
    ( check ! . far ok `mcp: point past the ring is an error` )
    ( check ( string_contains . far text `holds 61 points` ) `mcp: that says how many points there are` )
    ( call_free far )

    : Call ca ( call r `calibration` `{"model":"pub"}` `` )
    ( check . ca ok `mcp: calibration answers` )
    ( check ( jobj_at . ca data `versions` ) `mcp: calibration has the versions` )
    ( check ( jobj_at . ca data `aggregate` ) `mcp: calibration has the aggregate` )
    ( call_free ca )

    : Call sc ( call r `score_point` `{"model":"pub","values":{"temp":99,"load":44}}` `` )
    ( check . sc ok `mcp: score_point answers` )
    ( check ( string_contains . sc text `anomaly` ) `mcp: score_point carries a verdict` )
    ( check ( jobj_at . sc data `versions` ) `mcp: score_point lists the versions` )
    ( check ( json_obj_has . sc data `severity` ) `mcp: score_point carries the severity` )
    ( check ! ( json_obj_has . sc data `data_point` ) `mcp: score_point does not echo the values` )
    ?? ( json_obj_get . sc data `versions` ) {
        T svs → {
            ?? ( json_obj_get svs `short_term` ) {
                T svv → { ( check ( jobj_at svv `threshold_info` ) `mcp: score_point versions carry threshold_info` ) }
                F _ → { ( check F `mcp: score_point has short_term` ) }
            }
        }
        F _ → {}
    }
    : Call va ( call r `anomalies` `{"model":"pub","min_votes":2,"all_points":true}` `` )
    ( check . va ok `mcp: anomalies takes min_votes` )
    ( call_free va )
    ( call_free sc )
}

// The `weekly` version of `model` as describe_model shows it: its
// window_minutes, n_estimators and enabled flag (−1 / F when absent).
: Weekly {
    i wmin
    i est
    b en
}

@ weekly_of Router r s model → Weekly {
    : String args ( string_from `{"model":"` )
    ( string_push_str args model )
    ( string_push_str args `"}` )
    : Call dm ( call r `describe_model` ( string_data args ) `` )
    ( string_free args )
    : ~ i wmin -1
    : ~ i est -1
    : ~ b en F
    ?? ( json_obj_get . dm data `versions` ) {
        T vs → {
            ?? ( json_obj_get vs `weekly` ) {
                T w → {
                    = wmin ( jint_of w `window_minutes` )
                    = est ( jint_of w `n_estimators` )
                    ?? ( json_obj_get w `enabled` ) { T e → { = en ( json_as_bool e ) } F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( call_free dm )
    ^ @ Weekly { wmin est en }
}

@ test_scratch Router r → v {
    : Call noname ( call r `fork_model` `{"source":"pub"}` `` )
    ( check ! . noname ok `mcp: fork_model needs a name` )
    ( check ( string_contains . noname text `llm_` ) `mcp: and suggests the scratch prefix` )
    ( call_free noname )

    // Give the source a configuration of its own: the fork must carry it.
    : Call cfg ( call r `edit_model` `{"model":"pub","patch":{"versions":{"weekly":{"n_estimators":123,"enabled":false}}}}` `` )
    ( check . cfg ok `mcp: the source's weekly version is edited` )
    ( call_free cfg )

    : Call fk ( call r `fork_model` `{"source":"pub","name":"llm_fork","fields":["temp"]}` `` )
    ( check . fk ok `mcp: fork_model builds a scratch model` )
    ( check ( jstr_eq . fk data `model_name` `llm_fork` ) `mcp: fork names the new model` )
    ( check ( jstr_eq . fk data `source` `pub` ) `mcp: fork names its source` )
    ( check == ( jarr_len . fk data `fields` ) 1 `mcp: fork kept the one field asked` )
    ( check > ( jint_of . fk data `points` ) 50 `mcp: fork trained on the slice` )
    ( check ( string_contains . fk text `delete_model when done` ) `mcp: fork tells what comes next` )
    ( call_free fk )

    : Weekly fw ( weekly_of r `llm_fork` )
    ( check == . fw est 123 `mcp: the fork inherits the source's version configuration` )
    ( check ! . fw en `mcp: a version disabled on the source is disabled on the fork` )
    ( check == . fw wmin 10080 `mcp: whole-slice training leaves the version's window as configured` )

    : Call lm ( call r `list_models` `{}` `` )
    ( check == ( jint_of . lm data `count` ) 2 `mcp: list_models now counts two` )
    ( call_free lm )

    : Call dm ( call r `describe_model` `{"model":"llm_fork"}` `` )
    : ~ b scratch F
    ?? ( json_obj_get . dm data `scratch` ) {
        T v → { = scratch ( json_as_bool v ) }
        F _ → {}
    }
    ( check scratch `mcp: describe_model marks it scratch` )
    ( call_free dm )

    : Call ft ( call r `finetune` `{"model":"llm_fork","rate":0.05,"dry_run":true}` `` )
    ( check . ft ok `mcp: finetune dry_run answers` )
    ( check ( jobj_at . ft data `versions` ) `mcp: finetune reports the versions` )
    ( check ( jobj_at . ft data `window` ) `mcp: finetune reports the window` )
    ( check ! ( json_obj_has . ft data `adjusted_margins` ) `mcp: finetune drops the legacy margin map` )
    ( call_free ft )
    : Call fta ( call r `finetune` `{"model":"llm_fork","rate":0.05,"dry_run":true,"last":"all"}` `` )
    ( check . fta ok `mcp: finetune takes last=all` )
    ( call_free fta )

    : Call ed ( call r `edit_model` `{"model":"llm_fork","patch":{"alias":"forked"}}` `` )
    ( check . ed ok `mcp: edit_model applies a patch` )
    ( check ( string_contains . ed text `forked` ) `mcp: and echoes the new alias` )
    ( call_free ed )

    : Call nc ( call r `delete_model` `{"model":"llm_fork"}` `` )
    ( check ! . nc ok `mcp: delete_model without confirm is refused` )
    ( check ( string_contains . nc text `confirm` ) `mcp: and asks for confirm` )
    ( call_free nc )

    : Call rs ( call r `reset_model` `{"model":"llm_fork","confirm":false}` `` )
    ( check ! . rs ok `mcp: reset_model with confirm=false is refused` )
    ( call_free rs )

    : Call dl ( call r `delete_model` `{"model":"llm_fork","confirm":true}` `` )
    ( check . dl ok `mcp: delete_model with confirm removes it` )
    ( call_free dl )

    : Call lm2 ( call r `list_models` `{}` `` )
    ( check == ( jint_of . lm2 data `count` ) 1 `mcp: and the listing is back to one` )
    ( call_free lm2 )
}

// ── OIDC mode: the challenge, the metadata, and three roles ─────────────

: Keys {
    String admin
    String ingest
}

// The two kinds of key an organisation issues. There is no viewer key: a
// machine that only reads is pointless, so a viewer is always a person.
@ mk_keys → Keys {
    : ~ String a ( string_new )
    : ~ String g ( string_new )
    ?? ( az_db_open `orgM` ) {
        F _ → { ( check F `mcp: orgM opens` ) }
        T db → {
            : String r1 ( az_user_touch db `boss` `b@m` `Boss` T0 )
            ( string_free r1 )
            : KeyIssue ka ( az_key_create db `boss` `agent-admin` AZ_ROLE_ADMIN T0 )
            : KeyIssue kg ( az_key_create db `boss` `feed` AZ_ROLE_INGEST T0 )
            ( string_free a ) = a ( string_from ( string_data . ka secret ) )
            ( string_free g ) = g ( string_from ( string_data . kg secret ) )
            ( key_issue_free ka )
            ( key_issue_free kg )
        }
    }
    ^ @ Keys { a g }
}

@ test_oidc Router r → v {
    ( anomaly_authz_configure T F `https://id.example/organizations/v2.0` `cid` `api://cid` )
    ( check ( anomaly_authz_enabled ) `mcp: sign-in on` )

    // No credential: the challenge an MCP client follows to sign in.
    : Out anon ( rpc r `tools/list` `{}` `` )
    ( check == . anon status 401 `mcp: no credential -> 401` )
    ( check ( string_starts_with . anon www `Bearer resource_metadata="` ) `mcp: WWW-Authenticate points at the resource metadata` )
    ( check ( string_contains . anon www `/.well-known/oauth-protected-resource/mcp"` ) `mcp: at the /mcp-scoped document` )
    ( check ( jstr_eq . anon body `error` `unauthorized` ) `mcp: the body says unauthorized` )
    ( out_free anon )

    // A credential that does not verify says why.
    : Out badtok ( fire r `POST` `/mcp` `` `{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}` `anok_nosuch_key` )
    ( check == . badtok status 401 `mcp: a bad key -> 401` )
    ( check ( string_contains . badtok www `error="invalid_token"` ) `mcp: named invalid_token` )
    ( out_free badtok )

    // The metadata document, at both paths.
    : Out md ( fire r `GET` `/.well-known/oauth-protected-resource/mcp` `` `` `` )
    ( check == . md status 200 `mcp: protected-resource metadata -> 200` )
    : ~ b iss F
    ?? ( json_obj_get . md body `authorization_servers` ) {
        T as → {
            ?? ( json_arr_get as 0 ) {
                T a0 → { = iss ( streq ( json_as_str a0 ) `https://id.example/organizations/v2.0` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check iss `mcp: it names the issuer as the authorization server` )
    : ~ b res F
    ?? ( json_obj_get . md body `resource` ) {
        T rv → {
            : String rs ( string_from ( json_as_str rv ) )
            = res ( string_ends_with rs `/mcp` )
            ( string_free rs )
        }
        F _ → {}
    }
    ( check res `mcp: the resource is the /mcp endpoint` )
    : ~ b scope F
    ?? ( json_obj_get . md body `scopes_supported` ) {
        T ss → {
            ?? ( json_arr_get ss 0 ) {
                T s0 → { = scope ( streq ( json_as_str s0 ) `api://cid/access_as_user` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check scope `mcp: the scope is the audience's access_as_user` )
    ( out_free md )
    : Out md2 ( fire r `GET` `/.well-known/oauth-protected-resource` `` `` `` )
    ( check == . md2 status 200 `mcp: the unscoped metadata path answers too` )
    ( out_free md2 )

    : Keys ks ( mk_keys )
    : s GK ( string_data . ks ingest )
    : s AK ( string_data . ks admin )

    // What each key is shown.
    : Out gl ( rpc r `tools/list` `{}` GK )
    ( check == . gl status 200 `mcp: an ingest key is admitted` )
    ( check ( tools_has . gl body `list_models` ) `mcp: ingest sees list_models` )
    ( check ( tools_has . gl body `anomalies` ) `mcp: ingest sees anomalies` )
    ( check ( tools_has . gl body `fork_model` ) `mcp: ingest sees fork_model (scratch models)` )
    ( check ( tools_has . gl body `delete_model` ) `mcp: ingest sees delete_model (its own scratch)` )
    ( check ( tools_has . gl body `ingest_point` ) `mcp: ingest sees ingest_point` )
    ( check ( tools_has . gl body `import_data` ) `mcp: and import_data` )
    ( check ! ( tools_has . gl body `set_role` ) `mcp: ingest does not see set_role` )
    ( check ! ( tools_has . gl body `org_keys` ) `mcp: ingest does not see org_keys` )
    ( check ! ( tools_has . gl body `org_users` ) `mcp: ingest does not see org_users` )
    ( check ! ( tools_has . gl body `claim_model` ) `mcp: ingest does not see claim_model` )
    ( check == ( tools_count . gl body ) 22 `mcp: 22 tools for an ingest key` )
    ( out_free gl )

    : Out al ( rpc r `tools/list` `{}` AK )
    ( check == ( tools_count . al body ) 26 `mcp: an admin key sees every tool` )
    ( out_free al )

    // An invisible tool called by name is unknown to that caller.
    : Call hid ( call r `set_role` `{"subject":"boss","role":"viewer"}` GK )
    ( check ! . hid ok `mcp: ingest calling set_role is refused` )
    ( check ( string_contains . hid text `unknown tool` ) `mcp: as an unknown tool` )
    ( call_free hid )

    // A production model, fed by the ingest key: the organisation's.
    ( feed r `prod` 61 GK )

    : Call gwho ( call r `whoami` `{}` GK )
    ( check . gwho ok `mcp: ingest whoami answers` )
    ( check ( jstr_eq . gwho data `role` `ingest` ) `mcp: and says ingest` )
    ( check ( jstr_eq . gwho data `organization` `orgM` ) `mcp: in orgM` )
    ( check ( string_contains . gwho text `NOT change or delete models outside llm_` ) `mcp: whoami says what it may not do` )
    ( call_free gwho )

    : Call glm ( call r `list_models` `{}` GK )
    ( check . glm ok `mcp: ingest list_models answers` )
    ( check == ( jint_of . glm data `count` ) 1 `mcp: it sees the organisation's model` )
    ( check ( jstr_eq . glm data `organization` `orgM` ) `mcp: the listing names the organisation` )
    ( call_free glm )

    : Call gan ( call r `anomalies` `{"model":"prod","count":3}` GK )
    ( check . gan ok `mcp: ingest reads the organisation's anomalies` )
    ( check == ( jint_of . gan data `points_stored` ) 61 `mcp: all 61 points are there` )
    ( call_free gan )

    : Call gip ( call r `ingest_point` `{"model":"prod","values":{"temp":23.5,"load":1.2}}` GK )
    ( check . gip ok `mcp: ingest_point stores a point` )
    ( check ( string_contains . gip text `anomaly` ) `mcp: and answers with the verdict` )
    ( call_free gip )

    : Call grt ( call r `retrain` `{"model":"prod"}` GK )
    ( check ! . grt ok `mcp: ingest may not retrain a production model` )
    ( check ( string_contains . grt text `403` ) `mcp: refused with the API's 403` )
    ( check ( string_contains . grt text `llm_` ) `mcp: and the refusal explains the scratch rule` )
    ( call_free grt )

    // Bringing a model into being is the ingest capability, whatever the
    // name — but what it brought into being outside llm_… is production,
    // and production it may not touch again.
    : Call gfk_prod ( call r `fork_model` `{"source":"prod","name":"prod2"}` GK )
    ( check . gfk_prod ok `mcp: ingest may fork onto a production name (creating is its capability)` )
    ( call_free gfk_prod )
    : Call grt_p2 ( call r `retrain` `{"model":"prod2"}` GK )
    ( check ! . grt_p2 ok `mcp: but may not retrain what it created there` )
    ( call_free grt_p2 )

    : Call gfk ( call r `fork_model` `{"source":"prod","name":"llm_mine"}` GK )
    ( check . gfk ok `mcp: ingest forks a scratch model` )
    ( check ( jstr_eq . gfk data `model_name` `llm_mine` ) `mcp: named llm_mine` )
    ( call_free gfk )

    : Call glm2 ( call r `list_models` `{}` GK )
    ( check == ( jint_of . glm2 data `count` ) 3 `mcp: the scratch model is the organisation's too` )
    ( call_free glm2 )

    : Call grt2 ( call r `retrain` `{"model":"llm_mine"}` GK )
    ( check . grt2 ok `mcp: ingest retrains its scratch model` )
    ( call_free grt2 )

    : Call gae ( call r `train_autoencoder` `{"model":"llm_mine"}` GK )
    ( check . gae ok `mcp: ingest trains its scratch model's autoencoder` )
    ( call_free gae )

    // The admin sees it, and may touch production.
    : Call adm ( call r `describe_model` `{"model":"llm_mine"}` AK )
    ( check . adm ok `mcp: admin sees the scratch model` )
    ( call_free adm )
    : Call art ( call r `retrain` `{"model":"prod"}` AK )
    ( check . art ok `mcp: admin retrains a production model` )
    ( call_free art )
    : Call ausers ( call r `org_users` `{}` AK )
    ( check . ausers ok `mcp: admin lists the organisation's members` )
    ( check ( string_contains . ausers text `boss` ) `mcp: and finds boss among them` )
    ( call_free ausers )
    : Call akeys ( call r `org_keys` `{}` AK )
    ( check . akeys ok `mcp: admin lists the organisation's keys` )
    ( check ( string_contains . akeys text `agent-admin` ) `mcp: by label` )
    ( check ! ( string_contains . akeys text GK ) `mcp: never a secret` )
    ( call_free akeys )

    // The scratch model is cleaned up by whoever made it; production is not.
    : Call gdel_prod ( call r `delete_model` `{"model":"prod","confirm":true}` GK )
    ( check ! . gdel_prod ok `mcp: ingest may not delete a production model` )
    ( call_free gdel_prod )
    : Call gdel ( call r `delete_model` `{"model":"llm_mine","confirm":true}` GK )
    ( check . gdel ok `mcp: ingest deletes its scratch model` )
    ( call_free gdel )
    : Call glm3 ( call r `list_models` `{}` GK )
    ( check == ( jint_of . glm3 data `count` ) 2 `mcp: and it is gone from the listing` )
    ( call_free glm3 )
    : Call adel ( call r `delete_model` `{"model":"prod2","confirm":true}` AK )
    ( check . adel ok `mcp: admin deletes the production fork` )
    ( call_free adel )

    // Metadata comes back to 404 once sign-in is off again.
    ( anomaly_authz_configure F T `` `` `` )
    : Out off ( fire r `GET` `/.well-known/oauth-protected-resource/mcp` `` `` `` )
    ( check == . off status 404 `mcp: metadata is gone with sign-in off` )
    ( out_free off )

    ( string_free . ks admin )
    ( string_free . ks ingest )
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_mcp_test` )
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    ( anomaly_service_set_root ( string_data root ) )
    ( anomaly_authz_set_root ( string_data root ) )
    : Router r ( anomaly_service_router )

    ( test_transport r )
    ( test_reading r )
    ( test_scratch r )
    ( test_oidc r )

    ( router_free r )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `mcp_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
