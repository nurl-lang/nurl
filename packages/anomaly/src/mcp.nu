// anomaly/mcp.nu — the service as an MCP server, mounted at /mcp.
//
// A language model talks to the same service the dashboard does, with the
// same credential, and gets exactly what that credential may do: the tool
// list is computed per caller (a viewer never sees `ingest_point`), and
// every tool runs as an in-process HTTP request through the service's own
// router, so the API's authorisation gates are the only gates — there is
// no second rule book to drift.
//
// What the model sees is shaped for a context window rather than for a
// chart: timestamps are ISO-8601 UTC, floats are rounded, a listing is a
// summary plus the newest rows, and every reply names what it left out.
//
//   POST /mcp                        JSON-RPC (Streamable HTTP transport)
//   GET  /.well-known/oauth-protected-resource[/mcp]
//                                    where to get a token (RFC 9728)
//
// Sign-in: the same OAuth (Entra) tokens the dashboard sends, or an API
// key in `Authorization: Bearer` / `X-API-Key`. With authorisation off
// (simple mode) every caller is the administrator, as everywhere else.
//
// The server object is static (built once, no per-request state); the
// caller is a context Json the dispatch carries into gates and handlers.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_server.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/mcp_auth.nu`
$ `src/authz.nu`
$ `src/imptime.nu`

// One version for the CLI banner and the MCP handshake.
: s ANOMALY_VERSION `0.33.0`

// ── Wiring ───────────────────────────────────────────────────────────

// The router the tools call back into (a shallow copy of the service
// router, whose route table is complete by the time it is attached), the
// static server, and the public origin for the resource-metadata URLs.
: McpWiring {
    Router router
    b has_router
    String public_url
    b has_server
    McpServer server
}

: ~ i g_mcp_wiring 0

@ __mcp_wiring → *McpWiring {
    ? != g_mcp_wiring 0 { ^ # *McpWiring g_mcp_wiring } {}
    : *McpWiring w # *McpWiring ( nurl_malloc Z McpWiring )
    = . w router ( router_new )
    = . w has_router F
    = . w public_url ( string_new )
    = . w has_server F
    = g_mcp_wiring # i w
    ^ w
}

// Called by anomaly_service_router once every route is registered. The
// copy shares the route vector, so the router must not grow afterwards.
@ an_mcp_attach_router Router r → v {
    : *McpWiring w ( __mcp_wiring )
    ? . w has_router {} { ( router_free . w router ) }
    = . w router @ Router { . r routes }
    = . w has_router T
}

// `[service] public_url` — the origin clients reach the service at, when
// it sits behind a proxy that rewrites Host. Empty: derived per request
// from Host / X-Forwarded-*.
@ an_mcp_set_public_url s url → v {
    : *McpWiring w ( __mcp_wiring )
    ( string_clear . w public_url )
    ( string_push_str . w public_url url )
}

@ __mcp_server → McpServer {
    : *McpWiring w ( __mcp_wiring )
    ? . w has_server {} {
        = . w server ( __mcp_build_server )
        = . w has_server T
    }
    ^ . w server
}

// ── The caller ───────────────────────────────────────────────────────
//
// The context every gate and handler sees. It carries the credential
// itself (never shown to the model — it is only replayed onto the
// in-process requests), so the API's gates judge the same token.

@ __mcp_ctx_of HttpRequest req Principal p → Json {
    : Json c ( json_obj_new )
    ( json_obj_set c `authenticated` ( json_bool . p authed ) )
    ( json_obj_set c `organization` ( json_str_lit ( string_data . p org ) ) )
    ( json_obj_set c `subject` ( json_str_lit ( string_data . p sub ) ) )
    ( json_obj_set c `name` ( json_str_lit ( string_data . p pname ) ) )
    ( json_obj_set c `email` ( json_str_lit ( string_data . p email ) ) )
    ( json_obj_set c `role` ( json_str_lit ( string_data . p role ) ) )
    ( json_obj_set c `admin` ( json_bool ( principal_is_admin p ) ) )
    ( json_obj_set c `may_ingest` ( json_bool ( principal_may_ingest p ) ) )
    ( json_obj_set c `via_api_key` ( json_bool . p via_key ) )
    ?? ( header_get . req headers `authorization` ) {
        T v → { ( json_obj_set c `authorization` ( json_str_lit ( string_data v ) ) ) ( string_free v ) }
        F → {}
    }
    ?? ( header_get . req headers `x-api-key` ) {
        T v → { ( json_obj_set c `api_key` ( json_str_lit ( string_data v ) ) ) ( string_free v ) }
        F → {}
    }
    ^ c
}

@ __mcp_ctx_bool Json ctx s key → b {
    ?? ( json_obj_get ctx key ) {
        T v → { ^ ( json_as_bool v ) }
        F _ → { ^ F }
    }
}

@ __mcp_ctx_str Json ctx s key → s {
    ?? ( json_obj_get ctx key ) {
        T v → { ^ ( json_as_str v ) }
        F _ → { ^ `` }
    }
}

// The three audiences. A tool a caller may not use is not listed for
// that caller and is "unknown" when called (mcp_server_add_tool_gated).
@ __mcp_vis_member Json ctx → b { ^ ( __mcp_ctx_bool ctx `authenticated` ) }

@ __mcp_vis_ingest Json ctx → b { ^ ( __mcp_ctx_bool ctx `may_ingest` ) }

@ __mcp_vis_admin Json ctx → b { ^ ( __mcp_ctx_bool ctx `admin` ) }

// ── In-process API calls ─────────────────────────────────────────────
//
// A tool is an HTTP request the service makes to itself: the caller's
// credential is replayed, the router dispatches, and the JSON body comes
// back parsed. The outer /mcp handler already holds the service lock, so
// this runs inside it — one caller at a time, like every other request.

: ApiOut {
    i status
    Json body  // the parsed body, or JSON null when it was not JSON
}

@ __mcp_api_out_free sink ApiOut o → v { ( json_free . o body ) }

@ __mcp_api Json ctx s method s path String query ? Json body → ApiOut {
    ?? body {
        T bj → {
            : String txt ( json_stringify bj )
            : ApiOut out ( __mcp_api_send ctx method path query `application/json` ( string_data txt ) )
            ( string_free txt )
            ^ out
        }
        F _ → { ^ ( __mcp_api_send ctx method path query `` `` ) }
    }
}

// The general form: a body of any content type (empty `content_type` =
// no body).
@ __mcp_api_send Json ctx s method s path String query s content_type s text → ApiOut {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ( string_push_str . req query ( string_data query ) )
    ( string_push_str . req version `HTTP/1.1` )
    : s auth ( __mcp_ctx_str ctx `authorization` )
    ? > ( nurl_str_len auth ) 0 {
        ( vec_push [Header] . req headers ( header_new `Authorization` auth ) )
    } {}
    : s key ( __mcp_ctx_str ctx `api_key` )
    ? > ( nurl_str_len key ) 0 {
        ( vec_push [Header] . req headers ( header_new `X-API-Key` key ) )
    } {}
    ? > ( nurl_str_len content_type ) 0 {
        ( vec_push [Header] . req headers ( header_new `Content-Type` content_type ) )
        ( bytes_extend_str . req body text )
    } {}
    : *McpWiring w ( __mcp_wiring )
    : HttpResponse resp ( router_handle . w router req )
    ( request_free req )
    : ~ Json parsed ( json_null )
    ? > ( vec_len [u] . resp body ) 0 {
        ?? ( json_parse_bytes . resp body ) {
            T j → { ( json_free parsed ) = parsed j }
            F _ → {}
        }
    } {}
    : i st . resp status
    ( http_response_free resp )
    ^ @ ApiOut { st parsed }
}

// A failed call, as a tool error the model can act on: the status and
// the service's own message (the API's 4xx bodies say what to change).
@ __mcp_api_error ApiOut o → Json {
    : String m ( string_from `HTTP ` )
    ( string_push_int m . o status )
    ( string_push_str m `: ` )
    : ~ b said F
    ?? ( json_obj_get . o body `message` ) {
        T v → { ( string_push_str m ( json_as_str v ) ) = said T }
        F _ → {}
    }
    ? said {} {
        ?? ( json_obj_get . o body `detail` ) {
            T v → { ( string_push_str m ( json_as_str v ) ) = said T }
            F _ → {}
        }
    }
    ? said {} {
        ?? ( json_obj_get . o body `error` ) {
            T v → { ( string_push_str m ( json_as_str v ) ) = said T }
            F _ → {}
        }
    }
    ? said {} { ( string_push_str m ( __mcp_status_text . o status ) ) }
    // Where to go next. A successful answer here names its follow-up
    // tool; a failure named none, and the tool that could resolve it —
    // "which models are there", "who am I acting for" — is exactly what
    // a caller staring at a 404 or a 403 needs to be told.
    : s hint ( __mcp_status_next . o status )
    ? > ( nurl_str_len hint ) 0 {
        ( string_push_str m ` — ` )
        ( string_push_str m hint )
    } {}
    : Json out ( mcp_tool_result_error ( string_data m ) )
    ( string_free m )
    ^ out
}

@ __mcp_status_next i status → s {
    ? == status 400 { ^ `check the arguments against the tool's schema; the message names the field` } {}
    ? == status 401 { ^ `whoami says who this session is acting for, and whether it is signed in` } {}
    ? == status 403 { ^ `whoami shows the role this session has; a model named llm_<something> is yours to create and change whatever that role is` } {}
    ? == status 404 { ^ `list_models shows the model names, sources the data sources, list_tasks the jobs, list_files the folder` } {}
    ? == status 409 { ^ `the name is taken — list_models shows what exists; delete_model frees a scratch name` } {}
    ? == status 413 { ^ `send less: analyze_data and import_data take a file in pieces, and a big file comes back as a task to poll with task` } {}
    ? >= status 500 { ^ `the service failed, not the request; try again, and list_tasks if a background job was involved` } {}
    ^ ``
}

@ __mcp_status_text i status → s {
    ? == status 400 { ^ `bad request` } {}
    ? == status 401 { ^ `sign in required` } {}
    ? == status 403 { ^ `forbidden` } {}
    ? == status 404 { ^ `not found` } {}
    ? == status 409 { ^ `conflict` } {}
    ? == status 413 { ^ `too large` } {}
    ? >= status 500 { ^ `service error` } {}
    ^ `request failed`
}

@ __mcp_api_ok ApiOut o → b { ^ & >= . o status 200 < . o status 300 }

// A tool result whose text is `j` serialised compactly. CONSUMES j.
@ __mcp_result_json Json j → Json {
    : String txt ( json_stringify j )
    : Json out ( mcp_tool_result_text ( string_data txt ) )
    ( string_free txt )
    ( json_free j )
    ^ out
}

// Pass the API's own body through as the result, or its error.
@ __mcp_pass ApiOut o → Json {
    ? ( __mcp_api_ok o ) {} {
        : Json e ( __mcp_api_error o )
        ( __mcp_api_out_free o )
        ^ e
    }
    ^ ( __mcp_result_json . o body )
}

// ── Arguments ────────────────────────────────────────────────────────

@ __mcp_arg Json a s key → ?Json {
    ? ( json_is_obj a ) {} { ^ @ ?Json { F @ Json { JNull } } }
    ^ ( json_obj_get a key )
}

@ __mcp_arg_has Json a s key → b {
    ?? ( __mcp_arg a key ) {
        T v → { ^ ! ( json_is_null v ) }
        F _ → { ^ F }
    }
}

// A string argument; a number is accepted as its digits. `` when absent.
@ __mcp_arg_str Json a s key → String {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
            ? ( json_is_num v ) { : String n ( string_new ) ( string_push_int n ( json_as_int v ) ) ^ n } {}
            ^ ( string_new )
        }
        F _ → { ^ ( string_new ) }
    }
}

@ __mcp_arg_int Json a s key i dflt → i {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s raw ( json_str_data v )
                ? > ( nurl_str_len raw ) 0 { ^ ( nurl_str_to_int raw ) } {}
            } {}
            ^ dflt
        }
        F _ → { ^ dflt }
    }
}

@ __mcp_arg_f Json a s key f dflt → f {
    ?? ( __mcp_arg a key ) {
        T v → {
            ?? ( json_num_as_f v ) {
                T x → { ^ x }
                F → {
                    ? ( json_is_str v ) { ^ ( nurl_str_to_float ( json_str_data v ) ) } {}
                    ^ dflt
                }
            }
        }
        F _ → { ^ dflt }
    }
}

@ __mcp_arg_bool Json a s key b dflt → b {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_bool v ) { ^ ( json_bool_val v ) } {}
            ? ( json_is_str v ) {
                : s raw ( json_str_data v )
                ? == ( nurl_str_eq raw `true` ) 1 { ^ T } {}
                ? == ( nurl_str_eq raw `false` ) 1 { ^ F } {}
            } {}
            ? ( json_is_num v ) { ^ != ( json_as_int v ) 0 } {}
            ^ dflt
        }
        F _ → { ^ dflt }
    }
}

// A list argument as a comma-joined String: ["a","b"] or "a,b" → `a,b`.
@ __mcp_arg_csv Json a s key → String {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_arr v ) {
                : String out ( string_new )
                : i n ( json_arr_len v )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get v k ) {
                        T e → {
                            ? > ( string_len out ) 0 { ( string_push_char out 44 ) } {}
                            ( string_push_str out ( json_as_str e ) )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ^ out
            } {}
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
            ^ ( string_new )
        }
        F _ → { ^ ( string_new ) }
    }
}

// A moment: a Unix number, or an ISO date/date-time text (a bare one is
// read in the server's zone). 0 when absent, -1 when unreadable.
@ __mcp_arg_instant Json a s key → i {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_null v ) { ^ 0 } {}
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s raw ( json_str_data v )
                ? == ( nurl_str_len raw ) 0 { ^ 0 } {}
                : i t ( imp_instant_of_text raw ANOM_TZ_LOCAL )
                ^ ? > t 0 t -1
            } {}
            ^ -1
        }
        F _ → { ^ 0 }
    }
}

// A span: seconds as a number, or "90s" / "15m" / "24h" / "7d" / "2w";
// "all" (also "max", "*") is the whole ring, the word the REST routes
// know — one window vocabulary for every tool. 0 when absent,
// MCP_SPAN_ALL for the whole ring, -1 when unreadable.
: i MCP_SPAN_ALL -2

@ __mcp_span_is_all s raw → b {
    ^ || == ( nurl_str_eq raw `all` ) 1 || == ( nurl_str_eq raw `max` ) 1 == ( nurl_str_eq raw `*` ) 1
}

@ __mcp_arg_span Json a s key → i {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_null v ) { ^ 0 } {}
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s raw ( json_str_data v )
                ? == ( nurl_str_len raw ) 0 { ^ 0 } {}
                ? ( __mcp_span_is_all raw ) { ^ MCP_SPAN_ALL } {}
                : i t ( imp_span_of_text raw )
                ^ ? > t 0 t -1
            } {}
            ^ -1
        }
        F _ → { ^ 0 }
    }
}

// Model names are path segments; the API says what a bad one is.
@ __mcp_arg_model Json a s key → String {
    ^ ( __mcp_arg_str a key )
}

// ── Query strings ────────────────────────────────────────────────────

@ __mcp_q_add String q s key s value → v {
    ? > ( string_len q ) 0 { ( string_push_char q 38 ) } {}
    ( string_push_str q key )
    ( string_push_char q 61 )
    : String enc ( percent_encode value )
    ( string_push_str q ( string_data enc ) )
    ( string_free enc )
}

@ __mcp_q_add_int String q s key i value → v {
    : String n ( string_new )
    ( string_push_int n value )
    ( __mcp_q_add q key ( string_data n ) )
    ( string_free n )
}

// from / to / last from the arguments onto a query string. Returns a tool
// error when a bound is unreadable, else JSON null.
@ __mcp_q_window Json a String q → Json {
    : i from ( __mcp_arg_instant a `from` )
    ? < from 0 { ^ ( mcp_tool_result_error `from: not a moment — use ISO-8601 (2026-09-01 or 2026-09-01T06:00:00Z) or Unix seconds` ) } {}
    : i to ( __mcp_arg_instant a `to` )
    ? < to 0 { ^ ( mcp_tool_result_error `to: not a moment — use ISO-8601 (2026-09-01 or 2026-09-01T06:00:00Z) or Unix seconds` ) } {}
    : i last ( __mcp_arg_span a `last` )
    ? | > last 0 == last MCP_SPAN_ALL {} {
        ? < last 0 { ^ ( mcp_tool_result_error `last: not a span — use seconds, 90s / 15m / 24h / 7d / 2w, or "all" for every stored point` ) } {}
    }
    ? > from 0 { ( __mcp_q_add_int q `from` from ) } {}
    ? > to 0 { ( __mcp_q_add_int q `to` to ) } {}
    ? > last 0 { ( __mcp_q_add_int q `last` last ) } {}
    ? == last MCP_SPAN_ALL { ( __mcp_q_add q `last` `all` ) } {}
    ^ ( json_null )
}

// ── Time, for a reader ───────────────────────────────────────────────

// The `clock` the API reports: on a count clock the stamps are ordinals
// spaced ANOM_TICK apart, on a time clock they are Unix seconds.
@ __mcp_count_clock Json body → b {
    ?? ( json_obj_get body `clock` ) {
        T v → { ^ == ( nurl_str_eq ( json_as_str v ) `count` ) 1 }
        F _ → { ^ F }
    }
}

// A stamp as the model should read it: ISO UTC, or the point's ordinal.
@ __mcp_when i ts b count_clock → Json {
    ? count_clock { ^ ( json_int / ts 60 ) } {}
    ? <= ts 0 { ^ ( json_null ) } {}
    : String iso ( time_format_iso ( time_from_unix ts ) )
    : Json out ( json_str_lit ( string_data iso ) )
    ( string_free iso )
    ^ out
}

// The keys that carry a wall-clock instant, wherever they appear in a
// record. `list_models` promises "Times are ISO-8601 UTC", and the tools
// that hand a record back whole — sources, tasks, the audit trail, the
// forecast's trained_at — were handing back Unix seconds, so a reader had
// two spellings of a moment in one session and no rule for which was
// which. Row stamps are NOT in this list: on a count clock they are
// ordinals, and the tools that carry them already say so.
@ __mcp_is_time_key s k → b {
    ? == ( nurl_str_eq k `at` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `created` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `created_at` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `updated_at` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `started` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `finished` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `last_run` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `first_time` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `last_time` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `trained_at` ) 1 { ^ T } {}
    ? == ( nurl_str_eq k `last_trained_time` ) 1 { ^ T } {}
    ^ == ( nurl_str_eq k `expires_at` ) 1
}

// Every wall-clock key in a record, ISO-8601 UTC. A 0 stays 0: "never
// happened" is not a moment, and 1970 in its place is a lie.
@ __mcp_iso_times Json o → Json {
    ? ( json_is_arr o ) {
        : Json arr ( json_arr_new )
        ( json_arr_each o \ Json e → v { ( json_arr_push arr ( __mcp_iso_times e ) ) } )
        ^ arr
    } {}
    ? ( json_is_obj o ) {} { ^ ( json_clone o ) }
    : Json out ( json_obj_new )
    ( json_obj_each o \ s k Json v → v {
        ? & ( __mcp_is_time_key k ) ( json_is_num v ) {
            : i t ( json_as_int v )
            ( json_obj_set out k ? > t 0 ( __mcp_when t F ) ( json_clone v ) )
        } { ( json_obj_set out k ( __mcp_iso_times v ) ) }
    } )
    ^ out
}

// Copy `key` from `src` as a readable stamp under `dst_key`.
@ __mcp_when_of Json src s key Json dst s dst_key b count_clock → v {
    ?? ( json_obj_get src key ) {
        T v → {
            ? ( json_is_num v ) { ( json_obj_set dst dst_key ( __mcp_when ( json_as_int v ) count_clock ) ) } {}
        }
        F _ → {}
    }
}

