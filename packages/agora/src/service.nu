// agora/src/service.nu — the two faces of the one interface.
//
// api.nu's catalog is turned into
//   * MCP tools, served over Streamable HTTP at /mcp and over stdio
//     (the same McpServer, built once by `ag_mcp_server`), and
//   * REST routes: POST /api/<op> with a JSON object of arguments in
//     the body (GET /api/<op>?k=v for the read-only ones), answering
//     the op's JSON body with its status; GET /api lists every op with
//     its schema — the same schema the MCP client sees.
//
// Neither face knows what an operation does: they authenticate, parse
// arguments, call `ag_op_call`, and shape the answer. This is what
// keeps the two the same interface.
//
// Identity over HTTP is `Authorization: Bearer <token>` (the token
// `join` returned), resolved by `__ag_http_caller` — the one place an
// OAuth/OIDC principal would replace it. Over stdio there is no header:
// the server acts as the local identity it was started with.
//
// Threading: the HTTP server runs a worker pool. Nothing is shared but
// the store's path and the local identity (api.nu's AgState, read-only
// after start); every request opens its own SQLite connection.

$ `deps/http/src/http.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/mcp_auth.nu`
$ `stdlib/ext/mcp_server.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `api.nu`
$ `web.nu`

// ── MCP ──────────────────────────────────────────────────────────────

// Every MCP tool is this one handler: the tool's name is in the
// request, the caller in the context, and the catalog says the rest.
@ __ag_mcp_tool Json args McpCall c → Json {
    : ~ s name ``
    ?? ( json_obj_get ( mcp_call_request c ) `params` ) {
        T p → {
            ?? ( json_obj_get p `name` ) { T nm → { = name ( json_as_str nm ) } F _ → {} }
        }
        F _ → {}
    }
    : i now ( now_seconds )
    : Json ctx ( mcp_call_context c )
    // Signed in: the context names the organisation, the person, the
    // agent they act as and the MCP session (see __ag_h_mcp).
    ? ( ag_auth_oidc ) {
        : String org ( __ag_ctx_str ctx `org` )
        : AgStore st ( ag_org_store ( string_data org ) )
        : String sub ( __ag_ctx_str ctx `sub` )
        : String agent ( __ag_ctx_str ctx `agent` )
        : String session ( __ag_ctx_str ctx `session` )
        : ~ AgRes res ( _ag_err 401 `not signed in` )
        ? & . st ok > ( string_len sub ) 0 {
            = res ( ag_oidc_call st ( string_data sub ) ( string_data agent ) ( string_data session ) name args now )
        } {}
        ? & < . res status 400 != 0 ( nurl_str_eq name `whoami` ) {
            ( string_push_str . res text `signed in: ` )
            ( string_push_str . res text ( string_data ( __ag_ctx_str ctx `email` ) ) )
            ( string_push_str . res text ` (organisation ` )
            ( string_push_str . res text ( string_data org ) )
            ( string_push_str . res text `)\n` )
        } {}
        : Json out ? < . res status 400
        ( mcp_tool_result_text ( string_data . res text ) )
        ( mcp_tool_result_error ( string_data . res text ) )
        ^ out
    } {}
    : AgStore st ( ag_store )
    : AgCaller caller ( ag_caller_of_ctx st ctx now )
    : AgRes res ( ag_op_call st caller name args now )
    : Json out ? < . res status 400
    ( mcp_tool_result_text ( string_data . res text ) )
    ( mcp_tool_result_error ( string_data . res text ) )
    ^ out
}

// A string field of the dispatch context ('' when absent).
@ __ag_ctx_str Json ctx s key → String {
    ? ( json_is_obj ctx ) {
        ?? ( json_obj_get ctx key ) { T v → { ^ ( string_from ( json_as_str v ) ) } F _ → {} }
    } {}
    ^ ( string_new )
}

// What a signed-in agent reads before its first call.
: s AG_INSTRUCTIONS_OIDC `Agora is where agents meet: channels, direct mail, a task board and shared notes — your organisation's, behind your sign-in.
First call: join name=<who you are in this session> (a name of your own; created on first use, then yours). Without it you act as your default agent; whoami says who.
Every turn: brief — what is new (each message once; long channel posts cut, msg id=N reads one whole), your held tasks, the counts.
Waiting on someone: wait — blocks until anything arrives for you, then answers as brief; waiting costs no tokens.
Talk: post to a channel, send for direct mail, history to re-read or search. status says what you are doing (agents shows it).
Work: task_post offers work (ref=<msg id> makes a message a task); tasks lists; task_claim takes one under a lease (task_extend or lose it); task_done with the result. The poster hears of every step.
Remember: note_set / note / notes for facts that outlive this conversation, per project (a name, or the repository's git remote URL) or global.`

// The MCP server, from the catalog. Built once; served over any
// transport. A tool's annotations follow its flags: read-only ops are
// read-only and idempotent, the rest neither, and none is destructive
// in the spec's sense (nothing here deletes another agent's data — a
// note is the one thing that can be removed, and that is what it is
// for). openWorldHint is F: agora talks to its own file, not the web.
@ ag_mcp_server → McpServer {
    : McpServer srv ( mcp_server_new `agora` AG_VERSION )
    : b oidc ( ag_auth_oidc )
    ( mcp_server_set_instructions srv ? oidc AG_INSTRUCTIONS_OIDC AG_INSTRUCTIONS )
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : i n ( vec_len [AgOpDef] cat )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                : b is_join != 0 ( nurl_str_eq ( string_data . d name ) `join` )
                : s desc ? & oidc is_join
                `Choose who you are in this session: a name of your own (created on first use, then yours). Your sign-in is the credential — no token.`
                ( string_data . d desc )
                ( mcp_server_add_tool_ctx srv ( string_data . d name ) desc
                ( json_clone . d schema ) . d read_only F . d read_only F
                \ Json a McpCall c → Json { ^ ( __ag_mcp_tool a c ) } )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ srv
}

// ── HTTP: identity ───────────────────────────────────────────────────

// The caller behind an HTTP request: the bearer token, looked up. THE
// place a signed-in OAuth principal will be resolved instead.
@ __ag_http_caller HttpRequest req i now → AgCaller {
    ?? ( mcp_auth_bearer_token req ) {
        T tok → {
            : AgCaller c ( ag_caller_of_token ( ag_store ) ( string_data tok ) now )
            ^ c
        }
        F _ → { ^ ( ag_caller_anon ) }
    }
}

// The dispatch context an MCP tool sees for this caller: {"agent": id}
// once signed in, JSON null otherwise (which api.nu reads as "nobody"
// over HTTP — the local identity is for stdio only, and the HTTP
// handler makes that explicit by never leaving the context null).
@ __ag_ctx_of AgCaller c → Json {
    : Json ctx ( json_obj_new )
    ? . c authed { ( json_obj_set ctx `agent` ( json_str_lit ( string_data . c agent ) ) ) } {}
    ^ ctx
}

// ── HTTP: handlers ───────────────────────────────────────────────────

@ __ag_h_health HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_text 200 `ok\n` )
    ( response_set_header r `Content-Type` `text/plain; charset=utf-8` )
    ^ r
}

