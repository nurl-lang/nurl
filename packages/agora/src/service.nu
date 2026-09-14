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
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `api.nu`

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
    : AgStore st ( ag_store )
    : i now ( now_seconds )
    : AgCaller caller ( ag_caller_of_ctx st ( mcp_call_context c ) now )
    : AgRes res ( ag_op_call st caller name args now )
    ( ag_caller_free caller )
    : Json out ? < . res status 400
    ( mcp_tool_result_text ( string_data . res text ) )
    ( mcp_tool_result_error ( string_data . res text ) )
    ( ag_res_free res )
    ^ out
}

// The MCP server, from the catalog. Built once; served over any
// transport. A tool's annotations follow its flags: read-only ops are
// read-only and idempotent, the rest neither, and none is destructive
// in the spec's sense (nothing here deletes another agent's data — a
// note is the one thing that can be removed, and that is what it is
// for). openWorldHint is F: agora talks to its own file, not the web.
@ ag_mcp_server → McpServer {
    : McpServer srv ( mcp_server_new `agora` AG_VERSION )
    ( mcp_server_set_instructions srv AG_INSTRUCTIONS )
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : i n ( vec_len [AgOpDef] cat )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                ( mcp_server_add_tool_ctx srv ( string_data . d name ) ( string_data . d desc )
                ( json_clone . d schema ) . d read_only F . d read_only F
                \ Json a McpCall c → Json { ^ ( __ag_mcp_tool a c ) } )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( ag_catalog_free cat )
    ^ srv
}

// ── HTTP: identity ───────────────────────────────────────────────────

// The caller behind an HTTP request: the bearer token, looked up. THE
// place a signed-in OAuth principal will be resolved instead.
@ __ag_http_caller HttpRequest req i now → AgCaller {
    ?? ( mcp_auth_bearer_token req ) {
        T tok → {
            : AgCaller c ( ag_caller_of_token ( ag_store ) ( string_data tok ) now )
            ( string_free tok )
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
                : String path ( string_from `/api/` )
                ( string_push_str path ( string_data . d name ) )
                ( json_obj_set o `path` ( json_str_lit ( string_data path ) ) )
                ( string_free path )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( ag_catalog_free cat )
    : Json out ( json_obj_new )
    ( json_obj_set out `service` ( json_str_lit `agora` ) )
    ( json_obj_set out `version` ( json_str_lit AG_VERSION ) )
    ( json_obj_set out `auth` ( json_str_lit `Authorization: Bearer <token from join>` ) )
    ( json_obj_set out `ops` arr )
    ^ out
}

@ __ag_h_catalog HttpRequest req Params p → HttpResponse {
    : Json o ( ag_catalog_json )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// The arguments of a REST call: the JSON object in the body, else the
// query string as flat strings (handlers accept numeric strings).
@ __ag_http_args HttpRequest req → Json {
    ? > ( vec_len [u] . req body ) 0 {
        ?? ( json_parse_bytes . req body ) {
            T j → { ? ( json_is_obj j ) { ^ j } { ( json_free j ) } }
            F _ → {}
        }
        // A body that is not a JSON object: the query still counts.
    } {}
    : Json o ( json_obj_new )
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [QueryPair] pairs i ) {
            T qp → { ( json_obj_set o ( string_data . qp key ) ( json_str_lit ( string_data . qp value ) ) ) }
            F _ → {}
        }
        = i + i 1
    }
    ( query_pairs_free pairs )
    ^ o
}

// POST|GET /api/:op
@ __ag_h_api HttpRequest req Params p → HttpResponse {
    : ~ String op ( string_new )
    ?? ( params_get p `op` ) { T v → { ( string_free op ) = op v } F _ → {} }
    : i now ( now_seconds )
    : AgCaller caller ( __ag_http_caller req now )
    : Json args ( __ag_http_args req )
    : AgRes res ( ag_op_call ( ag_store ) caller ( string_data op ) args now )
    ( json_free args )
    ( ag_caller_free caller )
    ( string_free op )
    : HttpResponse r ( response_json . res status . res body )
    ? == . res status 401 {
        ( response_set_header r `WWW-Authenticate` `Bearer realm="agora"` )
    } {}
    ( ag_res_free res )
    ^ r
}

// The one McpServer the HTTP face serves, built on first use and
// freed by `ag_service_shutdown`. Every field of an McpServer is a
// shared handle, so the copy `__ag_mcp_srv` returns IS the server.
: AgMcpWiring {
    McpServer server
    b has_server
}

: ~ i g_ag_mcp 0

@ __ag_mcp_srv → McpServer {
    ? == g_ag_mcp 0 {
        : *AgMcpWiring w # *AgMcpWiring ( nurl_alloc Z AgMcpWiring )
        = . w server ( ag_mcp_server )
        = . w has_server T
        = g_ag_mcp # i w
    } {}
    : *AgMcpWiring w # *AgMcpWiring g_ag_mcp
    ^ . w server
}

// Free what the service built: the MCP server and the state. For a
// clean exit (and a clean LeakSanitizer run) after the listener closes.
@ ag_service_shutdown → v {
    ? == g_ag_mcp 0 {} {
        : *AgMcpWiring w # *AgMcpWiring g_ag_mcp
        ? . w has_server { ( mcp_server_free . w server ) } {}
        ( nurl_free # s # *AgMcpWiring g_ag_mcp )
        = g_ag_mcp 0
    }
    ( ag_state_free )
}

// /mcp — Streamable HTTP, the caller resolved per request and handed
// to the dispatch as its context.
@ __ag_h_mcp HttpRequest req → HttpResponse {
    : i now ( now_seconds )
    : AgCaller caller ( __ag_http_caller req now )
    : Json ctx ( __ag_ctx_of caller )
    ( ag_caller_free caller )
    : McpServer srv ( __ag_mcp_srv )
    : ( @ ?Json Json ) d \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv rq ctx ) }
    : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler d )
    : HttpResponse out ( h req )
    ( nurl_free # s # *u h 1 )
    ( nurl_free # s # *u d 1 )
    ( json_free ctx )
    ^ out
}

// ── Wiring ───────────────────────────────────────────────────────────

// The whole HTTP app. Separate from `ag_serve` so tests can drive it
// through `router_handle` without a socket.
@ ag_build_app i workers b quiet → *HttpApp {
    : *HttpApp a ( http_app_new )
    ( http_app_workers a workers )
    ( http_app_cors a )
    ( http_app_body_max a 1048576 )
    ? quiet { ( http_app_quiet a ) } {}

    ( http_app_get a `/healthz` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_health req p ) } )
    ( http_app_get a `/api` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_catalog req p ) } )
    ( http_app_get a `/api/:op` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_api req p ) } )
    ( http_app_post a `/api/:op` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_api req p ) } )
    // MCP shares the process and the port (the server itself lives in
    // the wiring above, built on the first /mcp request).
    ( http_app_route a `POST` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    ( http_app_route a `GET` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    ( http_app_route a `DELETE` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( __ag_h_mcp req ) } )
    ^ a
}

@ ag_serve s host i port i workers b quiet → i {
    : *HttpApp a ( ag_build_app workers quiet )
    : i rc ( http_app_listen a host port )
    ( http_app_free a )
    ( ag_service_shutdown )
    ^ rc
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
    ( mcp_server_free srv )
    ( ag_state_free )
    ^ rc
}