// When a model was last trained, as the wall-clock time the metadata
// records (`last_trained_time`; a model trained before it was recorded
// has none), and how many points it has taken since — `last_trained_at`
// is that point count, not a time, whatever the clock. A model whose
// feature order predates the current calendar encoding says so.
@ __mcp_training_of Json src Json dst → v {
    ?? ( json_obj_get src `last_trained_time` ) {
        T v → {
            : i t ( json_as_int v )
            ? > t 0 { ( json_obj_set dst `last_trained` ( __mcp_when t F ) ) } {}
        }
        F _ → {}
    }
    ?? ( json_obj_get src `last_trained_at` ) {
        T v → {
            : i at ( json_as_int v )
            : ~ i seen 0
            ?? ( json_obj_get src `n_points_seen` ) { T sv → { = seen ( json_as_int sv ) } F _ → {} }
            ? > at 0 { ( json_obj_set dst `points_since_training` ( json_int - seen at ) ) } {}
        }
        F _ → {}
    }
    ?? ( json_obj_get src `retrain_required` ) {
        T v → { ? ( json_as_bool v ) { ( json_obj_set dst `retrain_required` ( json_bool T ) ) } {} }
        F _ → {}
    }
}

// A number rounded to `digits` decimals, so a score reads as 0.6132 and
// not as seventeen digits of it — but never to fewer than `digits`
// SIGNIFICANT digits: an autoencoder scores in the 1e-4 range, and four
// decimals would turn every one of its values into 0.0001 or 0.0. Below
// one in magnitude the rounding is therefore by significant digits,
// through an exact integer mantissa and a power of ten so the result is
// the double the short decimal parses to.
@ __mcp_round_f f x i digits → Json {
    : f ax ( float_abs x )
    ? & > ax 0.0 < ax 1.0 {
        : i e # i ( float_floor ( float_log10 ax ) )
        : f scale ( float_pow 10.0 # f - - digits 1 e )
        : f m / ( float_round * ax scale ) scale
        ^ ( json_float ? < x 0.0 - 0.0 m m )
    } {}
    : ~ f scale 1.0
    : ~ i k 0
    ~ < k digits { = scale * scale 10.0 = k + k 1 }
    ^ ( json_float / ( float_round * x scale ) scale )
}

@ __mcp_round Json v i digits → Json {
    ?? ( json_num_as_f v ) {
        T x → { ^ ( __mcp_round_f x digits ) }
        F → { ^ ( json_clone v ) }
    }
}

// Move a key, if present, from `src` to `dst` (cloned).
@ __mcp_copy Json src s key Json dst → v {
    ?? ( json_obj_get src key ) {
        T v → { ( json_obj_set dst key ( json_clone v ) ) }
        F _ → {}
    }
}

@ __mcp_copy_rounded Json src s key Json dst i digits → v {
    ?? ( json_obj_get src key ) {
        T v → { ( json_obj_set dst key ( __mcp_round v digits ) ) }
        F _ → {}
    }
}

// An array of numbers under `key`, rounded; an empty array when the key
// is absent or is not an array.
@ __mcp_round_arr Json src s key i digits → Json {
    : Json out ( json_arr_new )
    ?? ( json_obj_get src key ) {
        T v → {
            ? ( json_is_arr v ) {
                ( json_arr_each v \ Json e → v { ( json_arr_push out ( __mcp_round e digits ) ) } )
            } {}
        }
        F _ → {}
    }
    ^ out
}

// Is `name` one of the comma-separated entries of `csv`?
@ __mcp_csv_has s csv s name → b {
    : String hay ( string_from csv )
    : ( Vec String ) parts ( string_split hay `,` )
    ( string_free hay )
    : ~ b hit F
    : i n ( vec_len [String] parts )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] parts k ) {
            T pp → {
                : String t ( string_trim pp )
                ? == ( nurl_str_eq ( string_data t ) name ) 1 { = hit T } {}
                ( string_free t )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String x → v { ( string_free x ) } )
    ^ hit
}

// A `{field: number}` object with every number rounded.
@ __mcp_round_obj Json vals i digits → Json {
    : Json out ( json_obj_new )
    ( json_obj_each vals \ s k Json v → v {
        ? ( json_is_num v ) { ( json_obj_set out k ( __mcp_round v digits ) ) }
        { ( json_obj_set out k ( json_clone v ) ) }
    } )
    ^ out
}

// ── Paths ────────────────────────────────────────────────────────────

@ __mcp_model_path s prefix String model s suffix → String {
    : String p ( string_from prefix )
    ( string_push_str p ( string_data model ) )
    ( string_push_str p suffix )
    ^ p
}

// A tool that needs a model name; `` when the argument is missing. A
// person calls a model by its alias as readily as by its name, and an
// agent repeats what it was told — so a name that is no stored model is
// looked up as an alias among the models the caller may see (the
// listing is the organisation's own, so nothing outside it resolves)
// and the model's real name is used. The lookup costs a listing and
// only runs when the name as given is not a model (404, or 400 when
// it is not even a valid name).
@ __mcp_need_model Json a Json ctx → String {
    : String given ( __mcp_arg_str a `model` )
    ? > ( string_len given ) 0 {} { ^ given }
    : String q ( string_new )
    : String mp ( __mcp_model_path `/models/dynamic/` given `/metadata` )
    : ApiOut probe ( __mcp_api ctx `GET` ( string_data mp ) q @ ?Json { F @ Json { JNull } } )
    ( string_free mp )
    // 404: no such model; 400: not even a model name (an alias may carry
    // spaces and accents, a name may not).
    : b missing | == . probe status 404 == . probe status 400
    ( __mcp_api_out_free probe )
    ? missing {} { ( string_free q ) ^ given }
    : ApiOut o ( __mcp_api ctx `GET` `/models/dynamic` q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    : ~ String real ( string_new )
    ? ( __mcp_api_ok o ) {
        : String want ( string_to_lower given )
        ?? ( json_obj_get . o body `models` ) {
            T ms → {
                ( json_obj_each ms \ s name Json mj → v {
                    ? > ( string_len real ) 0 {} {
                        ?? ( json_obj_get mj `alias` ) {
                            T av → {
                                ? ( json_is_str av ) {
                                    : String al ( string_from ( json_str_data av ) )
                                    : String all ( string_to_lower al )
                                    ? & > ( string_len all ) 0 ( string_eq all want ) { ( string_push_str real name ) } {}
                                    ( string_free all )
                                    ( string_free al )
                                } {}
                            }
                            F _ → {}
                        }
                    }
                } )
            }
            F _ → {}
        }
        ( string_free want )
    } {}
    ( __mcp_api_out_free o )
    ? > ( string_len real ) 0 { ( string_free given ) ^ real } {}
    ( string_free real )
    ^ given
}

@ __mcp_no_model → Json {
    ^ ( mcp_tool_result_error `model: required — the name from list_models` )
}

@ __mcp_is_scratch String name → b {
    ^ ( az_is_scratch_model ( string_data name ) )
}

// ── Tools: who am I ──────────────────────────────────────────────────

@ __mcp_t_whoami Json a Json ctx → Json {
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` `/api/me` q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `organization` out )
    ( __mcp_copy . o body `name` out )
    ( __mcp_copy . o body `email` out )
    ( __mcp_copy . o body `role` out )
    ( __mcp_copy . o body `via_api_key` out )
    ( __mcp_copy . o body `auth_enabled` out )
    : b admin ( __mcp_ctx_bool ctx `admin` )
    : b ingest ( __mcp_ctx_bool ctx `may_ingest` )
    : Json may ( json_arr_new )
    ( json_arr_push may ( json_str_lit `read every model of the organisation: list_models, anomalies, anomaly_summary, points, calibration, score_point, analyze_data` ) )
    ( json_arr_push may ( json_str_lit `create, retrain, fine-tune, edit and delete scratch models named llm_… (fork_model builds one)` ) )
    ? ingest { ( json_arr_push may ( json_str_lit `send points to any model: ingest_point, import_data` ) ) } {}
    ? admin {
        ( json_arr_push may ( json_str_lit `change or delete any model of the organisation, claim unowned ones` ) )
        ( json_arr_push may ( json_str_lit `see the organisation's members and API keys, change a member's role` ) )
    } {
        ( json_arr_push may ( json_str_lit `NOT change or delete models outside llm_… — an administrator does that` ) )
    }
    ( json_obj_set out `may` may )
    ( json_obj_set out `scratch_prefix` ( json_str_lit AZ_LLM_PREFIX ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// ── Tools: models ────────────────────────────────────────────────────

// One model, as a line in a listing: what it watches, how much it has
// seen, when it was last trained, what its versions flag at.
// One model in a listing. `detail` decides how much: an organisation with
// a dozen thirty-column models spent four thousand tokens on the full
// form before a reader had asked about any single one of them, and the
// listing exists to answer "what is here" — the columns and every
// version's margin belong to describe_model, which is one call away.
@ __mcp_model_brief s name Json mj b detail → Json {
    : Json m ( json_obj_new )
    ( json_obj_set m `name` ( json_str_lit name ) )
    : s alias ( __mcp_ctx_str mj `alias` )
    ? > ( nurl_str_len alias ) 0 { ( json_obj_set m `alias` ( json_str_lit alias ) ) } {}
    ( json_obj_set m `scratch` ( json_bool ( az_is_scratch_model name ) ) )
    ( __mcp_copy mj `clock` m )
    ?? ( json_obj_get mj `column_types` ) {
        T ct → {
            : Json cols ( json_arr_new )
            ( json_obj_each ct \ s k Json v → v { ( json_arr_push cols ( json_str_lit k ) ) } )
            ? detail { ( json_obj_set m `columns` cols ) } {
                ( json_obj_set m `columns` ( json_int ( json_arr_len cols ) ) )
                ( json_free cols )
            }
        }
        F _ → {}
    }
    ( __mcp_copy mj `n_points_seen` m )
    ( __mcp_copy mj `n_points_stored` m )
    ? detail { ( __mcp_copy mj `max_data_points` m ) } {}
    ( __mcp_training_of mj m )
    ? > ( __mcp_int_of mj `votes` ) 1 { ( __mcp_copy mj `votes` m ) } {}
    ?? ( json_obj_get mj `versions` ) {
        T vs → {
            ? detail {
                : Json out ( json_obj_new )
                ( json_obj_each vs \ s vn Json vo → v {
                    : Json v ( json_obj_new )
                    ( __mcp_copy vo `decision_margin` v )
                    ( __mcp_copy vo `enabled` v )
                    ( json_obj_set out vn v )
                } )
                ( json_obj_set m `versions` out )
            } {
                : Json on ( json_arr_new )
                ( json_obj_each vs \ s vn Json vo → v {
                    ?? ( json_obj_get vo `enabled` ) {
                        T e → { ? ( json_as_bool e ) { ( json_arr_push on ( json_str_lit vn ) ) } {} }
                        F _ → {}
                    }
                } )
                ( json_obj_set m `versions_on` on )
            }
        }
        F _ → {}
    }
    : Json w ( __mcp_health_meta mj )
    ? > ( json_arr_len w ) 0 { ( json_obj_set m `warnings` w ) } { ( json_free w ) }
    ^ m
}

// What a reader should know about a model before trusting its verdicts,
// from its metadata alone: a version with no band, a ring that has
// evicted history, a feature order the encoding has moved past. Empty
// when nothing stands out; a summary adds what only a scan can see.
@ __mcp_health_meta Json mj → Json {
    : Json w ( json_arr_new )
    : i seen ( __mcp_int_of mj `n_points_seen` )
    : i mx ( __mcp_int_of mj `max_data_points` )
    ? & > mx 0 > seen mx {
        : String s ( string_from `ring full: the newest ` )
        ( string_push_int s mx )
        ( string_push_str s ` of ` )
        ( string_push_int s seen )
        ( string_push_str s ` points are stored; the rest were evicted, and every window and retrain sees only what is stored` )
        ( json_arr_push w ( json_str_lit ( string_data s ) ) )
        ( string_free s )
    } {}
    ?? ( json_obj_get mj `retrain_required` ) {
        T v → { ? ( json_as_bool v ) { ( json_arr_push w ( json_str_lit `retrain required: the feature order predates the current calendar encoding; retrain re-encodes the ring` ) ) } {} }
        F _ → {}
    }
    ?? ( json_obj_get mj `versions` ) {
        T vs → {
            ( json_obj_each vs \ s vn Json vo → v {
                : ~ b on T
                ?? ( json_obj_get vo `enabled` ) { T e → { = on ( json_as_bool e ) } F _ → {} }
                ? & on == ( __mcp_f_of vo `decision_margin` ) 0.0 {
                    : String s ( string_from vn )
                    ( string_push_str s `: margin 0 — no band above its raw threshold, so it flags every row it scores past that line; calibration shows what a margin would flag, finetune sets one` )
                    ( json_arr_push w ( json_str_lit ( string_data s ) ) )
                    ( string_free s )
                } {}
            } )
        }
        F _ → {}
    }
    ^ w
}

@ __mcp_t_list_models Json a Json ctx → Json {
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` `/models/dynamic` q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : b detail ( __mcp_arg_bool a `detail` F )
    : Json out ( json_obj_new )
    ( json_obj_set out `organization` ( json_str_lit ( __mcp_ctx_str ctx `organization` ) ) )
    : Json arr ( json_arr_new )
    : ~ i n 0
    ?? ( json_obj_get . o body `models` ) {
        T ms → {
            : ( Vec String ) names ( json_obj_keys ms )
            : i nn ( vec_len [String] names )
            : ~ i k 0
            ~ < k nn {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ?? ( json_obj_get ms ( string_data nm ) ) {
                            T mj → { ( json_arr_push arr ( __mcp_model_brief ( string_data nm ) mj detail ) ) }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
            = n ( json_arr_len arr )
        }
        F _ → {}
    }
    ( json_obj_set out `count` ( json_int n ) )
    ( json_obj_set out `models` arr )
    ( json_obj_set out `hint` ( json_str_lit ? == n 0
    `No models yet. fork_model needs a source; analyze_data scores a file without a model; import_data (ingest role) creates one from a file.`
    ? detail
    `Times are ISO-8601 UTC; on a count clock rows are numbered instead. Next: anomalies {model, last:"24h"} or anomaly_summary.`
    `Times are ISO-8601 UTC; on a count clock rows are numbered instead. columns is a count and versions_on the versions that judge — describe_model {model} names them, detail: true lists them here for every model. Next: anomalies {model, last:"24h"} or anomaly_summary.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// A categorical column's levels, fit for a context window: a short list
// whole, a long one (a time-of-day text, an id) as its count and a
// sample — 144 dummies listed twice tell a reader nothing the count
// does not.
: i MCP_CATS_WHOLE 12
: i MCP_CATS_SAMPLE 6
: i MCP_FEATS_WHOLE 40

@ __mcp_cats_brief Json cats → Json {
    : Json out ( json_obj_new )
    ( json_obj_each cats \ s col Json lv → v {
        : i n ( json_arr_len lv )
        ? <= n MCP_CATS_WHOLE { ( json_obj_set out col ( json_clone lv ) ) } {
            : Json o ( json_obj_new )
            ( json_obj_set o `levels` ( json_int n ) )
            : Json smp ( json_arr_new )
            : ~ i k 0
            ~ < k MCP_CATS_SAMPLE {
                ?? ( json_arr_get lv k ) { T x → { ( json_arr_push smp ( json_clone x ) ) } F _ → {} }
                = k + k 1
            }
            ( json_obj_set o `sample` smp )
            ( json_obj_set o `note` ( json_str_lit `a level this many-valued is one feature per value; a time or an id read as text is better dropped from the model (fork_model with fields) or encoded as a number` ) )
            ( json_obj_set out col o )
        }
    } )
    ^ out
}

// The feature order, whole when short; otherwise its count, the first
// names and how many were left out.
@ __mcp_feats_brief Json feats → Json {
    : Json out ( json_obj_new )
    : i n ( json_arr_len feats )
    ( json_obj_set out `count` ( json_int n ) )
    ? <= n MCP_FEATS_WHOLE { ( json_obj_set out `names` ( json_clone feats ) ) } {
        : Json names ( json_arr_new )
        : ~ i k 0
        ~ < k MCP_FEATS_WHOLE {
            ?? ( json_arr_get feats k ) { T x → { ( json_arr_push names ( json_clone x ) ) } F _ → {} }
            = k + k 1
        }
        ( json_obj_set out `names` names )
        ( json_obj_set out `omitted` ( json_int - n MCP_FEATS_WHOLE ) )
    }
    ^ out
}

// One model's metadata as a reader sees it. `describe_model` and
// `edit_model` are two doors onto the same thing, so they answer with the
// same shape: the write tool used to hand back the raw record — the
// scaler, the score epoch, the positional flatline arrays — while the
// read tool showed less than it, and a reader had to edit something to
// see what a model held.
@ __mcp_model_desc Json b → Json {
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `alias` out )
    ( __mcp_copy b `owner` out )
    ( json_obj_set out `scratch` ( json_bool ( az_is_scratch_model ( __mcp_ctx_str b `model_name` ) ) ) )
    ( __mcp_copy b `clock` out )
    ( __mcp_copy b `created` out )
    ( __mcp_copy b `column_types` out )
    ?? ( json_obj_get b `categories` ) { T c → { ( json_obj_set out `categories` ( __mcp_cats_brief c ) ) } F _ → {} }
    ?? ( json_obj_get b `feature_names` ) { T f → { ( json_obj_set out `features` ( __mcp_feats_brief f ) ) } F _ → {} }
    ( __mcp_copy b `n_points_seen` out )
    ( __mcp_copy b `n_points_stored` out )
    ( __mcp_copy b `max_data_points` out )
    ( __mcp_training_of b out )
    ( __mcp_copy b `schedule` out )
    ( __mcp_copy b `votes` out )
    ( __mcp_copy b `versions` out )
    ?? ( json_obj_get b `autoencoder` ) {
        T ae → {
            : Json ao ( json_obj_new )
            ( __mcp_copy ae `trained` ao )
            ( __mcp_copy ae `enabled` ao )
            ( __mcp_copy_rounded ae `reconstruction_threshold` ao 5 )
            ( __mcp_copy ae `decision_margin` ao )
            ( __mcp_copy_rounded ae `effective_margin` ao 5 )
            ( __mcp_copy ae `training_data_points` ao )
            ( __mcp_copy ae `layer_sizes` ao )
            ( __mcp_when_of ae `trained_at` ao `trained` F )
            ?? ( json_obj_get ae `retrain_required` ) {
                T v → { ? ( json_as_bool v ) {
                        ( json_obj_set ao `retrain_required` ( json_bool T ) )
                        ( json_obj_set ao `note` ( json_str_lit `The net was trained on a feature order the model no longer encodes; it gives no verdict until train_autoencoder or the next retrain replaces it.` ) )
                    } {} }
                F _ → {}
            }
            ( json_obj_set out `autoencoder` ao )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `flatline` ) {
        T fl → {
            : Json fo ( json_obj_new )
            ( __mcp_copy fl `enabled` fo )
            ( __mcp_copy fl `margin` fo )
            ( __mcp_copy fl `window_rows` fo )
            ( __mcp_copy fl `columns` fo )
            ( __mcp_copy fl `unwatched` fo )
            ( __mcp_copy fl `note` fo )
            ( json_obj_set out `flatline` fo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `forecast` ) {
        T fc → {
            : Json fo ( json_obj_new )
            ( __mcp_copy fc `trained` fo )
            ( __mcp_copy fc `enabled` fo )
            ( __mcp_copy fc `season` fo )
            ( __mcp_copy fc `features` fo )
            ( __mcp_copy fc `skipped` fo )
            ( __mcp_copy fc `training_data_points` fo )
            ( __mcp_when_of fc `trained_at` fo `trained` F )
            ( json_obj_set out `forecast` fo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `absurd_readings` ) {
        T ab → { ? > ( __mcp_obj_len ab ) 0 { ( json_obj_set out `absurd_readings` ( json_clone ab ) ) } {} }
        F _ → {}
    }
    ( __mcp_copy b `editable_fields` out )
    ^ out
}

@ __mcp_t_describe_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String path ( __mcp_model_path `/models/dynamic/` model `/metadata` )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ( string_free path )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( __mcp_model_desc . o body )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// ── Tools: anomalies ─────────────────────────────────────────────────

// The scan behind `anomalies` and `anomaly_summary`: every flagged row of
// the window (the API's row cap lifted), with values and attribution.
@ __mcp_scan Json a Json ctx String model i rows i contrib b only_anomalies → ApiOut {
    : String q ( string_new )
    : Json werr ( __mcp_q_window a q )
    ? ( json_is_null werr ) {} {
        ( string_free q )
        ^ @ ApiOut { 0 werr }
    }
    ? only_anomalies { ( __mcp_q_add q `only` `anomalies` ) } {}
    : i votes ( __mcp_arg_int a `min_votes` 1 )
    ? > votes 1 { ( __mcp_q_add_int q `votes` votes ) } {}
    ( __mcp_q_add q `group` `runs` )
    ( __mcp_q_add q `limit` `all` )
    ? > rows 0 { ( __mcp_q_add_int q `rows` rows ) } {}
    : String vers ( __mcp_arg_csv a `versions` )
    ? > ( string_len vers ) 0 { ( __mcp_q_add q `versions` ( string_data vers ) ) } {}
    ( string_free vers )
    : String fields ( __mcp_arg_csv a `fields` )
    ( __mcp_q_add q `fields` ? > ( string_len fields ) 0 ( string_data fields ) `*` )
    ( string_free fields )
    ( __mcp_q_add_int q `contrib` contrib )
    : String path ( __mcp_model_path `/models/dynamic/` model `/anomalies` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ^ o
}

// A scan row for a reader.
@ __mcp_row_json Json r b count_clock → Json {
    : Json o ( json_obj_new )
    ( __mcp_copy r `index` o )
    ( __mcp_when_of r `timestamp` o `time` count_clock )
    ( __mcp_copy_rounded r `score` o 4 )
    ( __mcp_copy_rounded r `severity` o 3 )
    ( __mcp_copy r `anomaly` o )
    ( __mcp_copy r `votes` o )
    ?? ( json_obj_get r `run` ) {
        T ru → { ( json_obj_set o `event` ( json_int ( json_as_int ru ) ) ) }
        F _ → {}
    }
    ( __mcp_copy r `label` o )
    ( __mcp_copy r `versions` o )
    ?? ( json_obj_get r `values` ) {
        T vals → { ( json_obj_set o `values` ( __mcp_round_obj vals 4 ) ) }
        F _ → {}
    }
    ?? ( json_obj_get r `contributions` ) {
        T cs → {
            : Json arr ( json_arr_new )
            ( json_arr_each cs \ Json c → v {
                : Json co ( json_obj_new )
                ( __mcp_copy c `feature` co )
                ( __mcp_copy_rounded c `value` co 4 )
                ( __mcp_copy_rounded c `expected` co 4 )
                ( __mcp_copy_rounded c `share` co 3 )
                ( json_arr_push arr co )
            } )
            ( json_obj_set o `contributions` arr )
            // Blame from the autoencoder is reconstruction error per
            // field, and a broken RELATION puts error on both ends of it:
            // when a temperature freezes, the net's humidity prediction —
            // which it learnt to make from the temperature — goes wrong
            // too, and can carry the larger share. Naming one field there
            // sends a reader to the wrong sensor. When the top two shares
            // are of the same order, the finding is the pair.
            ? >= ( json_arr_len arr ) 2 {
                : f s0 ( __mcp_share_at arr 0 )
                : f s1 ( __mcp_share_at arr 1 )
                ? & > s0 0.0 >= s1 * 0.5 s0 {
                    : String m ( string_from `` )
                    ( string_push_str m ( __mcp_feat_at arr 0 ) )
                    ( string_push_str m ` and ` )
                    ( string_push_str m ( __mcp_feat_at arr 1 ) )
                    ( string_push_str m ` carry the blame together: what broke is the relation between them, not necessarily the field with the larger share — the net predicts each from the other, so the field that FOLLOWED a failure is blamed as loudly as the one that failed. A version that judges one field alone (range_guard, flatline, forecast) names the culprit when there is a single one; see this row's versions.` )
                    ( json_obj_set o `blame` ( json_str_lit ( string_data m ) ) )
                    ( string_free m )
                } {}
            } {}
        }
        F _ → {}
    }
    ^ o
}

@ __mcp_share_at Json arr i k → f {
    ?? ( json_arr_get arr k ) {
        T c → { ^ ( __mcp_f_of c `share` ) }
        F _ → { ^ 0.0 }
    }
}

@ __mcp_feat_at Json arr i k → s {
    ?? ( json_arr_get arr k ) {
        T c → { ^ ( __mcp_ctx_str c `feature` ) }
        F _ → { ^ `` }
    }
}

// The window as the API saw it (data_points_count / considered /
// anomalies), so a partial listing says what it is a part of.
@ __mcp_scan_summary Json b Json out → v {
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `clock` out )
    ( json_obj_set out `points_in_window` ( json_int ( __mcp_int_of b `considered` ) ) )
    ( json_obj_set out `anomalies_in_window` ( json_int ( __mcp_int_of b `anomalies` ) ) )
    ( json_obj_set out `events_in_window` ( json_int ( __mcp_int_of b `runs` ) ) )
    ( json_obj_set out `points_stored` ( json_int ( __mcp_int_of b `data_points_count` ) ) )
    : i votes ( __mcp_int_of b `votes` )
    ? > votes 1 { ( json_obj_set out `min_votes` ( json_int votes ) ) } {}
    ( __mcp_copy b `model_versions` out )
}