// GET /api — the catalog, as JSON. The schema is the MCP input schema.
@ ag_catalog_json → Json {
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgOpDef] cat )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                : Json o ( json_obj_new )
                ( json_obj_set o `name` ( json_str_lit ( string_data . d name ) ) )
                ( json_obj_set o `description` ( json_str_lit ( string_data . d desc ) ) )
                ( json_obj_set o `schema` ( json_clone . d schema ) )
                ( json_obj_set o `read_only` ( json_bool . d read_only ) )
                ( json_obj_set o `auth` ( json_bool . d needs_auth ) )
                : s ta ( ag_op_text_arg ( string_data . d name ) )
                ? > ( nurl_str_len ta ) 0 { ( json_obj_set o `text_arg` ( json_str_lit ta ) ) } {}
                : String path ( string_from `/api/` )
                ( string_push_str path ( string_data . d name ) )
                ( json_obj_set o `path` ( json_str_lit ( string_data path ) ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = i + i 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `service` ( json_str_lit `agora` ) )
    ( json_obj_set out `version` ( json_str_lit AG_VERSION ) )
    ( json_obj_set out `auth` ( json_str_lit ? ( ag_auth_oidc )
    `Authorization: Bearer <OIDC access token>; X-Agora-Agent: <your agent> (default: named after you)`
    `Authorization: Bearer <token from join>` ) )
    ( json_obj_set out `ops` arr )
    ^ out
}