// A filter that can never match is a caller's mistake, and answering it
// with "0 anomalies" reads as good news. The scan body names every
// version the model judges with, so the impossible ask can be refused
// with the number that makes it impossible.
@ __mcp_votes_impossible Json b i votes → Json {
    ?? ( json_obj_get b `model_versions` ) {
        T mv → {
            ? ( json_is_arr mv ) {
                : i n ( json_arr_len mv )
                ? > votes n {
                    : String m ( string_from `min_votes: ` )
                    ( string_push_int m votes )
                    ( string_push_str m ` — the model judges with ` )
                    ( string_push_int m n )
                    ( string_push_str m ` version` )
                    ? > n 1 { ( string_push_char m 115 ) } {}
                    ( string_push_str m `, so no row can carry that many votes. describe_model lists them; 2 is the usual "more than one version agrees".` )
                    : Json e ( mcp_tool_result_error ( string_data m ) )
                    ( string_free m )
                    ^ e
                } {}
            } {}
        }
        F _ → {}
    }
    ^ ( json_null )
}

@ __mcp_int_of Json o s key → i {
    ?? ( json_obj_get o key ) {
        T v → { ^ ( json_as_int v ) }
        F _ → { ^ 0 }
    }
}

@ __mcp_t_anomalies Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : i asked ( __mcp_arg_int a `count` 20 )
    : ~ i count asked
    ? <= count 0 { = count 20 } {}
    ? > count 200 { = count 200 } {}
    : ~ i contrib ( __mcp_arg_int a `contributions` 3 )
    ? < contrib 0 { = contrib 0 } {}
    : b all_points ( __mcp_arg_bool a `all_points` F )
    : ApiOut o ( __mcp_scan a ctx model count contrib ! all_points )
    ( string_free model )
    ? == . o status 0 { ^ . o body } {}
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json vbad ( __mcp_votes_impossible b ( __mcp_arg_int a `min_votes` 1 ) )
    ? ( json_is_null vbad ) {} { ( __mcp_api_out_free o ) ^ vbad }
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_scan_summary b out )
    // A count the tool had to cut is said out loud: a caller who asked
    // for 9999 and got 200 must not read the answer as the whole window.
    ? > asked count {
        : String cm ( string_from `count: ` )
        ( string_push_int cm asked )
        ( string_push_str cm ` is past the cap of 200 rows a tool answer carries; 200 were listed. Narrow the window (from/to/last) or read anomaly_summary for the whole of it.` )
        ( json_obj_set out `count_capped` ( json_str_lit ( string_data cm ) ) )
        ( string_free cm )
    } {}
    : Json rows ( json_arr_new )
    ?? ( json_obj_get b `points` ) {
        T pts → { ( json_arr_each pts \ Json r → v { ( json_arr_push rows ( __mcp_row_json r cc ) ) } ) }
        F _ → {}
    }
    : i shown ( json_arr_len rows )
    : i total ? all_points ( __mcp_int_of b `considered` ) ( __mcp_int_of b `anomalies` )
    ( json_obj_set out `returned` ( json_int shown ) )
    // under a versions / min_votes filter the window's count is over
    // every version: a short answer is the filter's doing, not the count's
    : b filtered | ( __mcp_arg_has a `versions` ) ( __mcp_arg_has a `min_votes` )
    ? & filtered > total shown {
        : String fnote ( string_from `the filter (versions / min_votes) kept ` )
        ( string_push_int fnote shown )
        ( string_push_str fnote ` of the ` )
        ( string_push_int fnote total )
        ( string_push_str fnote ` anomalies the window holds over every version` )
        ( json_obj_set out `note` ( json_str_lit ( string_data fnote ) ) )
        ( string_free fnote )
    } {}
    ? & ! filtered > total shown {
        : String note ( string_from `the newest ` )
        ( string_push_int note shown )
        ( string_push_str note ? all_points ` points of ` ` anomalies of ` )
        ( string_push_int note total )
        ( string_push_str note ` in the window — raise count (max 200), or narrow from/to/last` )
        ( json_obj_set out `note` ( json_str_lit ( string_data note ) ) )
        ( string_free note )
    } {}
    ( json_obj_set out `rows` rows )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// Events shown in an anomaly_summary; the count is always there.
: i MCP_EVENTS_SHOWN 10

// Which of `buckets` equal slices of [first, first + span] a stamp
// falls in; the last slice takes its own end.
@ __mcp_bucket_of i ts i first i span i buckets → i {
    : ~ i bi / * - ts first buckets span
    ? >= bi buckets { = bi - buckets 1 } {}
    ? < bi 0 { = bi 0 } {}
    ^ bi
}

// Per-feature attribution totals across the flagged rows.
: FeatShare {
    String name
    f share
    i n
}

@ __mcp_t_anomaly_summary Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ~ i buckets ( __mcp_arg_int a `buckets` 12 )
    ? <= buckets 0 { = buckets 12 } {}
    ? > buckets 48 { = buckets 48 } {}
    : ApiOut o ( __mcp_scan a ctx model 0 3 T )
    ( string_free model )
    ? == . o status 0 { ^ . o body } {}
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json vbad ( __mcp_votes_impossible b ( __mcp_arg_int a `min_votes` 1 ) )
    ? ( json_is_null vbad ) {} { ( __mcp_api_out_free o ) ^ vbad }
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_scan_summary b out )
    : i considered ( __mcp_int_of b `considered` )
    : i nanom ( __mcp_int_of b `anomalies` )
    : ~ f rate 0.0
    ? > considered 0 { = rate / # f nanom # f considered } {}
    ( json_obj_set out `anomaly_rate` ( __mcp_round_f rate 4 ) )

    // One pass over the flagged rows: time span, per-version counts,
    // per-feature attribution, the worst score.
    // Every version starts at zero, so "this version flagged nothing" and
    // "there is no such version" are different answers. Leaving the zeros
    // out made a quiet version indistinguishable from an absent one, and
    // a reader chasing "which version is loud" could not tell whether the
    // one it expected was even enabled.
    : Json per_version ( json_obj_new )
    ?? ( json_obj_get b `model_versions` ) {
        T mv → {
            ? ( json_is_arr mv ) {
                ( json_arr_each mv \ Json vn → v {
                    ( json_obj_set per_version ( json_as_str vn ) ( json_int 0 ) )
                } )
            } {}
        }
        F _ → {}
    }
    : ( Vec FeatShare ) feats ( vec_new [FeatShare] )
    : ~ i first_ts 0
    : ~ i last_ts 0
    // The worst row is the one farthest past its alert line: highest
    // severity (−score / margin), which is comparable across versions
    // where a raw score is not (a forest's ~1e-1 next to the
    // autoencoder's ~1e-4).
    : ~ f worst 0.0
    : ~ f worst_sev 0.0
    : ~ i worst_idx -1
    : ~ i worst_ts 0
    : ~ i n_fp 0
    : ~ i n_ok 0
    : ( Vec i ) stamps ( vec_new [i] )
    ?? ( json_obj_get b `points` ) {
        T pts → {
            : i np ( json_arr_len pts )
            : ~ i pi 0
            ~ < pi np {
                ?? ( json_arr_get pts pi ) {
                    T r → {
                        : i ts ( __mcp_int_of r `timestamp` )
                        ( vec_push [i] stamps ts )
                        : s lab ( __mcp_ctx_str r `label` )
                        ? == ( nurl_str_eq lab ANOM_LABEL_FP ) 1 { = n_fp + n_fp 1 } {}
                        ? == ( nurl_str_eq lab ANOM_LABEL_OK ) 1 { = n_ok + n_ok 1 } {}
                        ? | == first_ts 0 < ts first_ts { = first_ts ts } {}
                        ? > ts last_ts { = last_ts ts } {}
                        : f sc ( __mcp_f_of r `score` )
                        : f sv ( __mcp_f_of r `severity` )
                        ? | < worst_idx 0 > sv worst_sev { = worst sc = worst_sev sv = worst_idx ( __mcp_int_of r `index` ) = worst_ts ts } {}
                        ?? ( json_obj_get r `versions` ) {
                            T vs → {
                                ( json_arr_each vs \ Json vn → v {
                                    : s name ( json_as_str vn )
                                    : i cur ( __mcp_int_of per_version name )
                                    ( json_obj_set per_version name ( json_int + cur 1 ) )
                                } )
                            }
                            F _ → {}
                        }
                        ?? ( json_obj_get r `contributions` ) {
                            T cs → {
                                ( json_arr_each cs \ Json c → v {
                                    : s fname ( __mcp_ctx_str c `feature` )
                                    : f share ( __mcp_f_of c `share` )
                                    ( __mcp_feat_add feats fname share )
                                } )
                            }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
                = pi + pi 1
            }
        }
        F _ → {}
    }
    ( json_obj_set out `by_version` per_version )
    ? > + n_fp n_ok 0 {
        : Json lj ( json_obj_new )
        ( json_obj_set lj `false_positive` ( json_int n_fp ) )
        ( json_obj_set lj `confirmed` ( json_int n_ok ) )
        ( json_obj_set out `labelled` lj )
    } {}
    ? > nanom 0 {
        ( json_obj_set out `first_anomaly` ( __mcp_when first_ts cc ) )
        ( json_obj_set out `latest_anomaly` ( __mcp_when last_ts cc ) )
        : Json w ( json_obj_new )
        ( json_obj_set w `index` ( json_int worst_idx ) )
        ( json_obj_set w `time` ( __mcp_when worst_ts cc ) )
        ( json_obj_set w `score` ( __mcp_round_f worst 4 ) )
        ( json_obj_set w `severity` ( __mcp_round_f worst_sev 3 ) )
        ( json_obj_set out `worst` w )
    } {}

    // Events: the runs of consecutive anomalous rows, newest first —
    // a hundred flagged rows may be three of these. The run starts are
    // kept for the timeline.
    : ( Vec i ) starts ( vec_new [i] )
    ?? ( json_obj_get b `events` ) {
        T evs → {
            : i ne ( json_arr_len evs )
            : Json list ( json_arr_new )
            : ~ i ei - ne 1
            ~ >= ei 0 {
                ?? ( json_arr_get evs ei ) {
                    T ev → {
                        ( vec_push [i] starts ( __mcp_int_of ev `from` ) )
                        ? < ( json_arr_len list ) MCP_EVENTS_SHOWN {
                            : Json eo ( json_obj_new )
                            ( json_obj_set eo `event` ( json_int ( __mcp_int_of ev `run` ) ) )
                            ( __mcp_copy ev `rows` eo )
                            ( __mcp_when_of ev `from` eo `from` cc )
                            ( __mcp_when_of ev `to` eo `to` cc )
                            ( __mcp_copy ev `from_index` eo )
                            ( __mcp_copy ev `to_index` eo )
                            ( __mcp_copy ev `worst_index` eo )
                            ( __mcp_copy_rounded ev `worst_score` eo 4 )
                            ( __mcp_copy_rounded ev `worst_severity` eo 3 )
                            ( __mcp_copy ev `versions` eo )
                            ( json_arr_push list eo )
                        } {}
                    }
                    F _ → {}
                }
                = ei - ei 1
            }
            ( json_obj_set out `events` list )
            ? > ne MCP_EVENTS_SHOWN {
                : String note ( string_from `the newest ` )
                ( string_push_int note MCP_EVENTS_SHOWN )
                ( string_push_str note ` events of ` )
                ( string_push_int note ne )
                ( string_push_str note ` in the window — anomalies lists every row with its event; narrow from/to/last for the rest` )
                ( json_obj_set out `events_note` ( json_str_lit ( string_data note ) ) )
                ( string_free note )
            } {}
        }
        F _ → {}
    }

    // Timeline: the flagged rows and the event starts counted into
    // `buckets` equal slices between the first and the latest flagged
    // row.
    : i nst ( vec_len [i] stamps )
    ? & > nst 1 > last_ts first_ts {
        : Json tl ( json_arr_new )
        : i span - last_ts first_ts
        : ( Vec i ) counts ( vec_new [i] )
        : ( Vec i ) ecounts ( vec_new [i] )
        : ~ i k 0
        ~ < k buckets { ( vec_push [i] counts 0 ) ( vec_push [i] ecounts 0 ) = k + k 1 }
        = k 0
        ~ < k nst {
            : i bi ( __mcp_bucket_of ( __mcp_iget stamps k ) first_ts span buckets )
            : b _s ( vec_set [i] counts bi + ( __mcp_iget counts bi ) 1 )
            = k + k 1
        }
        = k 0
        : i nstarts ( vec_len [i] starts )
        ~ < k nstarts {
            : i bi ( __mcp_bucket_of ( __mcp_iget starts k ) first_ts span buckets )
            : b _s ( vec_set [i] ecounts bi + ( __mcp_iget ecounts bi ) 1 )
            = k + k 1
        }
        = k 0
        ~ < k buckets {
            : i bstart + first_ts / * k span buckets
            : Json bo ( json_obj_new )
            ( json_obj_set bo `from` ( __mcp_when bstart cc ) )
            ( json_obj_set bo `anomalies` ( json_int ( __mcp_iget counts k ) ) )
            ( json_obj_set bo `events` ( json_int ( __mcp_iget ecounts k ) ) )
            ( json_arr_push tl bo )
            = k + k 1
        }
        ( vec_free [i] counts )
        ( vec_free [i] ecounts )
        ( json_obj_set out `timeline` tl )
    } {}
    ( vec_free [i] stamps )
    ( vec_free [i] starts )

    // The features the autoencoder blamed most, by mean share.
    : i nf ( vec_len [FeatShare] feats )
    ? > nf 0 {
        : Json top ( json_arr_new )
        : ~ i taken 0
        ~ & < taken 5 < taken nf {
            : ~ i best -1
            : ~ f best_mean -1.0
            : ~ i k 0
            ~ < k nf {
                ?? ( vec_get [FeatShare] feats k ) {
                    T fs → {
                        ? > . fs n 0 {
                            : f mean / . fs share # f . fs n
                            ? > mean best_mean { = best_mean mean = best k } {}
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ? >= best 0 {
                ?? ( vec_get [FeatShare] feats best ) {
                    T fs → {
                        : Json fo ( json_obj_new )
                        ( json_obj_set fo `feature` ( json_str_lit ( string_data . fs name ) ) )
                        ( json_obj_set fo `mean_share` ( __mcp_round_f best_mean 3 ) )
                        ( json_obj_set fo `in_anomalies` ( json_int . fs n ) )
                        ( json_arr_push top fo )
                        // Taken: mark by zeroing the count.
                        : b _s ( vec_set [FeatShare] feats best @ FeatShare { . fs name . fs share 0 } )
                    }
                    F _ → {}
                }
            } {}
            = taken + taken 1
        }
        ( json_obj_set out `top_features` top )
    } {}
    ( vec_free_with [FeatShare] feats \ FeatShare x → v { ( string_free . x name ) } )

    // Health: what the window says about the model itself. A rate of
    // nothing or of everything is a margin problem or a stale version,
    // not a fact about the stream; a window of rows all stamped the same
    // second was imported without its time.
    : Json warn ( json_arr_new )
    ? > considered 0 {
        ? == nanom 0 {
            ( json_arr_push warn ( json_str_lit `no row in the window is flagged: margins may be loose for this data — calibration shows the rate each margin would give, finetune {rate: 0.01} sets them` ) )
        } {}
        ? >= rate 0.5 {
            : String s ( string_from `the model flags ` )
            ( string_push_int s # i ( float_round * rate 100.0 ) )
            ( string_push_str s ` % of the window: a margin this tight, or a version trained on data unlike this window, says nothing about the stream — see which version below, then finetune {rate: 0.01} or retrain` )
            ( json_arr_push warn ( json_str_lit ( string_data s ) ) )
            ( string_free s )
        } {}
        ?? ( json_obj_get b `flagged_by_version` ) {
            T fbv → {
                ( json_obj_each fbv \ s vn Json cnt → v {
                    : i c ( json_as_int cnt )
                    ? >= * c 2 considered {
                        ? >= rate 0.5 {} {
                            : String s ( string_from vn )
                            ( string_push_str s ` flags ` )
                            ( string_push_int s c )
                            ( string_push_str s ` of ` )
                            ( string_push_int s considered )
                            ( string_push_str s ` rows in the window` )
                            ? ( _an_is_flat_name vn ) { ( string_push_str s `: a column stood still for that long — a sensor to check, not a margin to move` ) } {}
                            ( json_arr_push warn ( json_str_lit ( string_data s ) ) )
                            ( string_free s )
                        }
                    } {}
                } )
            }
            F _ → {}
        }
        ?? ( json_obj_get b `window` ) {
            T wj → {
                : ~ b one F
                ?? ( json_obj_get wj `one_time` ) { T v → { = one ( json_as_bool v ) } F _ → {} }
                ? & one > considered 1 {
                    ( json_arr_push warn ( json_str_lit `every row in the window carries the same timestamp — a file imported without its time column named does this — so the time windows (short_term, daily, weekly, seasonal) all see one instant; re-import with the time column named, or fork with a count clock` ) )
                } {}
            }
            F _ → {}
        }
    } {}
    ? > ( json_arr_len warn ) 0 { ( json_obj_set out `warnings` warn ) } { ( json_free warn ) }
    ( json_obj_set out `next` ( json_str_lit `anomalies {model, count, from/to/last} lists the rows; point {model, index} shows one in full; calibration shows how the margins sit.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_f_of Json o s key → f {
    ?? ( json_obj_get o key ) {
        T v → {
            ?? ( json_num_as_f v ) { T x → { ^ x } F → { ^ 0.0 } }
        }
        F _ → { ^ 0.0 }
    }
}

@ __mcp_feat_add ( Vec FeatShare ) feats s name f share → v {
    : i n ( vec_len [FeatShare] feats )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [FeatShare] feats k ) {
            T fs → {
                ? == ( nurl_str_eq ( string_data . fs name ) name ) 1 {
                    : b _s ( vec_set [FeatShare] feats k @ FeatShare { . fs name + . fs share share + . fs n 1 } )
                    ^
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_push [FeatShare] feats @ FeatShare { ( string_from name ) share 1 } )
}

@ __mcp_iget ( Vec i ) v i idx → i {
    ?? ( vec_get [i] v idx ) { T x → { ^ x } F _ → { ^ 0 } }
}

// ── Tools: points ────────────────────────────────────────────────────

// Rows of the ring: `{index, time, <fields…>}` per row, newest last.
// A stored row for a reader: `index` and `time` are the row's place in
// the ring and its stamp, and the columns live under `values` — so a
// column called "time" or "index" (a Finnish "Aika" imported as time, a
// counter named index) can never overwrite the row's own coordinates. The
// same shape the anomalies rows use.
@ __mcp_data_rows Json b → Json {
    : b cc ( __mcp_count_clock b )
    : Json rows ( json_arr_new )
    ?? ( json_obj_get b `data` ) {
        T data → {
            : Json idxs ? ( json_obj_has b `indices` ) ( json_clone ( __mcp_val b `indices` ) ) ( json_arr_new )
            : i n ( json_arr_len data )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get data k ) {
                    T rec → {
                        : Json row ( json_obj_new )
                        ?? ( json_arr_get idxs k ) {
                            T ix → { ( json_obj_set row `index` ( json_clone ix ) ) }
                            F _ → {}
                        }
                        ( __mcp_when_of rec `timestamp` row `time` cc )
                        : Json vals ( json_obj_new )
                        ( json_obj_each rec \ s key Json v → v {
                            ? == ( nurl_str_eq key `timestamp` ) 1 {} {
                                ? ( json_is_num v ) { ( json_obj_set vals key ( __mcp_round v 4 ) ) }
                                { ( json_obj_set vals key ( json_clone v ) ) }
                            }
                        } )
                        ( json_obj_set row `values` vals )
                        ( json_arr_push rows row )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( json_free idxs )
        }
        F _ → {}
    }
    ^ rows
}

// The value under `key`, or JSON null (borrowed).
@ __mcp_val Json o s key → Json {
    ?? ( json_obj_get o key ) { T v → { ^ v } F _ → { ^ @ Json { JNull } } }
}

@ __mcp_t_points Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ~ i count ( __mcp_arg_int a `count` 20 )
    ? <= count 0 { = count 20 } {}
    ? > count 500 { = count 500 } {}
    : String q ( string_new )
    : Json werr ( __mcp_q_window a q )
    ? ( json_is_null werr ) {} { ( string_free q ) ( string_free model ) ^ werr }
    ( __mcp_q_add_int q `limit` count )
    : String fields ( __mcp_arg_csv a `fields` )
    ? > ( string_len fields ) 0 { ( __mcp_q_add q `fields` ( string_data fields ) ) } {}
    ( string_free fields )
    : String path ( __mcp_model_path `/models/dynamic/` model `/data` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `clock` out )
    ( json_obj_set out `points_stored` ( json_int ( __mcp_int_of b `data_points_count` ) ) )
    ( json_obj_set out `points_in_window` ( json_int ( __mcp_int_of b `in_window` ) ) )
    : Json rows ( __mcp_data_rows b )
    : i shown ( json_arr_len rows )
    ( json_obj_set out `returned` ( json_int shown ) )
    : i inw ( __mcp_int_of b `in_window` )
    ? > inw shown {
        : String note ( string_from `the newest ` )
        ( string_push_int note shown )
        ( string_push_str note ` of ` )
        ( string_push_int note inw )
        ( string_push_str note ` points in the window — raise count (max 500) or narrow from/to/last` )
        ( json_obj_set out `note` ( json_str_lit ( string_data note ) ) )
        ( string_free note )
    } {}
    ( json_obj_set out `rows` rows )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ? ( __mcp_arg_has a `index` ) {} { ( string_free model ) ^ ( mcp_tool_result_error `index: required — the ring index an anomalies row carries` ) }
    : i idx ( __mcp_arg_int a `index` -1 )
    ? >= idx 0 {} { ( string_free model ) ^ ( mcp_tool_result_error `index: a non-negative integer` ) }
    : String q ( string_new )
    ( __mcp_q_add_int q `at` idx )
    : String path ( __mcp_model_path `/models/dynamic/` model `/data` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json rows ( __mcp_data_rows . o body )
    ? > ( json_arr_len rows ) 0 {} {
        ( json_free rows )
        : String m ( string_from `no point at index ` )
        ( string_push_int m idx )
        ( string_push_str m ` — the ring holds ` )
        ( string_push_int m ( __mcp_int_of . o body `data_points_count` ) )
        ( string_push_str m ` points` )
        ( __mcp_api_out_free o )
        : Json e ( mcp_tool_result_error ( string_data m ) )
        ( string_free m )
        ^ e
    }
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `model_name` out )
    ( __mcp_copy . o body `clock` out )
    ?? ( json_arr_get rows 0 ) {
        T r → { ( json_obj_set out `point` ( json_clone r ) ) }
        F _ → {}
    }
    ( json_free rows )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// ── Tools: calibration and scoring ───────────────────────────────────

// Too quiet, too loud, or about right: the one-word reading of a flag
// rate over a window. A window too small to show 1 % says nothing. The
// alert rate a margin aims for is ANOM_FT_RATE (1 %); a version flagging
// nothing has no evidence it would flag anything, one flagging a tenth
// of the window is describing the window, not its anomalies.
// The flatline guard's margin has a fixed meaning (the fraction of the
// window a column has been stuck for), not a rate to aim at: a window
// where it flags nothing is a window where no column stuck, and a
// window where it flags a tenth is a column that was stuck a tenth of
// the time — neither says anything about the margin.
@ __mcp_flat_reading i n f rate → s {
    ? < n 100 { ^ `too few rows to read (under 100)` } {}
    ? == rate 0.0 { ^ `no column stuck in this window` } {}
    ^ `a column was stuck for this share of the window — see anomalies for which; the margin is a fraction with a fixed meaning, not a rate to tune`
}

// The band around ANOM_FT_RATE that counts as "on target": a third of it
// to three times it. A version flagging six rows in ten thousand is a
// seventeenth of what a 1 % margin aims for, and reading that back as "on
// target" told a reader the margin was set when it was loose enough to
// see almost nothing — the rule was, in effect, "flagged > 0".
@ __mcp_cal_reading i n f rate → s {
    ? < n 100 { ^ `too few rows to read (under 100)` } {}
    ? == rate 0.0 { ^ `quiet: flags nothing here — the margin may be loose; margin_for_rate shows the one for 1 %` } {}
    ? >= rate 0.1 { ^ `loud: flags a tenth or more of the window — the margin is too tight, or the version was trained on data unlike this; finetune {rate: 0.01} sets a margin from this window` } {}
    ? > rate 0.03 { ^ `louder than the 1 % a margin aims for` } {}
    ? < rate 0.0033 { ^ `quieter than the 1 % a margin aims for — this window is calmer than the one the margin came from, or the margin is loose; margin_for_rate shows the one for 1 %` } {}
    ^ `on target: near the 1 % a margin aims for`
}

@ __mcp_t_calibration Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_new )
    : Json werr ( __mcp_q_window a q )
    ? ( json_is_null werr ) {} { ( string_free q ) ( string_free model ) ^ werr }
    : String path ( __mcp_model_path `/models/dynamic/` model `/calibration` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_copy b `model` out )
    ( __mcp_copy b `clock` out )
    ?? ( json_obj_get b `window` ) {
        T w → {
            : Json wo ( json_obj_new )
            ( __mcp_when_of w `from` wo `from` cc )
            ( __mcp_when_of w `to` wo `to` cc )
            ( __mcp_copy w `rows` wo )
            ( __mcp_copy w `excluded` wo )
            ( __mcp_copy w `total` wo )
            ( json_obj_set out `window` wo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `aggregate` ) {
        T ag → {
            : Json ao ( json_obj_new )
            ( __mcp_copy ag `votes_required` ao )
            ( __mcp_copy ag `flagged` ao )
            ( __mcp_copy_rounded ag `rate` ao 4 )
            ( json_obj_set out `aggregate` ao )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `versions` ) {
        T vs → {
            : Json vo ( json_obj_new )
            ( json_obj_each vs \ s vn Json v → v {
                : Json one ( json_obj_new )
                ( __mcp_copy v `units` one )
                ( __mcp_copy v `margin` one )
                ( __mcp_copy v `n` one )
                ( __mcp_copy v `flagged` one )
                ( __mcp_copy_rounded v `rate` one 4 )
                ( __mcp_copy_rounded v `worst` one 4 )
                ( __mcp_copy_rounded v `median` one 4 )
                ? ( _an_is_flat_name vn ) {
                    ( json_obj_set one `reading` ( json_str_lit ( __mcp_flat_reading ( __mcp_int_of v `n` ) ( __mcp_f_of v `rate` ) ) ) )
                } {
                    ( json_obj_set one `reading` ( json_str_lit ( __mcp_cal_reading ( __mcp_int_of v `n` ) ( __mcp_f_of v `rate` ) ) ) )
                }
                ( __mcp_copy v `alert_line` one )
                ?? ( json_obj_get v `margin_for_rate` ) {
                    T mfr → {
                        : Json mo ( json_obj_new )
                        ( json_obj_each mfr \ s rk Json rv → v {
                            : Json ro ( json_obj_new )
                            ( __mcp_copy rv `margin` ro )
                            ( __mcp_copy rv `flagged` ro )
                            ( __mcp_copy rv `requested_rate` ro )
                            ( __mcp_copy_rounded rv `achieved_rate` ro 4 )
                            ( __mcp_copy rv `exact` ro )
                            ( json_obj_set mo rk ro )
                        } )
                        ( json_obj_set one `margin_for_rate` mo )
                    }
                    F _ → {}
                }
                ( json_obj_set vo vn one )
            } )
            ( json_obj_set out `versions` vo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `aggregate` ) {
        T ag → {
            : ~ i n 0
            ?? ( json_obj_get b `window` ) { T w → { = n ( __mcp_int_of w `rows` ) } F _ → {} }
            ( json_obj_set out `verdict` ( json_str_lit ( __mcp_cal_reading n ( __mcp_f_of ag `rate` ) ) ) )
        }
        F _ → {}
    }
    ( json_obj_set out `reading` ( json_str_lit `A version flags a row when its score is at or below -margin (score = decision function; the more negative, the more anomalous); rate = flagged / n over this window. margin_for_rate gives, per requested rate, the nearest margin the window's scores can supply: when scores tie at the cut the achieved rate differs from the requested one (exact = false) — a run of identical scores is taken or left whole. Margins are shown exactly as stored, in each version's own units (units: a forest's margin is absolute on its decision function; the autoencoder's is a fraction of its reconstruction threshold, and its scores here are scaled the same way; range_guard's is a count of standard deviations — its score is -max|z| over the features, and it names the feature; flatline's is a fraction of each column's OWN reference run — its score is minus the largest stuck fraction over the numeric columns, and it names the column). finetune {model, rate} sets them, the flatline excepted: its margin is not a rate, so it has no margin_for_rate table; alert_line says instead what the current margin asks of each column, in rows and in minutes, and edit_model sets it.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// The values object a scoring or ingest call sends: `values` as given.
@ __mcp_values_arg Json a → ?Json {
    ?? ( __mcp_arg a `values` ) {
        T v → { ? ( json_is_obj v ) { ^ @ ?Json { T v } } { ^ @ ?Json { F @ Json { JNull } } } }
        F _ → { ^ @ ?Json { F @ Json { JNull } } }
    }
}

@ __mcp_no_values → Json {
    ^ ( mcp_tool_result_error `values: required — an object of the model's columns, e.g. {"temperature": 21.5, "humidity": 40}` )
}

// A verdict for a reader: the aggregate, then each version with its
// score, severity and the margin it was held to. `decision_margin` — the
// number stored in the metadata, the one an edit or a fine-tune writes —
// goes out verbatim: a rounded setting is a different setting. `margin`
// is DERIVED from it (for the autoencoder, the reconstruction threshold
// times that fraction), so it is a computed number like the score beside
// it and is rounded like one; whole-precision it was the single
// unrounded figure in the whole answer and read as a different KIND of
// number rather than as the same one arrived at differently. The API's
// echo of the submitted values is dropped; the caller sent them. A model
// still collecting its first points says so instead of scoring.
@ __mcp_verdict_out ApiOut o b ingested → Json {
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_obj_new )
    ( __mcp_copy b `status` out )
    ( __mcp_copy b `model` out )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `message` out )
    ? ( json_obj_has b `anomaly` ) {
        ( __mcp_copy b `anomaly` out )
        ( __mcp_copy_rounded b `score` out 4 )
        ( __mcp_copy_rounded b `severity` out 3 )
        ( __mcp_copy b `missing` out )
        ?? ( json_obj_get b `versions` ) {
            T vers → {
                : Json vo ( json_obj_new )
                ( json_obj_each vers \ s name Json vv → v {
                    : Json e ( json_obj_new )
                    ( __mcp_copy vv `anomaly` e )
                    ( __mcp_copy_rounded vv `score` e 4 )
                    ( __mcp_copy_rounded vv `severity` e 3 )
                    ( __mcp_copy vv `feature` e )
                    ?? ( json_obj_get vv `threshold_info` ) {
                        T ti → {
                            : Json t ( json_obj_new )
                            ( __mcp_copy_rounded ti `margin` t 6 )
                            ( __mcp_copy ti `decision_margin` t )
                            ( __mcp_copy ti `units` t )
                            ( json_obj_set e `threshold_info` t )
                        }
                        F _ → {}
                    }
                    ( json_obj_set vo name e )
                } )
                ( json_obj_set out `versions` vo )
            }
            F _ → {}
        }
    } {
        ( __mcp_copy b `min_data_points` out )
    }
    ( json_obj_set out `points_stored` ( json_int ( __mcp_int_of b `data_points` ) ) )
    ( json_obj_set out `stored` ( json_bool ingested ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_score_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ?Json vals ( __mcp_values_arg a )
    ?? vals {
        T v → {
            : String q ( string_new )
            : String path ( __mcp_model_path `/detect_only/` model `` )
            : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T v } )
            ( string_free path )
            ( string_free q )
            ( string_free model )
            ^ ( __mcp_verdict_out o F )
        }
        F _ → { ( string_free model ) ^ ( __mcp_no_values ) }
    }
}

@ __mcp_t_ingest_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ?Json vals ( __mcp_values_arg a )
    ?? vals {
        T v → {
            : String q ( string_new )
            : String path ( __mcp_model_path `/detect/` model `` )
            : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T v } )
            ( string_free path )
            ( string_free q )
            ( string_free model )
            ^ ( __mcp_verdict_out o T )
        }
        F _ → { ( string_free model ) ^ ( __mcp_no_values ) }
    }
}

// ── Tools: files, tasks, analyses ────────────────────────────────────

// A record listing, passed through with every wall-clock key spelt as a
// moment rather than as Unix seconds.
@ __mcp_t_get Json ctx s path → Json {
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` path q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( __mcp_iso_times . o body )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_task Json a Json ctx → Json {
    : String id ( __mcp_arg_str a `id` )
    ? > ( string_len id ) 0 {} { ( string_free id ) ^ ( mcp_tool_result_error `id: required — a task_id from list_tasks or analyze_data` ) }
    : String path ( __mcp_model_path `/api/org/tasks/` id `` )
    : Json out ( __mcp_t_get ctx ( string_data path ) )
    ( string_free path )
    ( string_free id )
    ^ out
}

// The file to analyse or import: `csv` text, or `rows` (an array of
// objects) sent as JSON. Returns the content type, `` when neither.
// The file to work on: inline `csv` text, inline `rows`, or the name of
// one the organisation's folder already holds. A folder file leaves
// `text` empty and answers `folder`; the caller then puts the name on the
// query string and sends no body.
@ __mcp_file_arg Json a String text → s {
    : String fname ( __mcp_arg_str a `file` )
    ? > ( string_len fname ) 0 { ( string_free fname ) ^ `folder` } {}
    ( string_free fname )
    : String csv ( __mcp_arg_str a `csv` )
    ? > ( string_len csv ) 0 {
        ( string_push_str text ( string_data csv ) )
        ( string_free csv )
        ^ `text/csv`
    } {}
    ( string_free csv )
    ?? ( __mcp_arg a `rows` ) {
        T rows → {
            ? ( json_is_arr rows ) {
                : String js ( json_stringify rows )
                ( string_push_str text ( string_data js ) )
                ( string_free js )
                ^ `application/json`
            } {}
        }
        F _ → {}
    }
    ^ ``
}

@ __mcp_no_file → Json {
    ^ ( mcp_tool_result_error `csv, rows or file: required — csv is the file's text (header row first), rows an array of objects one per point, file the name of one the organisation's folder already holds (list_files shows them)` )
}

// The import/analyze query the two share: format, time, tz, calendar, clock.
@ __mcp_q_file Json a String q s content_type → v {
    ? == ( nurl_str_eq content_type `folder` ) 1 {
        : String fname ( __mcp_arg_str a `file` )
        ( __mcp_q_add q `file` ( string_data fname ) )
        ( string_free fname )
    } {}
    : String fmt ( __mcp_arg_str a `format` )
    ? > ( string_len fmt ) 0 { ( __mcp_q_add q `format` ( string_data fmt ) ) } {
        ? == ( nurl_str_eq content_type `application/json` ) 1 { ( __mcp_q_add q `format` `json` ) } {}
    }
    ( string_free fmt )
    : String time ( __mcp_arg_str a `time` )
    ? > ( string_len time ) 0 {
        // A column name is the common case; a plan object passes through.
        ?? ( __mcp_arg a `time` ) {
            T tv → {
                ? ( json_is_obj tv ) {
                    : String js ( json_stringify tv )
                    ( __mcp_q_add q `time` ( string_data js ) )
                    ( string_free js )
                } {
                    : Json plan ( json_obj_new )
                    ( json_obj_set plan `mode` ( json_str_lit `column` ) )
                    ( json_obj_set plan `column` ( json_str_lit ( string_data time ) ) )
                    : String js ( json_stringify plan )
                    ( __mcp_q_add q `time` ( string_data js ) )
                    ( string_free js )
                    ( json_free plan )
                }
            }
            F _ → {}
        }
    } {}
    ( string_free time )
    : String tz ( __mcp_arg_str a `tz` )
    ? > ( string_len tz ) 0 { ( __mcp_q_add q `tz` ( string_data tz ) ) } {}
    ( string_free tz )
    ? ( __mcp_arg_bool a `calendar` F ) { ( __mcp_q_add q `calendar` `1` ) } {}
    : String clock ( __mcp_arg_str a `clock` )
    ? > ( string_len clock ) 0 { ( __mcp_q_add q `clock` ( string_data clock ) ) } {}
    ( string_free clock )
}

@ __mcp_t_analyze_data Json a Json ctx → Json {
    : String text ( string_new )
    : s ct ( __mcp_file_arg a text )
    ? > ( nurl_str_len ct ) 0 {} { ( string_free text ) ^ ( __mcp_no_file ) }
    : String q ( string_new )
    ( __mcp_q_file a q ct )
    : String name ( __mcp_arg_str a `name` )
    ? > ( string_len name ) 0 { ( __mcp_q_add q `name` ( string_data name ) ) } {}
    ( string_free name )
    : i votes ( __mcp_arg_int a `votes` 0 )
    ? > votes 0 { ( __mcp_q_add_int q `votes` votes ) } {}
    : i wait ( __mcp_arg_int a `wait` 30 )
    ( __mcp_q_add_int q `wait` wait )
    : b folder == ( nurl_str_eq ct `folder` ) 1
    : ApiOut o ( __mcp_api_send ctx `POST` `/api/analyze` q ? folder `text/csv` ct ( string_data text ) )
    ( string_free q )
    ( string_free text )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    // 202: the task is still running — say how to come back for it.
    ? == . o status 202 {
        ( json_obj_set . o body `hint` ( json_str_lit `still running — call task {id: task_id} in a little while; wait (max 60 s) holds the call longer next time` ) )
    } {}
    ^ ( __mcp_result_json . o body )
}

@ __mcp_t_import_data Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String text ( string_new )
    : s ct ( __mcp_file_arg a text )
    ? > ( nurl_str_len ct ) 0 {} { ( string_free text ) ( string_free model ) ^ ( __mcp_no_file ) }
    : String q ( string_new )
    ( __mcp_q_file a q ct )
    // The share of the file the margins should flag, the same knob
    // fork_model calls `rate` and a data source calls `finetune_rate`.
    // It only bites on a model this import TRAINS for the first time; a
    // model already trained keeps the margins its owner left it, and the
    // answer says which of those two happened.
    ? ( __mcp_arg_has a `rate` ) {
        : String rs ( string_new )
        ( string_push_float rs ( __mcp_arg_f a `rate` 0.01 ) )
        ( __mcp_q_add q `finetune` ( string_data rs ) )
        ( string_free rs )
    } {}
    : String path ( __mcp_model_path `/models/dynamic/` model `/import` )
    : b folder == ( nurl_str_eq ct `folder` ) 1
    : ApiOut o ( __mcp_api_send ctx `POST` ( string_data path ) q ? folder `text/csv` ct ( string_data text ) )
    ( string_free path )
    ( string_free q )
    ( string_free text )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `format` out )
    ( __mcp_copy b `imported` out )
    ( __mcp_copy b `skipped` out )
    ( __mcp_copy b `data_points` out )
    ( __mcp_copy b `clock` out )
    ( __mcp_copy b `trained` out )
    ( __mcp_copy b `calibrated` out )
    ( __mcp_copy b `calibrated_rate` out )
    ( __mcp_copy b `not_calibrated_because` out )
    ( __mcp_copy b `time` out )
    ( __mcp_copy b `notes` out )
    ( __mcp_copy b `warning` out )
    ( json_obj_set out `next` ( json_str_lit `calibration {model} says what the margins flag over this history — read it before anomalies, especially when calibrated is false.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// ── Tools: changing models ───────────────────────────────────────────

@ __mcp_t_fork_model Json a Json ctx → Json {
    : String src ( __mcp_arg_str a `source` )
    ? > ( string_len src ) 0 {} { ( string_free src ) ^ ( mcp_tool_result_error `source: required — the model whose history to learn from` ) }
    : String name ( __mcp_arg_str a `name` )
    ? > ( string_len name ) 0 {} {
        ( string_free name )
        ( string_free src )
        ^ ( mcp_tool_result_error `name: required — llm_<something> is yours to create; another name needs the administrator role` )
    }
    : Json body ( json_obj_new )
    ( json_obj_set body `name` ( json_str_lit ( string_data name ) ) )
    : i from ( __mcp_arg_instant a `from` )
    : i to ( __mcp_arg_instant a `to` )
    : i last ( __mcp_arg_span a `last` )
    ? | | < from 0 < to 0 & < last 0 != last MCP_SPAN_ALL {
        ( json_free body )
        ( string_free name )
        ( string_free src )
        ^ ( mcp_tool_result_error `from/to: ISO-8601 or Unix seconds; last: seconds, 90s / 15m / 24h / 7d / 2w, or "all" for the source's whole ring` )
    } {}
    ? > from 0 { ( json_obj_set body `from` ( json_int from ) ) } {}
    ? > to 0 { ( json_obj_set body `to` ( json_int to ) ) } {}
    ? > last 0 { ( json_obj_set body `last` ( json_int last ) ) } {}
    ? == last MCP_SPAN_ALL { ( json_obj_set body `last` ( json_str_lit `all` ) ) } {}
    ?? ( __mcp_arg a `fields` ) {
        T fv → { ? ( json_is_arr fv ) { ( json_obj_set body `fields` ( json_clone fv ) ) } {} }
        F _ → {}
    }
    ? ( __mcp_arg_has a `rate` ) { ( json_obj_set body `rate` ( json_float ( __mcp_arg_f a `rate` 0.01 ) ) ) } {}
    : String q ( string_new )
    : String path ( __mcp_model_path `/models/dynamic/` src `/fork` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( json_free body )
    ( string_free path )
    ( string_free q )
    ( string_free name )
    ( string_free src )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : b cc F
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `source` out )
    ?? ( json_obj_get b `window` ) {
        T w → {
            : Json wo ( json_obj_new )
            ( __mcp_when_of w `from` wo `from` cc )
            ( __mcp_when_of w `to` wo `to` cc )
            ( __mcp_copy w `source_points` wo )
            ( json_obj_set out `window` wo )
        }
        F _ → {}
    }
    ( __mcp_copy b `points` out )
    ( __mcp_copy b `rejected` out )
    ( __mcp_copy b `fields` out )
    ( __mcp_copy b `target_rate` out )
    ( __mcp_copy b `margins` out )
    ( __mcp_copy b `notes` out )
    ( __mcp_copy b `anomalies` out )
    ( __mcp_copy b `considered` out )
    ( __mcp_copy b `model_versions` out )
    // `rate` is what EACH version is set to flag. A point is anomalous if
    // ANY of them flags it, so the share of the window the model calls
    // anomalous is the union — several times the rate on a model with
    // several versions, and the number a reader is actually looking at.
    // Asking for 1 % and reading back 3.9 % with nothing to explain it
    // looks like a broken knob; both numbers, side by side, is the truth.
    : i fc_cons ( __mcp_int_of b `considered` )
    : i fc_an ( __mcp_int_of b `anomalies` )
    ? > fc_cons 0 {
        : Json rj ( json_obj_new )
        ( json_obj_set rj `per_version_target` ( json_float ( __mcp_f_of b `target_rate` ) ) )
        ( json_obj_set rj `union` ( __mcp_round_f / # f fc_an # f fc_cons 4 ) )
        ( json_obj_set rj `note` ( json_str_lit `per_version_target is what each version's margin was set to flag on its own; union is the share of the training window the model as a whole calls anomalous, since any one version flagging is enough. Lower the rate, or switch versions off with edit_model, to bring the union down.` ) )
        ( json_obj_set out `alert_rate` rj )
    } {}
    ( json_obj_set out `next` ( json_str_lit `anomalies {model: <model_name>} shows what it flags on its own history; calibration to see the margins; delete_model when done with it.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// POST to a model path with an optional JSON body, result passed through.
@ __mcp_model_post Json ctx s prefix String model s suffix s method ? Json body → Json {
    : String q ( string_new )
    : String path ( __mcp_model_path prefix model suffix )
    : ApiOut o ( __mcp_api ctx method ( string_data path ) q body )
    ( string_free path )
    ( string_free q )
    ^ ( __mcp_pass o )
}

@ __mcp_t_retrain Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_new )
    : String path ( __mcp_model_path `/force_train/` model `` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `status` out )
    ( __mcp_copy . o body `message` out )
    ( __mcp_copy . o body `points_used` out )
    ( json_obj_set out `next` ( json_str_lit `calibration to see the margins the retrained versions now hold; anomalies to see what they flag.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_train_autoencoder Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json body ( json_obj_new )
    ?? ( __mcp_arg a `hidden` ) {
        T hv → { ? ( json_is_arr hv ) { ( json_obj_set body `hidden` ( json_clone hv ) ) } {} }
        F _ → {}
    }
    ? ( __mcp_arg_has a `contamination` ) { ( json_obj_set body `contamination` ( json_float ( __mcp_arg_f a `contamination` 0.0 ) ) ) } {}
    : String q ( string_new )
    : String path ( __mcp_model_path `/train/autoencoder/` model `` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( string_free path )
    ( string_free q )
    ( json_free body )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `status` out )
    ( __mcp_copy . o body `message` out )
    ( __mcp_copy . o body `training_data_points` out )
    ( __mcp_copy . o body `filtered_anomalies` out )
    // The threshold is a reconstruction error in the model's own scale
    // (often 1e-4); significant digits keep it readable, and it is
    // informational — the margin the verdict uses is relative to it.
    ( __mcp_copy_rounded . o body `reconstruction_threshold` out 4 )
    ( json_obj_set out `next` ( json_str_lit `describe_model shows the autoencoder's effective margin; anomalies {versions: ["autoencoder"]} what it flags on its own.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_train_forecast Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json body ( json_obj_new )
    ? ( __mcp_arg_has a `season` ) { ( json_obj_set body `season` ( json_int ( __mcp_arg_int a `season` 0 ) ) ) } {}
    ? ( __mcp_arg_has a `window_points` ) { ( json_obj_set body `window_points` ( json_int ( __mcp_arg_int a `window_points` 0 ) ) ) } {}
    : String q ( string_new )
    : String path ( __mcp_model_path `/train/forecast/` model `` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( string_free path )
    ( string_free q )
    ( json_free body )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `status` out )
    ( __mcp_copy . o body `message` out )
    ( __mcp_copy . o body `features` out )
    ( __mcp_copy . o body `skipped` out )
    ( __mcp_copy . o body `training_data_points` out )
    ( __mcp_copy . o body `season` out )
    ( json_obj_set out `next` ( json_str_lit `forecast {model, horizon} for what the models expect next; anomalies {versions: ["forecast"]} for the points that landed far from their forecast, each naming the feature.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// An ARIMA order as one line — "(0,1,0)" or "(1,1,1)(0,1,1)[144]" —
// instead of eight named integers a reader has to reassemble.
@ __mcp_order_str Json m → String {
    : String out ( string_new )
    ?? ( json_obj_get m `order` ) {
        T sp → {
            ( string_push_char out 40 )
            ( string_push_int out ( __mcp_int_of sp `p` ) )
            ( string_push_char out 44 )
            ( string_push_int out ( __mcp_int_of sp `d` ) )
            ( string_push_char out 44 )
            ( string_push_int out ( __mcp_int_of sp `q` ) )
            ( string_push_char out 41 )
            : i sper ( __mcp_int_of sp `s` )
            ? > sper 0 {
                ( string_push_char out 40 )
                ( string_push_int out ( __mcp_int_of sp `P` ) )
                ( string_push_char out 44 )
                ( string_push_int out ( __mcp_int_of sp `D` ) )
                ( string_push_char out 44 )
                ( string_push_int out ( __mcp_int_of sp `Q` ) )
                ( string_push_str out `)[` )
                ( string_push_int out sper )
                ( string_push_char out 93 )
            } {}
        }
        F _ → {}
    }
    ^ out
}

// The forecast, sized for a context window. One ARIMA per numeric
// feature times loglik/aic/aicc/bic/phi/theta/se is a page of fit
// diagnostics per column, and on a thirty-column model the answer was
// unreadable — and unusable, because what a reader came for (the next
// values and the band around them) was buried in it. The order and the
// chosen form stay, as one line each; `detail: true` brings the rest
// back, and `features` narrows to the columns asked for.
@ __mcp_t_forecast Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_from `horizon=` )
    ( string_push_int q ( __mcp_arg_int a `horizon` 12 ) )
    ? ( __mcp_arg_has a `origin` ) { ( string_push_str q `&origin=` ) ( string_push_int q ( __mcp_arg_int a `origin` 0 ) ) } {}
    : String path ( __mcp_model_path `/models/dynamic/` model `/forecast` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : b detail ( __mcp_arg_bool a `detail` F )
    : String want ( __mcp_arg_csv a `features` )
    : b cc == ( nurl_str_eq ( __mcp_ctx_str b `clock` ) `count` ) 1
    : Json out ( json_obj_new )
    ( __mcp_copy b `horizon` out )
    ( __mcp_copy b `season` out )
    ( __mcp_copy b `seasonal_features` out )
    ( __mcp_copy b `season_note` out )
    ( __mcp_copy b `enabled` out )
    ( __mcp_copy b `clock` out )
    ( __mcp_copy b `step_seconds` out )
    ( __mcp_copy b `origin` out )
    ( __mcp_copy b `warning` out )
    ?? ( json_obj_get b `times` ) {
        T ts → {
            : Json arr ( json_arr_new )
            ( json_arr_each ts \ Json t → v { ( json_arr_push arr ( __mcp_when ( json_as_int t ) cc ) ) } )
            ( json_obj_set out `times` arr )
        }
        F _ → {}
    }
    : Json fa ( json_arr_new )
    : ~ i shown 0
    : ~ i total 0
    ?? ( json_obj_get b `forecasts` ) {
        T fs → {
            = total ( json_arr_len fs )
            : ~ i fi 0
            ~ < fi total {
                ?? ( json_arr_get fs fi ) {
                    T fo → {
                        : s fname ( __mcp_ctx_str fo `feature` )
                        ? | == ( string_len want ) 0 ( __mcp_csv_has ( string_data want ) fname ) {
                            = shown + shown 1
                            : Json e ( json_obj_new )
                            ( __mcp_copy fo `feature` e )
                            ( __mcp_copy fo `selected` e )
                            ?? ( json_obj_get fo `model` ) {
                                T m → {
                                    : String os ( __mcp_order_str m )
                                    ( json_obj_set e `order` ( json_str_lit ( string_data os ) ) )
                                    ( string_free os )
                                    ( __mcp_copy_rounded m `sigma2` e 6 )
                                    ? detail { ( json_obj_set e `fit` ( json_clone m ) ) } {}
                                }
                                F _ → {}
                            }
                            ( json_obj_set e `mean` ( __mcp_round_arr fo `mean` 4 ) )
                            ( json_obj_set e `se` ( __mcp_round_arr fo `se` 4 ) )
                            ( json_obj_set e `lo95` ( __mcp_round_arr fo `lo95` 4 ) )
                            ( json_obj_set e `hi95` ( __mcp_round_arr fo `hi95` 4 ) )
                            ? detail {
                                ( json_obj_set e `lo80` ( __mcp_round_arr fo `lo80` 4 ) )
                                ( json_obj_set e `hi80` ( __mcp_round_arr fo `hi80` 4 ) )
                            } {}
                            ( json_arr_push fa e )
                        } {}
                    }
                    F _ → {}
                }
                = fi + fi 1
            }
        }
        F _ → {}
    }
    ( string_free want )
    ( json_obj_set out `forecasts` fa )
    ? > total shown {
        : String n ( string_from `` )
        ( string_push_int n shown )
        ( string_push_str n ` of ` )
        ( string_push_int n total )
        ( string_push_str n ` watched features shown (features narrowed the list)` )
        ( json_obj_set out `note` ( json_str_lit ( string_data n ) ) )
        ( string_free n )
    } {}
    ? ! detail {
        ( json_obj_set out `fit_note` ( json_str_lit `order is the fitted ARIMA in one line and selected the form the holdout chose; detail: true adds the coefficients and the fit statistics, and the 80 % band. forecast_backtest measures whether these forecasts are any good — read it before trusting the band, whose width comes from the fit and is routinely optimistic.` ) )
    } {}
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_forecast_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ~ Json body ( json_obj_new )
    ?? ( __mcp_arg a `values` ) {
        T v → { ? ( json_is_obj v ) { ( json_free body ) = body ( json_clone v ) } {} }
        F _ → {}
    }
    : String q ( string_from `horizon=` )
    ( string_push_int q ( __mcp_arg_int a `horizon` 1 ) )
    : String path ( __mcp_model_path `/forecast/` model `` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( string_free path )
    ( string_free q )
    ( json_free body )
    ( string_free model )
    ^ ( __mcp_pass o )
}

@ __mcp_t_audit Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_from `limit=` )
    ( string_push_int q ( __mcp_arg_int a `limit` 100 ) )
    : String path ( __mcp_model_path `/models/dynamic/` model `/audit` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( __mcp_iso_times . o body )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

// The mean of an array's non-null numbers, or -1 when there are none.
@ __mcp_arr_mean Json src s key → f {
    : ~ f sum 0.0
    : ~ i n 0
    ?? ( json_obj_get src key ) {
        T v → {
            ? ( json_is_arr v ) {
                : i m ( json_arr_len v )
                : ~ i k 0
                ~ < k m {
                    ?? ( json_arr_get v k ) {
                        T e → { ?? ( json_num_as_f e ) { T x → { = sum + sum x = n + n 1 } F → {} } }
                        F _ → {}
                    }
                    = k + k 1
                }
            } {}
        }
        F _ → {}
    }
    ^ ? > n 0 / sum # f n -1.0
}

// A backtest that measures a forecast worse than carrying the last value
// forward, or a 95 % band that covers three readings in four, is telling
// a reader something about the version they are about to trust as a
// detector — and it was telling it only in numbers, beside a
// skill_vs_seasonal_naive of 0.85 that flatters because the seasonal
// naive is dreadful. The readings say it in words, per feature and for
// the model.
@ __mcp_t_forecast_backtest Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_from `horizon=` )
    ( string_push_int q ( __mcp_arg_int a `horizon` 12 ) )
    ( string_push_str q `&points=` )
    ( string_push_int q ( __mcp_arg_int a `points` 200 ) )
    : String path ( __mcp_model_path `/models/dynamic/` model `/forecast/backtest` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_clone b )
    : ~ i n_feat 0
    : ~ i n_useless 0
    : ~ i n_narrow 0
    ?? ( json_obj_get out `features` ) {
        T fs → {
            : i nf ( json_arr_len fs )
            : ~ i k 0
            ~ < k nf {
                ?? ( json_arr_get fs k ) {
                    T fo → {
                        = n_feat + n_feat 1
                        : f cov ( __mcp_arr_mean fo `coverage95` )
                        ? >= cov 0.0 { ( json_obj_set fo `coverage95_mean` ( __mcp_round_f cov 3 ) ) } {}
                        : ~ b useless F
                        ?? ( json_obj_get fo `skill_vs_naive` ) {
                            T sv → { ?? ( json_num_as_f sv ) { T x → { = useless <= x 0.0 } F → {} } }
                            F _ → {}
                        }
                        : b narrow & >= cov 0.0 < cov 0.9
                        ? useless { = n_useless + n_useless 1 } {}
                        ? narrow { = n_narrow + n_narrow 1 } {}
                        : ~ String rd ( string_new )
                        ? useless {
                            ( string_push_str rd `no skill: the fitted model forecasts this feature no better than carrying the last value forward, so a reading judged against it is judged against persistence with extra machinery. ` )
                        } {}
                        ? narrow {
                            ( string_push_str rd `the 95 % band covers only ` )
                            ( string_push_int rd # i ( float_round * cov 100.0 ) )
                            ( string_push_str rd ` % of what followed: the standard errors are optimistic, so a margin read as a plain sigma count would over-flag. The version's margin is calibrated from the stream's own z-scores at train_forecast for exactly this reason — leave it to calibration rather than setting a sigma by hand. ` )
                        } {}
                        ? & ! useless ! narrow {
                            ( string_push_str rd `the model beats persistence and its band covers about what it claims.` )
                        } {}
                        ( json_obj_set fo `reading` ( json_str_lit ( string_data rd ) ) )
                        ( string_free rd )
                        // skill_vs_seasonal_naive flatters when the
                        // seasonal naive is bad; the two baselines'
                        // errors are already here, and naming that is
                        // cheaper than a reader noticing it.
                        ( json_obj_set fo `baseline_note` ( json_str_lit `skill is 1 - MAE/MAE_baseline. Compare naive_mae and seasonal_naive_mae before reading either skill: a high skill against a baseline that is itself far off says little.` ) )
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
    ? > n_feat 0 {
        : String v ( string_new )
        ? == n_useless n_feat {
            ( string_push_str v `no feature's forecast beats carrying the last value forward. As a detector this version is flagging distance from persistence, which the other versions already see — switch it off with edit_model {versions: {forecast: {enabled: false}}} unless a backtest over more history says otherwise.` )
        } {
            ? > n_useless 0 {
                ( string_push_int v n_useless )
                ( string_push_str v ` of ` )
                ( string_push_int v n_feat )
                ( string_push_str v ` features have no skill over persistence; the rest do.` )
            } { ( string_push_str v `every feature's forecast beats carrying the last value forward.` ) }
        }
        ? > n_narrow 0 {
            ( string_push_str v ` The 95 % band is narrower than its name on ` )
            ( string_push_int v n_narrow )
            ( string_push_str v ` of them.` )
        } {}
        ( json_obj_set out `verdict` ( json_str_lit ( string_data v ) ) )
        ( string_free v )
    } {}
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_finetune Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json body ( json_obj_new )
    ? ( __mcp_arg_has a `rate` ) { ( json_obj_set body `rate` ( json_float ( __mcp_arg_f a `rate` 0.01 ) ) ) } {}
    // `last`: the shared span vocabulary, plus "own" — each version's
    // own training period — which only fine-tune knows.
    : ~ b own F
    ?? ( __mcp_arg a `last` ) {
        T lv → { ? ( json_is_str lv ) { = own == ( nurl_str_eq ( json_str_data lv ) `own` ) 1 } {} }
        F _ → {}
    }
    ? own { ( json_obj_set body `last` ( json_str_lit `own` ) ) } {
        : i last ( __mcp_arg_span a `last` )
        ? == last -1 {
            ( json_free body )
            ( string_free model )
            ^ ( mcp_tool_result_error `last: not a span — use seconds, 90s / 15m / 24h / 7d / 2w, "all" for every stored point, or "own" for each version's own training period` )
        } {}
        ? > last 0 { ( json_obj_set body `last` ( json_int last ) ) } {}
        ? == last MCP_SPAN_ALL { ( json_obj_set body `last` ( json_str_lit `all` ) ) } {}
    }
    : i from ( __mcp_arg_instant a `from` )
    : i to ( __mcp_arg_instant a `to` )
    ? | < from 0 < to 0 {
        ( json_free body )
        ( string_free model )
        ^ ( mcp_tool_result_error `from/to: ISO-8601 or Unix seconds` )
    } {}
    ? > from 0 { ( json_obj_set body `from` ( json_int from ) ) } {}
    ? > to 0 { ( json_obj_set body `to` ( json_int to ) ) } {}
    ?? ( __mcp_arg a `versions` ) {
        T vv → { ? ( json_is_arr vv ) { ( json_obj_set body `versions` ( json_clone vv ) ) } {} }
        F _ → {}
    }
    ? ( __mcp_arg_bool a `dry_run` F ) { ( json_obj_set body `dry_run` ( json_bool T ) ) } {}
    : String q ( string_new )
    : String path ( __mcp_model_path `/api/dynamic/` model `/finetune` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( string_free path )
    ( string_free q )
    ( json_free body )
    ( string_free model )
    ^ ( __mcp_finetune_out o )
}

// A fine-tune report for a reader: the window as stamps, then each
// version's margin before and after (verbatim — a margin is a
// threshold, not a reading), how many rows it flagged either side and
// the rate that makes, whether the requested rate was reachable exactly
// and whether the change was applied. The API's legacy
// `adjusted_margins` / `max_anomaly_scores` maps repeat the per-version
// numbers and are not carried.
@ __mcp_finetune_out ApiOut o → Json {
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_copy b `status` out )
    ( __mcp_copy b `message` out )
    ( __mcp_copy b `rate` out )
    ( __mcp_copy b `dry_run` out )
    ( __mcp_copy b `note` out )
    ?? ( json_obj_get b `window` ) {
        T w → {
            : Json wo ( json_obj_new )
            ( __mcp_when_of w `from` wo `from` cc )
            ( __mcp_when_of w `to` wo `to` cc )
            ( __mcp_copy w `rows` wo )
            ( __mcp_copy w `excluded` wo )
            ( __mcp_copy w `own` wo )
            ( json_obj_set out `window` wo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `versions` ) {
        T vers → {
            : Json vo ( json_obj_new )
            ( json_obj_each vers \ s name Json vv → v {
                : Json e ( json_obj_new )
                ( __mcp_copy vv `units` e )
                ( __mcp_copy vv `old_margin` e )
                ( __mcp_copy vv `new_margin` e )
                ( __mcp_copy vv `n` e )
                ( __mcp_copy vv `flagged_before` e )
                ( __mcp_copy vv `flagged_after` e )
                ( __mcp_copy vv `applied` e )
                ( __mcp_copy vv `warning` e )
                ( __mcp_copy_rounded vv `rate_before` e 4 )
                ( __mcp_copy_rounded vv `rate_after` e 4 )
                ( __mcp_copy vv `exact` e )
                ( __mcp_copy vv `applied` e )
                ( __mcp_when_of vv `from` e `from` cc )
                ( __mcp_copy vv `rows` e )
                ( json_obj_set vo name e )
            } )
            ( json_obj_set out `versions` vo )
        }
        F _ → {}
    }
    // `rate` is per version, and a point is anomalous if ANY version
    // flags it, so the share of the window the model calls anomalous is
    // the union of the versions' — several times the rate on a model with
    // several versions.
    ( __mcp_copy b `votes_required` out )
    ( __mcp_copy b `consensus` out )
    // With one vote `rate` is each version's own share and the model's is
    // the union of them; with more, `rate` is the model's and `consensus`
    // says what each version was set to on its own to reach it.
    ? <= ( __mcp_int_of b `votes_required` ) 1 {
        ( json_obj_set out `rate_is_per_version` ( json_str_lit `the rate above is what EACH version's margin now flags on its own; this model calls a row an anomaly if ANY version flags it (votes = 1), so its own rate over this window is the union — calibration's aggregate.rate, or anomaly_summary's anomaly_rate, is that number. edit_model {votes: N} makes N versions have to agree, and then rate becomes the model's own share.` ) )
    } {}
    ( json_obj_set out `next` ( json_str_lit `calibration {model} to read the aggregate rate these margins produce; anomalies to see what they flag.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_edit_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ?? ( __mcp_arg a `patch` ) {
        T pv → {
            ? & ( json_is_obj pv ) > ( __mcp_obj_len pv ) 0 {} {
                ( string_free model )
                ^ ( mcp_tool_result_error `patch: required — an object with one or more of alias, clock, schedule, max_data_points, versions, votes (describe_model lists editable_fields and the current values)` )
            }
            : String q ( string_new )
            : String path ( __mcp_model_path `/models/dynamic/` model `/metadata` )
            : ApiOut o ( __mcp_api ctx `PUT` ( string_data path ) q @ ?Json { T pv } )
            ( string_free path )
            ( string_free q )
            ( string_free model )
            ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
            : Json b . o body
            : Json out ( json_obj_new )
            ( __mcp_copy b `message` out )
            // What the patch asked for and the config could not hold — a
            // step of 0 under a seasonal window, a forest of no trees.
            ( __mcp_copy b `adjusted` out )
            ?? ( json_obj_get b `metadata` ) {
                T mj → { ( json_obj_set out `model` ( __mcp_model_desc mj ) ) }
                F _ → {}
            }
            ( json_obj_set out `next` ( json_str_lit `calibration to see what the margins now flag over a window; audit lists every margin this and every other change moved.` ) )
            ( __mcp_api_out_free o )
            ^ ( __mcp_result_json out )
        }
        F _ → {
            ( string_free model )
            ^ ( mcp_tool_result_error `patch: required — an object with one or more of alias, clock, schedule, max_data_points, versions, votes` )
        }
    }
}

// How many keys an object has.
@ __mcp_obj_len Json o → i {
    : ( Vec String ) ks ( json_obj_keys o )
    : i n ( vec_len [String] ks )
    ( vec_free_with [String] ks \ String x → v { ( string_free x ) } )
    ^ n
}

@ __mcp_t_reset_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ? ( __mcp_arg_bool a `confirm` F ) {} {
        ( string_free model )
        ^ ( mcp_tool_result_error `confirm: true is required — reset drops every stored point and forest of the model and cannot be undone` )
    }
    : Json out ( __mcp_model_post ctx `/models/dynamic/` model `/reset` `POST` @ ?Json { F @ Json { JNull } } )
    ( string_free model )
    ^ out
}

// A reader's word on a row: false_positive, confirmed, or none to
// withdraw. Rides on the row through anomalies; a false positive is
// left out of calibration and fine-tune.
@ __mcp_t_label_anomaly Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : i index ( __mcp_arg_int a `index` -1 )
    ? >= index 0 {} {
        ( string_free model )
        ^ ( mcp_tool_result_error `index: the row's index, as anomalies and points list it` )
    }
    : String label ( __mcp_arg_str a `label` )
    ? ( label_known ( string_data label ) ) {} {
        ( string_free label )
        ( string_free model )
        ^ ( mcp_tool_result_error `label: "false_positive", "confirmed", or "none" to withdraw an earlier label` )
    }
    : Json body ( json_obj_new )
    ( json_obj_set body `index` ( json_int index ) )
    ( json_obj_set body `label` ( json_str_lit ( string_data label ) ) )
    ( string_free label )
    : String note ( __mcp_arg_str a `note` )
    ? > ( string_len note ) 0 { ( json_obj_set body `note` ( json_str_lit ( string_data note ) ) ) } {}
    ( string_free note )
    : String q ( string_new )
    : String path ( __mcp_model_path `/models/dynamic/` model `/labels` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { T body } )
    ( string_free path )
    ( string_free q )
    ( json_free body )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_obj_new )
    ( __mcp_copy b `status` out )
    ( __mcp_copy b `message` out )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `index` out )
    ( __mcp_when_of b `timestamp` out `time` F )
    ( __mcp_copy b `label` out )
    ( __mcp_copy b `by` out )
    ( __mcp_when_of b `at` out `at` F )
    ( __mcp_copy b `note` out )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_labels Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String q ( string_new )
    : String path ( __mcp_model_path `/models/dynamic/` model `/labels` )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free path )
    ( string_free q )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `clock` out )
    ( __mcp_copy b `count` out )
    ( __mcp_copy b `false_positives` out )
    ( __mcp_copy b `confirmed` out )
    : Json rows ( json_arr_new )
    ?? ( json_obj_get b `labels` ) {
        T ls → {
            ( json_arr_each ls \ Json l → v {
                : Json lo ( json_obj_new )
                ( __mcp_copy l `index` lo )
                ( __mcp_copy l `evicted` lo )
                ( __mcp_when_of l `timestamp` lo `time` cc )
                ( __mcp_copy l `label` lo )
                ( __mcp_copy l `by` lo )
                ( __mcp_when_of l `at` lo `at` F )
                ( __mcp_copy l `note` lo )
                ( json_arr_push rows lo )
            } )
        }
        F _ → {}
    }
    ( json_obj_set out `labels` rows )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_delete_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ? ( __mcp_arg_bool a `confirm` F ) {} {
        ( string_free model )
        ^ ( mcp_tool_result_error `confirm: true is required — delete removes the model, its data and its forests for good` )
    }
    : Json out ( __mcp_model_post ctx `/delete_model/` model `` `DELETE` @ ?Json { F @ Json { JNull } } )
    ( string_free model )
    ^ out
}

// ── Tools: the organisation ──────────────────────────────────────────

@ __mcp_t_claim_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a ctx )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String owner ( __mcp_arg_str a `owner` )
    : Json body ( json_obj_new )
    ? > ( string_len owner ) 0 { ( json_obj_set body `owner` ( json_str_lit ( string_data owner ) ) ) } {}
    ( string_free owner )
    : Json out ( __mcp_model_post ctx `/models/dynamic/` model `/claim` `POST` @ ?Json { T body } )
    ( json_free body )
    ( string_free model )
    ^ out
}

@ __mcp_t_set_role Json a Json ctx → Json {
    : String sub ( __mcp_arg_str a `subject` )
    ? > ( string_len sub ) 0 {} { ( string_free sub ) ^ ( mcp_tool_result_error `subject: required — a member's subject from org_users` ) }
    : String role ( __mcp_arg_str a `role` )
    ? > ( string_len role ) 0 {} { ( string_free role ) ( string_free sub ) ^ ( mcp_tool_result_error `role: required — admin or viewer` ) }
    : Json body ( json_obj_new )
    ( json_obj_set body `role` ( json_str_lit ( string_data role ) ) )
    : String path ( __mcp_model_path `/api/org/users/` sub `/role` )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `PUT` ( string_data path ) q @ ?Json { T body } )
    ( string_free q )
    ( string_free path )
    ( json_free body )
    ( string_free role )
    ( string_free sub )
    ^ ( __mcp_pass o )
}

// ── Tools: data sources (src/sources.nu) ─────────────────────────────
//
// The record's fields as the API takes them, copied from the arguments
// as given — the API validates and answers with the reason on a 400.
: s __MCP_SOURCE_FIELDS `name kind url query mode params features categorical time_field model interval_minutes history_hours calendar enabled method headers body path allow_future finetune_rate`

@ __mcp_source_body Json a → Json {
    : Json body ( json_obj_new )
    : String all ( string_from __MCP_SOURCE_FIELDS )
    : ( Vec String ) keys ( string_split all ` ` )
    ( string_free all )
    : i n ( vec_len [String] keys )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] keys k ) {
            T key → {
                ?? ( __mcp_arg a ( string_data key ) ) {
                    T v → { ( json_obj_set body ( string_data key ) ( json_clone v ) ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ^ body
}

@ __mcp_need_source_id Json a → String {
    ^ ( __mcp_arg_str a `id` )
}

@ __mcp_t_source Json a Json ctx → Json {
    : String id ( __mcp_need_source_id a )
    ? > ( string_len id ) 0 {} { ( string_free id ) ^ ( mcp_tool_result_error `id: required — a source id from sources` ) }
    : String path ( __mcp_model_path `/api/org/sources/` id `` )
    : Json out ( __mcp_t_get ctx ( string_data path ) )
    ( string_free path )
    ( string_free id )
    ^ out
}

@ __mcp_t_create_source Json a Json ctx → Json {
    : Json body ( __mcp_source_body a )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `POST` `/api/org/sources` q @ ?Json { T body } )
    ( string_free q )
    ( json_free body )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_clone . o body )
    ( json_obj_set out `next` ( json_str_lit `run_source {id} fetches now (backfill_hours reaches back); source {id} shows each run's outcome; the model named receives the points.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_update_source Json a Json ctx → Json {
    : String id ( __mcp_need_source_id a )
    ? > ( string_len id ) 0 {} { ( string_free id ) ^ ( mcp_tool_result_error `id: required — a source id from sources` ) }
    : Json body ( __mcp_source_body a )
    : String path ( __mcp_model_path `/api/org/sources/` id `` )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `PUT` ( string_data path ) q @ ?Json { T body } )
    ( string_free q )
    ( string_free path )
    ( json_free body )
    ( string_free id )
    ^ ( __mcp_pass o )
}

@ __mcp_t_delete_source Json a Json ctx → Json {
    : String id ( __mcp_need_source_id a )
    ? > ( string_len id ) 0 {} { ( string_free id ) ^ ( mcp_tool_result_error `id: required — a source id from sources` ) }
    ? ( __mcp_arg_bool a `confirm` F ) {} {
        ( string_free id )
        ^ ( mcp_tool_result_error `confirm: true is required — delete removes the source and its schedule; the model and the points it fetched stay` )
    }
    : String path ( __mcp_model_path `/api/org/sources/` id `` )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `DELETE` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ( string_free path )
    ( string_free id )
    ^ ( __mcp_pass o )
}

@ __mcp_t_run_source Json a Json ctx → Json {
    : String id ( __mcp_need_source_id a )
    ? > ( string_len id ) 0 {} { ( string_free id ) ^ ( mcp_tool_result_error `id: required — a source id from sources` ) }
    : String q ( string_new )
    : i back ( __mcp_arg_int a `backfill_hours` 0 )
    ? > back 0 { ( string_push_str q `backfill_hours=` ) ( string_push_int q back ) } {}
    : String path ( __mcp_model_path `/api/org/sources/` id `/run` )
    : ApiOut o ( __mcp_api ctx `POST` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ( string_free path )
    ( string_free id )
    ^ ( __mcp_pass o )
}

// A service's catalogue is hundreds of entries with their parameters —
// far more than a context window wants at once. The tool answers with
// id, kind and title per entry, `filter` narrowing them by a substring
// of id or title, and one entry in full (abstract, parameters) when
// `query` names it.
@ __mcp_t_source_catalog Json a Json ctx → Json {
    : String url ( __mcp_arg_str a `url` )
    ? > ( string_len url ) 0 {} { ( string_free url ) ^ ( mcp_tool_result_error `url: required — the WFS endpoint` ) }
    : Json body ( json_obj_new )
    ( json_obj_set body `url` ( json_str_lit ( string_data url ) ) )
    ( string_free url )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `POST` `/api/org/sources/catalog` q @ ?Json { T body } )
    ( string_free q )
    ( json_free body )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : String want ( __mcp_arg_str a `query` )
    : String filt0 ( __mcp_arg_str a `filter` )
    : String filt ( string_to_lower filt0 )
    ( string_free filt0 )
    : Json out ( json_obj_new )
    ( __mcp_copy . o body `base_url` out )
    : Json list ( json_arr_new )
    : ~ i total 0
    ?? ( json_obj_get . o body `queries` ) {
        T qs → {
            ? ( json_is_arr qs ) {
                = total ( json_arr_len qs )
                : ~ i k 0
                ~ < k total {
                    ?? ( json_arr_get qs k ) {
                        T e → {
                            : String id ( __mcp_jstr e `id` )
                            : String title ( __mcp_jstr e `title` )
                            : ~ b take T
                            ? > ( string_len want ) 0 { = take ( string_eq id want ) } {
                                ? > ( string_len filt ) 0 {
                                    : String lid ( string_to_lower id )
                                    : String lt ( string_to_lower title )
                                    = take | >= ( nurl_str_find ( string_data lid ) ( string_data filt ) ) 0 >= ( nurl_str_find ( string_data lt ) ( string_data filt ) ) 0
                                    ( string_free lid ) ( string_free lt )
                                } {}
                            }
                            ? take {
                                ? > ( string_len want ) 0 { ( json_arr_push list ( json_clone e ) ) } {
                                    : Json c ( json_obj_new )
                                    ( json_obj_set c `id` ( json_str_lit ( string_data id ) ) )
                                    ( __mcp_copy e `kind` c )
                                    ( json_obj_set c `title` ( json_str_lit ( string_data title ) ) )
                                    ?? ( json_obj_get e `parameters` ) { T pa → { ? ( json_is_arr pa ) { ( json_obj_set c `parameters` ( json_int ( json_arr_len pa ) ) ) } {} } F _ → {} }
                                    ( json_arr_push list c )
                                }
                            } {}
                            ( string_free id ) ( string_free title )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
            } {}
        }
        F _ → {}
    }
    ( json_obj_set out `total` ( json_int total ) )
    ( json_obj_set out `listed` ( json_int ( json_arr_len list ) ) )
    ( json_obj_set out `queries` list )
    ? & == ( string_len want ) 0 == ( json_arr_len list ) 0 {} {
        ? == ( string_len want ) 0 { ( json_obj_set out `next` ( json_str_lit `source_catalog {url, query: "<id>"} shows one entry's parameters; source_preview {url, query, mode, params, hours} its columns.` ) ) } {}
    }
    ( string_free want ) ( string_free filt )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_jstr Json o s key → String {
    ?? ( json_obj_get o key ) { T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {} } F _ → {} }
    ^ ( string_new )
}

@ __mcp_t_source_preview Json a Json ctx → Json {
    : Json body ( __mcp_source_body a )
    ? ( __mcp_arg_has a `hours` ) { ( json_obj_set body `hours` ( json_int ( __mcp_arg_int a `hours` 24 ) ) ) } {}
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `POST` `/api/org/sources/preview` q @ ?Json { T body } )
    ( string_free q )
    ( json_free body )
    ^ ( __mcp_pass o )
}

// ── Schemas ──────────────────────────────────────────────────────────

@ __mcp_sc_model → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `model` `string` `Model name, as list_models shows it.` T )
    ^ sc
}

// from / to / last on a schema — the window vocabulary every reader shares.
@ __mcp_sc_window Json sc → v {
    ( mcp_schema_prop sc `last` `string` `A span back from the newest stored point (not from now): "24h", "7d", "2w", "90m", or seconds; "all" for every stored point. A model that stopped receiving data still answers about its last day.` F )
    ( mcp_schema_prop sc `from` `string` `Window start: ISO-8601 ("2026-09-01" or "2026-09-01T06:00:00Z"; a bare stamp is read in the server's zone) or Unix seconds.` F )
    ( mcp_schema_prop sc `to` `string` `Window end, same forms as from. With last, the span ends here.` F )
}

@ __mcp_sc_list_models → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `detail` `boolean` `List every column name and every version's margin, as this tool did before it learned to be brief. Default false: a count of columns and the versions that are on.` F )
    ^ sc
}

@ __mcp_sc_model_window → Json {
    : Json sc ( __mcp_sc_model )
    ( __mcp_sc_window sc )
    ^ sc
}

@ __mcp_sc_anomalies → Json {
    : Json sc ( __mcp_sc_model_window )
    ( mcp_schema_prop sc `count` `integer` `How many of the newest matching rows to return (default 20, max 200). The reply says how many the window had.` F )
    ( mcp_schema_prop sc `all_points` `boolean` `true: every scored row, flagged or not (default false: only anomalies).` F )
    ( mcp_schema_prop sc `versions` `array` `Keep only rows flagged by one of these model versions (names from list_models), e.g. ["autoencoder"].` F )
    ( mcp_schema_prop sc `min_votes` `integer` `Narrow this listing to rows at least this many versions flagged. It is a FILTER on top of the model's own rule (describe_model's votes, 1 unless it was raised): the model says what an anomaly is, this asks for stricter agreement within that. Raising the model's votes instead changes what is stored, calibrated and tuned for — edit_model {votes: N}.` F )
    ( mcp_schema_prop sc `fields` `array` `Which of the row's columns to include as values (default: all of them).` F )
    ( mcp_schema_prop sc `contributions` `integer` `Per flagged row, the N features the autoencoder blames most, with the value it saw and the value it expected (default 3, 0 = none). Needs a trained autoencoder.` F )
    ^ sc
}

@ __mcp_sc_summary → Json {
    : Json sc ( __mcp_sc_model_window )
    ( mcp_schema_prop sc `buckets` `integer` `Timeline slices between the first and the latest anomaly (default 12, max 48).` F )
    ( mcp_schema_prop sc `min_votes` `integer` `Narrow to rows at least this many versions flagged — a filter on top of the model's own votes rule, not a replacement for it.` F )
    ^ sc
}

@ __mcp_sc_points → Json {
    : Json sc ( __mcp_sc_model_window )
    ( mcp_schema_prop sc `count` `integer` `Newest N rows of the window (default 20, max 500).` F )
    ( mcp_schema_prop sc `fields` `array` `Columns to include (default: all).` F )
    ^ sc
}

@ __mcp_sc_point → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `index` `integer` `The ring index an anomalies row carries.` T )
    ^ sc
}

@ __mcp_sc_values s missing → Json {
    : Json sc ( __mcp_sc_model )
    : String d ( string_from `One point: the model's columns and their values, e.g. {"temperature": 21.5, "state": "on"}. Columns the model does not know are ignored; ` )
    ( string_push_str d missing )
    ( mcp_schema_prop sc `values` `object` ( string_data d ) T )
    ( string_free d )
    ^ sc
}

@ __mcp_sc_id → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `id` `string` `The task_id.` T )
    ^ sc
}

// csv / rows / format / time / tz / calendar / clock — the file vocabulary.
@ __mcp_sc_file Json sc → v {
    ( mcp_schema_prop sc `csv` `string` `The file as text: a header row, then one row per point. One of csv, rows or file.` F )
    ( mcp_schema_prop sc `rows` `array` `The points as an array of objects (one key per column). One of csv, rows or file.` F )
    ( mcp_schema_prop sc `file` `string` `A file already in the organisation's folder, by the name list_files gives — the input an earlier analysis or import left behind, or an export. Prefer this to inlining the bytes: a file sent as csv or rows costs its whole size in the conversation, twice.` F )
    ( mcp_schema_prop sc `format` `string` `csv, json, jsonl or fmi; omitted = detected from the content.` F )
    ( mcp_schema_prop sc `time` `string` `The column holding each row's time (default: detected). Without a time column the model runs on a point count.` F )
    ( mcp_schema_prop sc `tz` `string` `Zone for naive stamps: local (default), utc, or +03:00.` F )
    ( mcp_schema_prop sc `calendar` `boolean` `true: keep an ISO time column so hour-of-day and weekday become features.` F )
}

@ __mcp_sc_analyze → Json {
    : Json sc ( mcp_schema_obj )
    ( __mcp_sc_file sc )
    ( mcp_schema_prop sc `name` `string` `A label for the analysis (it appears in list_tasks and list_files).` F )
    ( mcp_schema_prop sc `votes` `integer` `How many versions must agree for a row to count as an anomaly (default 1).` F )
    ( mcp_schema_prop sc `wait` `integer` `Seconds to hold the call for the result (default 30, max 60). A big file that is not done answers with a task to poll.` F )
    ^ sc
}

@ __mcp_sc_import → Json {
    : Json sc ( __mcp_sc_model )
    ( __mcp_sc_file sc )
    ( mcp_schema_prop sc `clock` `string` `For a NEW model: time or count. Default: time when the rows are stamped, count when not.` F )
    ( mcp_schema_prop sc `rate` `number` `The share of the imported history each version's margin should flag, 0 < rate ≤ 0.5 (default 0.01). Applies only when this import is what first trains the model: a model already trained keeps the margins it has, and the answer says so under not_calibrated_because.` F )
    ^ sc
}

@ __mcp_sc_fork → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `source` `string` `The model whose stored history to learn from.` T )
    ( mcp_schema_prop sc `name` `string` `The new model's name. llm_<something> needs no special role; any other name needs an administrator.` T )
    ( __mcp_sc_window sc )
    ( mcp_schema_prop sc `fields` `array` `Only these columns of the source (default: all). Fewer columns = a model that watches fewer relations.` F )
    ( mcp_schema_prop sc `rate` `number` `The share of the training window the margins should flag, 0 < rate ≤ 1 (default 0.01).` F )
    ^ sc
}

@ __mcp_sc_train_ae → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `hidden` `array` `Hidden layer sizes, e.g. [64, 16, 64] (default).` F )
    ( mcp_schema_prop sc `contamination` `number` `Share of the training rows the pre-filter drops as outliers before fitting (default: automatic).` F )
    ^ sc
}

@ __mcp_sc_train_fc → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `season` `integer` `Seasonal period in rows — 24 for hourly data with a daily rhythm, 1440 at a minute's step, 7 for daily data with a weekly one; 0 = from the ring's step; -1 = no season (default: the version's current setting). Every form is tried and the holdout chooses: a plain ARIMA, the persistence forecast, the seasonal polynomial (up to 168 rows), Fourier terms with 2, 4 or 6 harmonics, the week added when the fit window holds three of them.` F )
    ( mcp_schema_prop sc `window_points` `integer` `Rows back from the newest the models are fitted on (default: the version's setting, 2000).` F )
    ^ sc
}

@ __mcp_sc_forecast → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `horizon` `integer` `How many steps ahead (default 12, at most 1000).` F )
    ( mcp_schema_prop sc `origin` `integer` `A stored row's index: the forecast as it would have been made from that row (the models replayed up to it), to put beside what followed. Default: from the newest row.` F )
    ( mcp_schema_prop sc `features` `array` `Only these columns (default: every watched one). A model watching thirty features answers with thirty forecasts otherwise.` F )
    ( mcp_schema_prop sc `detail` `boolean` `Add each fit's coefficients and statistics (phi, theta, loglik, aic, bic, standard errors) and the 80 % band. Default false: the order in one line, the chosen form, the values and the 95 % band.` F )
    ^ sc
}