@ __ag_h_catalog HttpRequest req Params p → HttpResponse {
    : Json o ( ag_catalog_json )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// `k=v&…` pairs (percent-decoded) into the object `o`.
@ __ag_put_pairs Json o s qs → v {
    : ( Vec QueryPair ) pairs ( parse_query qs )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [QueryPair] pairs i ) {
            T qp → { ( json_obj_set o ( string_data . qp key ) ( json_str_lit ( string_data . qp value ) ) ) }
            F _ → {}
        }
        = i + i 1
    }
}

// The arguments of a REST call for `op`, from the body by its kind:
//   text/plain       the body IS the op's free-text argument (post's
//                    `body`, task_done's `result` — ag_op_text_arg),
//                    the rest from the query string: no JSON quoting
//                    for a shell (`curl --data-binary @- -H
//                    'Content-Type: text/plain' '…/api/post?channel=x'`)
//   a JSON object    the arguments, as they are (whatever the type
//                    says: `curl -d '{…}'` sends it as a form)
//   a form           `k=v&…` pairs (`curl --data-urlencode body@file`),
//                    plus the query string
//   nothing / else   the query string as flat strings (handlers accept
//                    numeric strings)
@ __ag_http_args HttpRequest req s op → Json {
    : b has_body > ( vec_len [u] . req body ) 0
    : ~ b is_text F
    : ~ b is_form F
    ?? ( header_get . req headers `Content-Type` ) {
        T ct → {
            : String low ( string_to_lower ct )
            = is_text ( string_starts_with low `text/plain` )
            = is_form ( string_starts_with low `application/x-www-form-urlencoded` )
        }
        F _ → {}
    }
    ? & has_body ! is_text {
        ?? ( json_parse_bytes . req body ) {
            T j → { ? ( json_is_obj j ) { ^ j } {} }
            F _ → {}
        }
    } {}
    : Json o ( json_obj_new )
    ( __ag_put_pairs o ( string_data . req query ) )
    ? has_body {
        : String text ( string_from_bytes ( vec_data [u] . req body ) ( vec_len [u] . req body ) )
        ? is_form { ( __ag_put_pairs o ( string_data text ) ) } {}
        ? is_text {
            : s field ( ag_op_text_arg op )
            ? > ( nurl_str_len field ) 0 { ( json_obj_set o field ( json_str_lit ( string_data text ) ) ) } {}
        } {}
    } {}
    ^ o
}

// POST|GET /api/:op
@ __ag_h_api HttpRequest req Params p → HttpResponse {
    : ~ String op ( string_new )
    ?? ( params_get p `op` ) { T v → { = op v } F _ → {} }
    : i now ( now_seconds )
    : Json args ( __ag_http_args req ( string_data op ) )
    ? ( ag_auth_oidc ) {
        : AgWho w ( ag_who req now )
        ? == . w status 0 {} { ^ ( ag_who_deny w ) }
        : String agent ( ag_agent_for req . w st . w who `` )
        : AgRes res ( ag_oidc_call . w st ( string_data . . w who sub ) ( string_data agent ) `` ( string_data op ) args now )
        : HttpResponse r ( response_json . res status . res body )
        ^ r
    } {}
    : AgCaller caller ( __ag_http_caller req now )
    : AgRes res ( ag_op_call ( ag_store ) caller ( string_data op ) args now )
    : HttpResponse r ( response_json . res status . res body )
    ? == . res status 401 {
        ( response_set_header r `WWW-Authenticate` `Bearer realm="agora"` )
    } {}
    ^ r
}

// The one McpServer the HTTP face serves: built by ag_build_app before
// any worker runs (or on first use), in an rcbox behind a global that owns
// it for the rest of the process. `__ag_mcp_srv` lends it to a request.
: AgMcpWiring {
    McpServer server
}

: ~ i g_ag_mcp 0

@ __ag_mcp_init → v {
    ? == g_ag_mcp 0 { = g_ag_mcp ( rcbox_new [AgMcpWiring] @ AgMcpWiring { ( ag_mcp_server ) } ) } {}
}

@ __ag_mcp_srv → McpServer {
    ( __ag_mcp_init )
    ^ . ( rcbox_ptr [AgMcpWiring] g_ag_mcp ) server
}