@ __mcp_sc_forecast_point → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `values` `object` `The point's fields, as ingest_point takes them.` T )
    ( mcp_schema_prop sc `horizon` `integer` `How many steps ahead to forecast from this point (default 1, at most 1000).` F )
    ^ sc
}

@ __mcp_sc_backtest → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `horizon` `integer` `Steps ahead to score (default 12).` F )
    ( mcp_schema_prop sc `points` `integer` `How many of the newest stored rows are forecast origins (default 200).` F )
    ^ sc
}

@ __mcp_sc_audit → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `limit` `integer` `How many of the newest entries (default 100).` F )
    ^ sc
}

@ __mcp_sc_finetune → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `rate` `number` `Target alert rate: the share of the window each version should flag, e.g. 0.01 for 1% (default 0.01).` F )
    ( mcp_schema_prop sc `last` `string` `Window: a span back from the newest stored point ("7d", "24h", seconds), "all" for every stored point, or "own" for each version's own training period. Default: the last 24h.` F )
    ( mcp_schema_prop sc `from` `string` `Window start, ISO-8601 or Unix seconds.` F )
    ( mcp_schema_prop sc `to` `string` `Window end.` F )
    ( mcp_schema_prop sc `versions` `array` `Only these versions (default: every enabled, trained one).` F )
    ( mcp_schema_prop sc `dry_run` `boolean` `true: report the margins it would set without writing them.` F )
    ^ sc
}

@ __mcp_sc_label → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `index` `integer` `The row's index, as anomalies and points list it.` T )
    : Json labels ( json_arr_new )
    ( json_arr_push labels ( json_str_lit ANOM_LABEL_FP ) )
    ( json_arr_push labels ( json_str_lit ANOM_LABEL_OK ) )
    ( json_arr_push labels ( json_str_lit ANOM_LABEL_NONE ) )
    ( mcp_schema_prop_enum sc `label` `string` `"false_positive": the row was flagged but nothing was wrong — left out of calibration and finetune from now on. "confirmed": the row was the real thing. "none": withdraw an earlier label.` labels T )
    ( mcp_schema_prop sc `note` `string` `Why, in a sentence.` F )
    ^ sc
}

@ __mcp_sc_patch → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `patch` `object` `The fields to change: alias, clock ("time" | "count"), schedule {below_max, at_max, autoencoder}, max_data_points, versions {name: {enabled, decision_margin, window_minutes, window_points, window_size, step_size, n_estimators, max_samples, contamination}}. Anything else is rejected with the reason.` T )
    ^ sc
}

@ __mcp_sc_confirm s what → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `confirm` `boolean` what T )
    ^ sc
}

@ __mcp_sc_claim → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `owner` `string` `The member (subject from org_users) to record as the model's owner; omitted = the caller.` F )
    ^ sc
}