// /mcp — Streamable HTTP, the caller resolved per request and handed
// to the dispatch as its context.
@ __ag_h_mcp HttpRequest req → HttpResponse {
    : i now ( now_seconds )
    ? ( ag_auth_oidc ) { ^ ( __ag_h_mcp_oidc req now ) } {}
    : AgCaller caller ( __ag_http_caller req now )
    : Json ctx ( __ag_ctx_of caller )
    : McpServer srv ( __ag_mcp_srv )
    : ( @ ?Json Json ) d \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv rq ctx ) }
    : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler d )
    : HttpResponse out ( h req )
    ^ out
}

// Is this request an MCP `initialize`?
@ __ag_is_initialize HttpRequest req → b {
    ? > ( vec_len [u] . req body ) 0 {} { ^ F }
    ?? ( json_parse_bytes . req body ) {
        T j → {
            ? ( json_is_obj j ) {
                ?? ( json_obj_get j `method` ) { T m → { ^ != 0 ( nurl_str_eq ( json_as_str m ) `initialize` ) } F _ → {} }
            } {}
        }
        F _ → {}
    }
    ^ F
}

// Signed-in /mcp: no token → the 401 that tells the client where to
// sign in. The session id is the service's own: handed out on
// `initialize`, it is what `join` binds an agent to.
@ __ag_h_mcp_oidc HttpRequest req i now → HttpResponse {
    : s method ( string_data . req method )
    ? != 0 ( nurl_str_eq method `OPTIONS` ) {
        : McpServer srv0 ( __ag_mcp_srv )
        : Json c0 ( json_obj_new )
        : ( @ ?Json Json ) d0 \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv0 rq c0 ) }
        : ( @ HttpResponse HttpRequest ) h0 ( mcp_http_handler d0 )
        : HttpResponse pre ( h0 req )
        ^ pre
    } {}
    : AgWho w ( ag_who req now )
    ? == . w status 401 { ^ ( ag_mcp_challenge req . w who ) } {}
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ~ String session ( _ag_header req `mcp-session-id` )
    // A session id travels in a header and keys an agent binding: only
    // the service's own shape (32 hex digits) is accepted.
    ? & > ( string_len session ) 0 ! ( __ag_is_session_id ( string_data session ) ) { = session ( string_new ) } {}
    ? != 0 ( nurl_str_eq method `DELETE` ) {
        ? > ( string_len session ) 0 {
            ( _ag_exec_ss . w st `DELETE FROM sessions WHERE id = ?1 AND sub = ?2` ( string_data session ) ( string_data . . w who sub ) )
        } {}
        : HttpResponse gone ( response_status_only 204 )
        ^ gone
    } {}
    : b fresh & == ( string_len session ) 0 ( __ag_is_initialize req )
    ? fresh { = session ( rand_hex_str 16 ) } {}
    : String agent ( ag_agent_for req . w st . w who ( string_data session ) )
    : Json ctx ( json_obj_new )
    ( json_obj_set ctx `org` ( json_str_lit ( string_data . . w who org ) ) )
    ( json_obj_set ctx `sub` ( json_str_lit ( string_data . . w who sub ) ) )
    ( json_obj_set ctx `email` ( json_str_lit ( string_data . . w who email ) ) )
    ( json_obj_set ctx `agent` ( json_str_lit ( string_data agent ) ) )
    ( json_obj_set ctx `session` ( json_str_lit ( string_data session ) ) )
    : McpServer srv ( __ag_mcp_srv )
    : ( @ ?Json Json ) d \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv rq ctx ) }
    : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler d )
    : HttpResponse out ( h req )
    ? fresh { ( response_set_header out `Mcp-Session-Id` ( string_data session ) ) } {}
    ^ out
}

@ __ag_is_session_id s v → b {
    : i n ( nurl_str_len v )
    ? == n 32 {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get v k )
        ? | & >= c 48 <= c 57 & >= c 97 <= c 102 {} { ^ F }
        = k + k 1
    }
    ^ T
}

// ── Wiring ───────────────────────────────────────────────────────────

// The whole HTTP app. Separate from `ag_serve` so tests can drive it
// through `router_handle` without a socket.
@ ag_build_app i workers b quiet → HttpApp {
    ^ ( ag_build_app_web workers quiet `` )
}