@ __mcp_sc_source_id → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `id` `string` `Source id, as sources shows it.` T )
    ^ sc
}

// The record's fields (every one optional on an update).
@ __mcp_sc_source_fields Json sc b creating → v {
    ( mcp_schema_prop sc `name` `string` `A name for people.` F )
    : Json kinds ( json_arr_new )
    ( json_arr_push kinds ( json_str_lit `wfs` ) )
    ( json_arr_push kinds ( json_str_lit `http` ) )
    ( json_arr_push kinds ( json_str_lit `csv` ) )
    ( mcp_schema_prop_enum sc `kind` `string` `The kind of service: "wfs" (an OGC WFS 2.0 endpoint), "http" (any URL answering JSON) or "csv" (any URL answering a CSV file — a header row, then one row per record; read by the same parser the import route uses, so a file that imports cleanly fetches cleanly).` kinds F )
    ( mcp_schema_prop sc `url` `string` `For wfs: the endpoint (https://opendata.fmi.fi/wfs); for http and csv: the URL as it is to be requested, query string and all.` creating )
    ( mcp_schema_prop sc `model` `string` `The model the points go into (letters, numbers, underscores); created on the first run if it does not exist.` creating )
    : Json modes ( json_arr_new )
    ( json_arr_push modes ( json_str_lit `stored` ) )
    ( json_arr_push modes ( json_str_lit `type` ) )
    ( mcp_schema_prop_enum sc `mode` `string` `wfs: "stored" for a stored query (a weather service's fmi::observations::weather::simple), "type" for a feature type (a GeoServer's or MapServer's layer).` modes F )
    ( mcp_schema_prop sc `query` `string` `wfs: the stored query id, or the feature type name — source_catalog lists them.` F )
    ( mcp_schema_prop sc `params` `object` `wfs: the query's parameters as strings — a stored query's place / fmisid / bbox / timestep; a feature type's count / bbox / cql_filter / sortBy.` F )
    ( mcp_schema_prop sc `features` `array` `The columns to take as features (names from source_preview); empty = every column.` F )
    ( mcp_schema_prop sc `categorical` `array` `Columns to store as text so each value is an identity the anomaly is judged against — a station code, a place.` F )
    ( mcp_schema_prop sc `time_field` `string` `The clock of a feature type, an http source or a csv source: a date column's name, "" to detect one, "none" to stamp every record with the fetch time (a snapshot series). A csv feed that repeats rows on every fetch — a rolling "last day" file — needs this: only rows newer than the newest already stored are taken.` F )
    ( mcp_schema_prop sc `interval_minutes` `integer` `How often to fetch (default 10).` F )
    ( mcp_schema_prop sc `history_hours` `integer` `How far back the first run reaches (default 168, a week: a daily rhythm seen seven times).` F )
    ( mcp_schema_prop sc `allow_future` `boolean` `Take records dated past the fetch time (a price list published ahead). Default false: they wait for their hour.` F )
    ( mcp_schema_prop sc `finetune_rate` `number` `The share of the ring the first train's calibration flags (default 0.01; 0 = leave the default margins). Runs after the first never touch the margins; finetune does, on request.` F )
    ( mcp_schema_prop sc `calendar` `boolean` `Give the model the observation time as calendar features (default true).` F )
    ( mcp_schema_prop sc `enabled` `boolean` `Fetch on the schedule (default true); false keeps the record and stops the runs.` F )
    : Json methods ( json_arr_new )
    ( json_arr_push methods ( json_str_lit `GET` ) )
    ( json_arr_push methods ( json_str_lit `POST` ) )
    ( json_arr_push methods ( json_str_lit `PUT` ) )
    ( mcp_schema_prop_enum sc `method` `string` `http: GET, POST or PUT (default GET).` methods F )
    ( mcp_schema_prop sc `headers` `object` `http: request headers as strings — an Authorization, the Digitraffic-User a service requires. A header whose NAME contains authorization, cookie, key, token, secret or password is treated as a credential: source and sources show its value masked, and sending the mask back keeps the stored value. Any other header is shown as it is.` F )
    ( mcp_schema_prop sc `body` `string` `http: the request body for POST / PUT.` F )
    ( mcp_schema_prop sc `path` `string` `http: where the records are in the answer — dotted, indexes allowed (data.items, stations.0.values); empty for the whole answer. An array gives one record per element, an object one record.` F )
}

@ __mcp_sc_create_source → Json {
    : Json sc ( mcp_schema_obj )
    ( __mcp_sc_source_fields sc T )
    ^ sc
}

@ __mcp_sc_update_source → Json {
    : Json sc ( __mcp_sc_source_id )
    ( __mcp_sc_source_fields sc F )
    ^ sc
}

@ __mcp_sc_delete_source → Json {
    : Json sc ( __mcp_sc_source_id )
    ( mcp_schema_prop sc `confirm` `boolean` `Must be true: the source and its schedule are removed for good (the model and the points it fetched stay).` T )
    ^ sc
}

@ __mcp_sc_run_source → Json {
    : Json sc ( __mcp_sc_source_id )
    ( mcp_schema_prop sc `backfill_hours` `integer` `Reach this many hours back before what has been fetched, instead of forward from it.` F )
    ^ sc
}

@ __mcp_sc_catalog → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `url` `string` `The WFS endpoint.` T )
    ( mcp_schema_prop sc `filter` `string` `Keep the entries whose id or title contains this (case-insensitive) — "observations", "weather", "t2m".` F )
    ( mcp_schema_prop sc `query` `string` `One entry's id: answers with that entry in full, its parameters included.` F )
    ^ sc
}

@ __mcp_sc_preview → Json {
    : Json sc ( mcp_schema_obj )
    ( __mcp_sc_source_fields sc F )
    ( mcp_schema_prop sc `hours` `integer` `How many of the last hours to fetch (default 24).` F )
    ^ sc
}

@ __mcp_sc_role → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `subject` `string` `The member's subject, from org_users.` T )
    : Json roles ( json_arr_new )
    ( json_arr_push roles ( json_str_lit `admin` ) )
    ( json_arr_push roles ( json_str_lit `viewer` ) )
    ( mcp_schema_prop_enum sc `role` `string` `The new role.` roles T )
    ^ sc
}

// ── The server ───────────────────────────────────────────────────────

@ __mcp_instructions → s {
    ^ `Anomaly detection over an organisation's sensor and event streams: every model watches one stream, stores its recent points in a ring, and flags points its versions (isolation forests over different windows, an autoencoder that sees the relations between fields, a range_guard that flags a single field far outside its usual range and names it, a flatline guard that flags a numeric column that has stopped moving — a run of identical readings, or a spread collapsed far below the stream's own quiet periods — and names it, and an optional forecast version — a seasonal ARIMA per numeric feature — that flags a reading far from what the feature's own recent past forecast for that moment, ordinary value or not, and names it) score as unusual. You act with the signed-in user's permissions, inside their organisation.

Start with list_models. Then anomalies {model, last: "24h"} for the newest flagged rows with the features that caused them, anomaly_summary for counts, events, timeline and the features blamed most, point for one row in full, describe_model for how a model is built, calibration for how its margins sit against the recent data. Times are ISO-8601 UTC; a model on a count clock numbers its rows instead. "last" counts back from the model's newest point, not from now. Scores run downward into anomaly: a point is flagged when its score is at or below minus the version's margin. A forest's decision_margin is that margin as is; the autoencoder's decision_margin is a fraction of its reconstruction threshold (margin = threshold × decision_margin), so its scores are ~1e-4 where a forest's are ~1e-1; range_guard's decision_margin is a count of standard deviations; flatline's is a fraction (0.9 = nine tenths of the reference run identical, or the window ten times flatter than the stream's quiet periods); forecast's is a count of the forecast's standard errors (4 = the reading sat four standard errors from what was forecast), and point shows which column each of them named. Rank points and versions by severity (−score / margin: 1.0 is exactly on the alert line, 2.0 twice as far past it), never by raw score; a row's score and severity are those of its most severe version. Consecutive anomalous rows are one event: anomalies gives each row its event number, anomaly_summary lists the events — count events, not rows, when saying how often something went wrong. When the person says a flagged row was nothing, label_anomaly {model, index, label: "false_positive"} — from then on calibration and finetune leave it out, so the margins stop paying for known noise.

Every member may build scratch models named llm_… (fork_model: a slice of an existing model's history, optionally fewer columns), tune them (finetune, train_autoencoder, train_forecast, retrain), edit and delete them — use them to test a hypothesis without touching production models. Changing or deleting any other model needs the administrator role; the reply says so when it does. Sending new points (ingest_point, import_data) needs the ingest capability, and so does forecast_point, which stores a point and answers with the forecast from it; forecast reads the forecast from the newest stored point and forecast_backtest says how good the forecasts have been against naive baselines. Data sources — a WFS stored query or feature type, or a URL answering JSON, fetched on a schedule into a model — are listed by sources and shown by source for every member; an administrator adds one with create_source (source_catalog and source_preview first, to find the query and choose its columns), changes it with update_source, fetches now with run_source, removes it with delete_source. analyze_data scores a file you provide without creating a model.`
}

@ __mcp_add McpServer srv s name s desc Json sc b ro b destr b idem b ow ( @ b Json ) vis ( @ Json Json McpCall ) h → v {
    ( mcp_server_add_tool_gated srv name desc sc ro destr idem ow vis h )
}

@ __mcp_build_server → McpServer {
    : McpServer srv ( mcp_server_new `anomaly` ANOMALY_VERSION )
    ( mcp_server_set_instructions srv ( __mcp_instructions ) )
    : ( @ b Json ) member \ Json c → b { ^ ( __mcp_vis_member c ) }
    : ( @ b Json ) ingest \ Json c → b { ^ ( __mcp_vis_ingest c ) }
    : ( @ b Json ) admin \ Json c → b { ^ ( __mcp_vis_admin c ) }

    // ── Reading (every member) ──
    ( __mcp_add srv `whoami`
    `Who you are here: organisation, role, and what that role lets you do through these tools.`
    ( mcp_schema_empty ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_whoami a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `list_models`
    `Every model the organisation has: name, how many columns it watches, points seen, last training time, and which versions judge. Start here; a name from this list is what the other tools take as "model". detail: true adds every column name, every version's margin and the ring cap — one model's worth of that is describe_model.`
    ( __mcp_sc_list_models ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_list_models a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `describe_model`
    `How one model is built: column types, categories, feature names, the retraining schedule, every version's geometry and margin, the autoencoder's and the forecast's state, the flatline guard's reference per column (what each column's own habit is, and the run of identical readings the margin flags it at), the readings left out of the last fit as impossible, the owner — and which fields edit_model may change. edit_model answers with the same record.`
    ( __mcp_sc_model ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_describe_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `anomalies`
    `The newest flagged points of a model in a window (default: everything stored): each with its time, score, the versions that flagged it, its values, and the features the autoencoder blames with what it expected instead. The reply says how many anomalies the window held, so a partial list is never mistaken for the whole. all_points=true lists unflagged rows too.`
    ( __mcp_sc_anomalies ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_anomalies a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `anomaly_summary`
    `A window in one screen: points and anomalies counted, the rate, counts per version, first/latest/worst anomaly, the events (runs of consecutive anomalous rows — a hundred flagged rows may be three events), a timeline of anomaly and event counts, and the features blamed most often. Cheap enough to call before anomalies; call it for "how has <model> been doing".`
    ( __mcp_sc_summary ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_anomaly_summary a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `points`
    `Raw stored rows of a model (newest N of a window) with their ring index and time — the data itself, flagged or not. For "what did the sensor read around 06:00" and for eyeballing normal behaviour.`
    ( __mcp_sc_points ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_points a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `point`
    `One stored row by the ring index an anomalies row carries: every value it had.`
    ( __mcp_sc_point ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `calibration`
    `How each version's margin sits against a window (default: the last 24 h before the newest point; last: "all" for the whole ring): how much it flags now, the worst and median scores, and the margin that would flag 0.1%, 1%, 5% … — the numbers to read before finetune. Each version gets a reading — quiet, loud or on target — and the model a verdict.`
    ( __mcp_sc_model_window ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_calibration a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `forecast_backtest`
    `How good a model's forecasts are, measured: a rolling-origin backtest over the newest stored rows — per feature and step the mean absolute error, MAPE, the 95 % interval's coverage, and the skill against the two forecasts anyone can make without a model (the last value, the value a season earlier; 1 = perfect, 0 = no better, negative = worse).`
    ( __mcp_sc_backtest ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_forecast_backtest a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `audit`
    `Who set which margin to what, when: every change of a version's alert line — by a person's edit or finetune, by a source's or an import's first-train calibration (actor "source:<id>"), or by a key — newest last.`
    ( __mcp_sc_audit ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_audit a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `sources`
    `The organisation's data sources: what is fetched from where into which model and how often, each with its last run's outcome (status, error, rows) and whether a fetch is in flight.`
    ( mcp_schema_empty ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_get ( mcp_call_context c ) `/api/org/sources` ) } )
    ( __mcp_add srv `source`
    `One data source in full — its kind, URL, query and parameters, the columns taken, the model, the schedule, the span fetched so far and the run statistics. A header value that carries a credential is masked (a name containing authorization, cookie, key, token, secret or password); one that only names the caller — a Digitraffic-User, an Accept — is shown as it is, because knowing what is being sent is the point of reading the record. Sending a masked value back on an edit keeps the stored secret.`
    ( __mcp_sc_source_id ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_source a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `forecast`
    `What a model's forecast version expects next: for every feature it watches, the next horizon values with standard errors, and the fitted order. Needs a trained forecast version (train_forecast).`
    ( __mcp_sc_forecast ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_forecast a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `score_point`
    `Score one hypothetical point against a model WITHOUT storing it: the verdict of every version and the scores. For "would the model flag this".`
    ( __mcp_sc_values `a column the model knows and the point leaves out is an error that names it.` ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_score_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `analyze_data`
    `Score a file on its own, with no model kept: a self-trained model finds the time column, learns the file, and reports its anomalies, margins and notes. The file is csv text, rows, or — cheapest by far — the name of one the organisation's folder already holds (list_files). The margins are set from the file itself, so about 1 % of any file is flagged — read "reading", "separation" and "stands_apart_rows" first: they say whether some block of rows really stands apart from the file or whether what is flagged is merely its least typical tail. For a one-off "what is odd in this data". Big files return a task to poll with task.`
    ( __mcp_sc_analyze ) F F F F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_analyze_data a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `list_tasks`
    `The organisation's background jobs (analyses, imports): id, state, what they were, when.`
    ( mcp_schema_empty ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_get ( mcp_call_context c ) `/api/org/tasks` ) } )
    ( __mcp_add srv `task`
    `One task by id — the result once done (an analysis's anomalies and margins, an import's counts), or its state while running.`
    ( __mcp_sc_id ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_task a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `list_files`
    `The organisation's folder: files analyses and imports left behind, with sizes and dates.`
    ( mcp_schema_empty ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_get ( mcp_call_context c ) `/api/org/files` ) } )

    // ── Changing models (every member for llm_…, administrators for the rest) ──
    ( __mcp_add srv `fork_model`
    `Create a NEW model trained on a slice of an existing model's stored history — a window, optionally only some columns — and scan that history with it. Name it llm_<something> and it is yours to make, tune and delete regardless of role (a scratch model); any other name needs an administrator. Needs at least 50 points in the slice. This is how you test "would a model of only these fields / this period flag the same things".`
    ( __mcp_sc_fork ) F F F F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_fork_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `retrain`
    `Retrain a model's forests on its stored points now, instead of waiting for the schedule. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_model ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_retrain a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `train_autoencoder`
    `Train (or retrain) a model's autoencoder version — the one version that learns the relations between fields, and the source of per-feature blame in anomalies. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_train_ae ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_train_autoencoder a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `train_forecast`
    `Train (or retrain) a model's forecast version — a seasonal ARIMA per numeric feature that judges every reading against what the feature's own recent past said it would be, and names the feature. Switches the version on. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_train_fc ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_train_forecast a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `finetune`
    `Set the margins so that a chosen share of a window is flagged (rate 0.01 = 1%). On a model with votes = 1 — the default, where any one version flagging is enough — the share is EACH version's own, as it always has been. On a model that requires a consensus (votes = N), the share is the MODEL's: every tunable version is placed at the same quantile of its own scores, found so that N of them together flag the rate asked for, and the answer's "consensus" block says what each version was set to on its own to get there. dry_run=true shows the margins without applying them; calibration shows the same numbers for several rates at once. The flatline guard's margin is left alone either way (it is a fraction of each column's own reference run, not a rate; edit_model sets it) — but it counts towards the consensus like any other version. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_finetune ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_finetune a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `label_anomaly`
    `Say what a flagged row was: false_positive (nothing was wrong — calibration and finetune leave it out from then on), confirmed, or none to withdraw. The label shows on the row in anomalies; labels lists them. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_label ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_label_anomaly a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `labels`
    `The labels readers have put on a model's rows, with the row's index (or evicted when the ring has let it go), who said it and when.`
    ( __mcp_sc_model ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_labels a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `edit_model`
    `Change a model's settings: alias, clock, retraining schedule, ring size, votes (how many versions must agree before the model calls a point an anomaly — 1, any one, unless raised), and per-version enabled / decision_margin / geometry. Rejected fields come back with the reason, and so does anything the config could not hold. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_patch ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_edit_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `reset_model`
    `Drop every stored point and every forest of a model but keep its name and settings — it starts learning again from nothing. Irreversible; confirm=true required. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_confirm `Must be true. Resetting cannot be undone.` ) F T T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_reset_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `delete_model`
    `Delete a model with its data and forests, for good. confirm=true required. Members: llm_… models only (clean up your scratch models with this); administrators: any.`
    ( __mcp_sc_confirm `Must be true. Deleting cannot be undone.` ) F T T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_delete_model a ( mcp_call_context c ) ) } )

    // ── Feeding models (the ingest capability: administrators and ingest keys) ──
    ( __mcp_add srv `ingest_point`
    `Send one point to a model: it is stored, scored, and answered with the verdict. A new name creates a model, which warms up (HTTP 202) until it has 50 points. This changes what the model learns — use score_point to ask without teaching.`
    ( __mcp_sc_values `a column the model knows and the point leaves out is stored as absent, scored as its training mean (no version blames it), and listed under "missing" in the verdict. A value is a finite number, or something that reads as one: a numeric string ("12.5"), and true/false as 1/0 — a status flag is a 0/1 channel and is one of the things a stream watches. "1e999" and anything else with no finite value are refused, and a boolean landing in a column of real measurements is stored and judged like any other reading far outside that column's range (range_guard names it, and absurd_readings keeps it out of the fits). A reading too far from its feature's own range to be a measurement of it is stored and flagged like any other, but is left out of every fit, so one broken sensor cannot make its feature stop being watched; describe_model reports those under "absurd_readings".` ) F F F F ingest
    \ Json a McpCall c → Json { ^ ( __mcp_t_ingest_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `forecast_point`
    `ingest_point's twin: store a point and get, with its verdict, the forecast from it — the next horizon values of every watched feature with 80 % and 95 % intervals and their times. A model without a trained forecast version gets one fitted here once it has trained.`
    ( __mcp_sc_forecast_point ) F F F F ingest
    \ Json a McpCall c → Json { ^ ( __mcp_t_forecast_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `import_data`
    `Load a file of history into a model — a new one or an existing one. The file is csv text, rows, or the name of one the organisation's folder already holds (list_files), which costs nothing to send. The time column is detected (or named with time); rows are stamped, stored and the model trained. Answers with the counts imported and skipped, and with whether the margins were calibrated from this history — a model already trained keeps the margins it has, and not_calibrated_because says so.`
    ( __mcp_sc_import ) F F F F ingest
    \ Json a McpCall c → Json { ^ ( __mcp_t_import_data a ( mcp_call_context c ) ) } )

    // ── The organisation (administrators) ──
    ( __mcp_add srv `claim_model`
    `Record an owner for a model that has none (one that predates sign-in), or hand one over to another member.`
    ( __mcp_sc_claim ) F F T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_claim_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `org_users`
    `The organisation's members: subject, name, email, role, first and last seen.`
    ( mcp_schema_empty ) T F T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_get ( mcp_call_context c ) `/api/org/users` ) } )
    ( __mcp_add srv `set_role`
    `Make a member an administrator or a viewer. The last administrator cannot be demoted.`
    ( __mcp_sc_role ) F F T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_set_role a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `org_keys`
    `The organisation's API keys: id, role, label, who created it, last use, revoked or not. Keys are created and revoked in the dashboard — a secret must not pass through a conversation.`
    ( mcp_schema_empty ) T F T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_get ( mcp_call_context c ) `/api/org/keys` ) } )
    ( __mcp_add srv `create_source`
    `Add a data source the server fetches on a schedule into a model: a WFS stored query or feature type (source_catalog lists a service's; source_preview shows a query's columns), or any URL answering JSON with the headers it needs. Administrators only.`
    ( __mcp_sc_create_source ) F F F F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_create_source a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `update_source`
    `Change a data source: any field of create_source — its kind and settings, the columns, the model, the schedule, enabled or not. Fields left out keep their values. Administrators only.`
    ( __mcp_sc_update_source ) F F T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_update_source a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `delete_source`
    `Remove a data source and its schedule (confirm: true). The model and the points already fetched stay. Administrators only.`
    ( __mcp_sc_delete_source ) F T T F admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_delete_source a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `run_source`
    `Fetch a data source now — forward from what has been fetched, or backfill_hours back before it — and report what came of it. Administrators only.`
    ( __mcp_sc_run_source ) F F F T admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_run_source a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `source_catalog`
    `What a WFS offers: its feature types and, where it publishes them, its stored queries with their parameters — the ids create_source's query takes. Fetches the service. Administrators only.`
    ( __mcp_sc_catalog ) T F T T admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_source_catalog a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `source_preview`
    `Fetch the last hours of a stored query, a feature type's features, or an http or csv source's answer, and show the columns it would give — name, kind, count, distinct values, min, max, last — with a few sample rows, so the features and categorical columns can be chosen before create_source. Administrators only.`
    ( __mcp_sc_preview ) T F T T admin
    \ Json a McpCall c → Json { ^ ( __mcp_t_source_preview a ( mcp_call_context c ) ) } )
    ^ srv
}

// ── HTTP ─────────────────────────────────────────────────────────────

// The origin to build absolute URLs on: configured, else from the request.
@ __mcp_base HttpRequest req → String {
    : *McpWiring w ( __mcp_wiring )
    ? > ( string_len . w public_url ) 0 { ^ ( string_from ( string_data . w public_url ) ) } {}
    ^ ( mcp_auth_base_url req `` )
}

// GET /.well-known/oauth-protected-resource[/mcp] — RFC 9728: which
// authorization server issues tokens for /mcp, and which scope to ask for.
// The same issuer and audience the dashboard uses. 404 in simple mode:
// there is no sign-in to point at.
@ an_mcp_metadata_response HttpRequest req → HttpResponse {
    ? ( anomaly_authz_enabled ) {} { ^ ( response_text 404 `not found\n` ) }
    : String base ( __mcp_base req )
    : String resource ( string_from ( string_data base ) )
    ( string_push_str resource `/mcp` )
    : String scope ( string_from ( anomaly_authz_audience ) )
    ( string_push_str scope `/access_as_user` )
    : Json md ( mcp_auth_resource_metadata ( string_data resource ) ( anomaly_authz_issuer ) ( string_data scope ) )
    : HttpResponse r ( mcp_auth_metadata_response md )
    ( string_free scope )
    ( string_free resource )
    ( string_free base )
    ^ r
}

// The /mcp endpoint. Called inside the service lock, like every handler.
@ an_mcp_handle HttpRequest req → HttpResponse {
    : Principal p ( authz_principal req )
    // No credential, or one that did not verify: the 401 that tells an MCP
    // client where to sign in (WWW-Authenticate → resource metadata →
    // authorization server), and why.
    ? & ( anomaly_authz_enabled ) ! . p authed {
        ( principal_free p )
        : String base ( __mcp_base req )
        : String mdpath ( mcp_auth_metadata_path `/mcp` )
        : String mdurl ( string_from ( string_data base ) )
        ( string_push_str mdurl ( string_data mdpath ) )
        ( string_free mdpath )
        : s why ( anomaly_authz_last_error )
        // A credential was PRESENTED — as a bearer token or in X-API-Key,
        // the two places authz_principal reads — and refused: that is
        // invalid_token, and the description says why. Nothing presented
        // is the plain invitation to sign in.
        : b had_token | ?? ( mcp_auth_bearer_token req ) { T t → { ( string_free t ) T } F → F }
        ?? ( header_get . req headers `x-api-key` ) { T v → { ( string_free v ) T } F → F }
        : HttpResponse r ( mcp_auth_challenge ( string_data mdurl )
        ? had_token `invalid_token` `unauthorized`
        ? > ( nurl_str_len why ) 0 why `sign in to the anomaly service, or send an API key as the bearer token` )
        ( string_free mdurl )
        ( string_free base )
        ^ r
    } {}
    : Json ctx ( __mcp_ctx_of req p )
    ( principal_free p )
    : McpServer srv ( __mcp_server )
    : ( @ ?Json Json ) d \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv rq ctx ) }
    : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler d )
    : HttpResponse out ( h req )
    ( nurl_free # s # *u h 1 )
    ( nurl_free # s # *u d 1 )
    ( json_free ctx )
    ^ out
}