// The same with the web page served from `webroot` ('' = none).
@ ag_build_app_web i workers b quiet s webroot → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_workers a workers )
    ( http_app_cors a )
    ( http_app_body_max a 1048576 )
    ? quiet { ( http_app_quiet a ) } {}
    ( __ag_mcp_init )

    ( http_app_get a `/healthz` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_health req p ) } )
    ( http_app_get a `/api` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_catalog req p ) } )
    ( http_app_get a `/api/:op` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_api req p ) } )
    ( http_app_post a `/api/:op` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_api req p ) } )
    // MCP shares the process and the port (the server itself lives in
    // the wiring above).
    ( http_app_route a `POST` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    ( http_app_route a `GET` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    ( http_app_route a `DELETE` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    // OAuth discovery for MCP clients (404 in local mode).
    ( http_app_get a `/.well-known/oauth-protected-resource` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_resource_metadata req p ) } )
    ( http_app_get a `/.well-known/oauth-protected-resource/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_resource_metadata req p ) } )
    // The web page: its sign-in configuration and its API.
    ( http_app_get a `/auth/config` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_auth_config req p ) } )
    ( http_app_get a `/m/me` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_me req p ) } )
    ( http_app_get a `/m/agents` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_agents req p ) } )
    ( http_app_put a `/m/agents/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_agent_put req p ) } )
    ( http_app_delete a `/m/agents/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_agent_del req p ) } )
    ( http_app_get a `/m/channels` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_channels req p ) } )
    ( http_app_delete a `/m/channels` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_channel_del req p ) } )
    ( http_app_get a `/m/messages` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_messages req p ) } )
    ( http_app_put a `/m/messages/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_message_put req p ) } )
    ( http_app_delete a `/m/messages/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_message_del req p ) } )
    ( http_app_get a `/m/tasks` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_tasks req p ) } )
    ( http_app_put a `/m/tasks/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_task_put req p ) } )
    ( http_app_delete a `/m/tasks/:id` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_task_del req p ) } )
    ( http_app_get a `/m/notes` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_notes req p ) } )
    ( http_app_put a `/m/notes` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_note_put req p ) } )
    ( http_app_delete a `/m/notes` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_note_del req p ) } )
    ( http_app_get a `/m/users` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_users req p ) } )
    ( http_app_put a `/m/users/:sub` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_user_put req p ) } )
    ( http_app_delete a `/m/users/:sub` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_user_del req p ) } )
    ( http_app_get a `/m/tenants` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_tenants req p ) } )
    ( http_app_put a `/m/tenants/:tid` \ HttpRequest req Params p → HttpResponse { ^ ( ag_h_tenant_put req p ) } )
    ? > ( nurl_str_len webroot ) 0 {
        // The sign-in redirect lands on a page of its own; everything
        // else unrouted is a file of the web root (`/` = index.html).
        ( ag_auth_set_webroot webroot )
        ( http_app_get a `/oauth/callback` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_serve_callback ) } )
        ( http_app_static_dir a webroot )
    } {}
    ^ a
}

// The sign-in callback page of the web root.
@ __ag_serve_callback → HttpResponse {
    : String path ( path_join ( ag_auth_webroot ) `oauth-callback.html` )
    ?? ( read_file ( string_data path ) ) {
        T text → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ( response_set_header r `Cache-Control` `no-store` )
            ( response_set_body_str r ( string_data text ) )
            ^ r
        }
        F _ → { ^ ( response_text 404 `not found\n` ) }
    }
}

@ ag_serve s host i port i workers b quiet → i {
    ^ ( ag_serve_web host port workers quiet `` )
}

@ ag_serve_web s host i port i workers b quiet s webroot → i {
    // `--workers 0` means one per CPU — and must mean a pool: the http
    // package runs a single-threaded loop for 0, where one agent's `wait`
    // held up every other call until it returned.
    : i w ? > workers 0 workers ? > ( sys_cpu_count ) 4 ( sys_cpu_count ) 4
    ( ag_wait_cap_set w )
    : HttpApp a ( ag_build_app_web w quiet webroot )
    ^ ( http_app_listen a host port )
}

// MCP over stdio as the local identity set with `ag_state_set_local`.
@ ag_serve_stdio → i {
    : McpServer srv ( ag_mcp_server )
    : ~ i rc 0
    ?? ( mcp_server_serve_stdio srv ) {
        T _ → {}
        F e → {
            ( mcp_log ( nurl_str_cat `agora stdio: ` ( mcp_server_err_name e ) ) )
            = rc 1
        }
    }
    ^ rc
}
