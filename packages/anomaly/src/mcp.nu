// anomaly/mcp.nu — the service as an MCP server, mounted at /mcp.
//
// A language model talks to the same service the dashboard does, with the
// same credential, and gets exactly what that credential may do: the tool
// list is computed per caller (a viewer never sees `delete_model`), and
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
: s ANOMALY_VERSION `0.13.0`

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

@ __mcp_api_out_free ApiOut o → v { ( json_free . o body ) }

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
    : Json out ( mcp_tool_result_error ( string_data m ) )
    ( string_free m )
    ^ out
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

// A span: seconds as a number, or "90s" / "15m" / "24h" / "7d" / "2w".
// 0 when absent, -1 when unreadable.
@ __mcp_arg_span Json a s key → i {
    ?? ( __mcp_arg a key ) {
        T v → {
            ? ( json_is_null v ) { ^ 0 } {}
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s raw ( json_str_data v )
                ? == ( nurl_str_len raw ) 0 { ^ 0 } {}
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
    ? < last 0 { ^ ( mcp_tool_result_error `last: not a span — use seconds or 90s / 15m / 24h / 7d / 2w` ) } {}
    ? > from 0 { ( __mcp_q_add_int q `from` from ) } {}
    ? > to 0 { ( __mcp_q_add_int q `to` to ) } {}
    ? > last 0 { ( __mcp_q_add_int q `last` last ) } {}
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

// A tool that needs a model name; `` when the argument is missing.
@ __mcp_need_model Json a → String {
    ^ ( __mcp_arg_str a `model` )
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
@ __mcp_model_brief s name Json mj → Json {
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
            ( json_obj_set m `columns` cols )
        }
        F _ → {}
    }
    ( __mcp_copy mj `n_points_seen` m )
    ( __mcp_copy mj `max_data_points` m )
    ( __mcp_training_of mj m )
    ?? ( json_obj_get mj `versions` ) {
        T vs → {
            : Json out ( json_obj_new )
            ( json_obj_each vs \ s vn Json vo → v {
                : Json v ( json_obj_new )
                ( __mcp_copy vo `decision_margin` v )
                ( __mcp_copy vo `enabled` v )
                ( json_obj_set out vn v )
            } )
            ( json_obj_set m `versions` out )
        }
        F _ → {}
    }
    ^ m
}

@ __mcp_t_list_models Json a Json ctx → Json {
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` `/models/dynamic` q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json out ( json_obj_new )
    ( json_obj_set out `organization` ( json_str_lit ( __mcp_ctx_str ctx `organization` ) ) )
    : Json arr ( json_arr_new )
    : ~ i n 0
    ?? ( json_obj_get . o body `models` ) {
        T ms → {
            ( json_obj_each ms \ s name Json mj → v {
                ( json_arr_push arr ( __mcp_model_brief name mj ) )
            } )
            = n ( json_arr_len arr )
        }
        F _ → {}
    }
    ( json_obj_set out `count` ( json_int n ) )
    ( json_obj_set out `models` arr )
    ( json_obj_set out `hint` ( json_str_lit ? == n 0
    `No models yet. fork_model needs a source; analyze_data scores a file without a model; import_data (ingest role) creates one from a file.`
    `Times are ISO-8601 UTC; on a count clock rows are numbered instead. Next: anomalies {model, last:"24h"} or anomaly_summary.` ) )
    ( __mcp_api_out_free o )
    ^ ( __mcp_result_json out )
}

@ __mcp_t_describe_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String path ( __mcp_model_path `/models/dynamic/` model `/metadata` )
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` ( string_data path ) q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ( string_free path )
    ( string_free model )
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
    : Json out ( json_obj_new )
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `alias` out )
    ( __mcp_copy b `owner` out )
    ( json_obj_set out `scratch` ( json_bool ( az_is_scratch_model ( __mcp_ctx_str b `model_name` ) ) ) )
    ( __mcp_copy b `clock` out )
    ( __mcp_copy b `created` out )
    ( __mcp_copy b `column_types` out )
    ( __mcp_copy b `categories` out )
    ( __mcp_copy b `feature_names` out )
    ( __mcp_copy b `n_points_seen` out )
    ( __mcp_copy b `max_data_points` out )
    ( __mcp_training_of b out )
    ( __mcp_copy b `schedule` out )
    ( __mcp_copy b `versions` out )
    ?? ( json_obj_get b `autoencoder` ) {
        T ae → {
            : Json ao ( json_obj_new )
            ( __mcp_copy ae `trained` ao )
            ( __mcp_copy ae `enabled` ao )
            ( __mcp_copy_rounded ae `reconstruction_threshold` ao 5 )
            ( __mcp_copy ae `decision_margin` ao )
            ( __mcp_copy ae `training_data_points` ao )
            ( __mcp_copy ae `layer_sizes` ao )
            ( __mcp_when_of ae `trained_at` ao `trained` F )
            ( json_obj_set out `autoencoder` ao )
        }
        F _ → {}
    }
    ( __mcp_copy b `editable_fields` out )
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
    ( __mcp_copy r `anomaly` o )
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
        }
        F _ → {}
    }
    ^ o
}

// The window as the API saw it (data_points_count / considered /
// anomalies), so a partial listing says what it is a part of.
@ __mcp_scan_summary Json b Json out → v {
    ( __mcp_copy b `model_name` out )
    ( __mcp_copy b `clock` out )
    ( json_obj_set out `points_in_window` ( json_int ( __mcp_int_of b `considered` ) ) )
    ( json_obj_set out `anomalies_in_window` ( json_int ( __mcp_int_of b `anomalies` ) ) )
    ( json_obj_set out `points_stored` ( json_int ( __mcp_int_of b `data_points_count` ) ) )
    ( __mcp_copy b `model_versions` out )
}

@ __mcp_int_of Json o s key → i {
    ?? ( json_obj_get o key ) {
        T v → { ^ ( json_as_int v ) }
        F _ → { ^ 0 }
    }
}

@ __mcp_t_anomalies Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ~ i count ( __mcp_arg_int a `count` 20 )
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
    : b cc ( __mcp_count_clock b )
    : Json out ( json_obj_new )
    ( __mcp_scan_summary b out )
    : Json rows ( json_arr_new )
    ?? ( json_obj_get b `points` ) {
        T pts → { ( json_arr_each pts \ Json r → v { ( json_arr_push rows ( __mcp_row_json r cc ) ) } ) }
        F _ → {}
    }
    : i shown ( json_arr_len rows )
    : i total ? all_points ( __mcp_int_of b `considered` ) ( __mcp_int_of b `anomalies` )
    ( json_obj_set out `returned` ( json_int shown ) )
    ? > total shown {
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

// Per-feature attribution totals across the flagged rows.
: FeatShare {
    String name
    f share
    i n
}

@ __mcp_t_anomaly_summary Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : ~ i buckets ( __mcp_arg_int a `buckets` 12 )
    ? <= buckets 0 { = buckets 12 } {}
    ? > buckets 48 { = buckets 48 } {}
    : ApiOut o ( __mcp_scan a ctx model 0 3 T )
    ( string_free model )
    ? == . o status 0 { ^ . o body } {}
    ? ( __mcp_api_ok o ) {} { : Json e ( __mcp_api_error o ) ( __mcp_api_out_free o ) ^ e }
    : Json b . o body
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
    : Json per_version ( json_obj_new )
    : ( Vec FeatShare ) feats ( vec_new [FeatShare] )
    : ~ i first_ts 0
    : ~ i last_ts 0
    // Scores run DOWNWARD into anomaly: a point is flagged when its score
    // falls below minus the margin, so the worst row is the lowest score.
    : ~ f worst 0.0
    : ~ i worst_idx -1
    : ~ i worst_ts 0
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
                        ? | == first_ts 0 < ts first_ts { = first_ts ts } {}
                        ? > ts last_ts { = last_ts ts } {}
                        : f sc ( __mcp_f_of r `score` )
                        ? | < worst_idx 0 < sc worst { = worst sc = worst_idx ( __mcp_int_of r `index` ) = worst_ts ts } {}
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
    ? > nanom 0 {
        ( json_obj_set out `first_anomaly` ( __mcp_when first_ts cc ) )
        ( json_obj_set out `latest_anomaly` ( __mcp_when last_ts cc ) )
        : Json w ( json_obj_new )
        ( json_obj_set w `index` ( json_int worst_idx ) )
        ( json_obj_set w `time` ( __mcp_when worst_ts cc ) )
        ( json_obj_set w `score` ( __mcp_round_f worst 4 ) )
        ( json_obj_set out `worst` w )
    } {}

    // Timeline: the flagged rows counted into `buckets` equal slices
    // between the first and the latest of them.
    : i nst ( vec_len [i] stamps )
    ? & > nst 1 > last_ts first_ts {
        : Json tl ( json_arr_new )
        : i span - last_ts first_ts
        : ( Vec i ) counts ( vec_new [i] )
        : ~ i k 0
        ~ < k buckets { ( vec_push [i] counts 0 ) = k + k 1 }
        = k 0
        ~ < k nst {
            : i ts ( __mcp_iget stamps k )
            : ~ i bi / * - ts first_ts buckets span
            ? >= bi buckets { = bi - buckets 1 } {}
            ? < bi 0 { = bi 0 } {}
            : b _s ( vec_set [i] counts bi + ( __mcp_iget counts bi ) 1 )
            = k + k 1
        }
        = k 0
        ~ < k buckets {
            : i bstart + first_ts / * k span buckets
            : Json bo ( json_obj_new )
            ( json_obj_set bo `from` ( __mcp_when bstart cc ) )
            ( json_obj_set bo `anomalies` ( json_int ( __mcp_iget counts k ) ) )
            ( json_arr_push tl bo )
            = k + k 1
        }
        ( vec_free [i] counts )
        ( json_obj_set out `timeline` tl )
    } {}
    ( vec_free [i] stamps )

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
                        ( json_obj_each rec \ s key Json v → v {
                            ? == ( nurl_str_eq key `timestamp` ) 1 {} {
                                ? ( json_is_num v ) { ( json_obj_set row key ( __mcp_round v 4 ) ) }
                                { ( json_obj_set row key ( json_clone v ) ) }
                            }
                        } )
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
    : String model ( __mcp_need_model a )
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
    : String model ( __mcp_need_model a )
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

@ __mcp_t_calibration Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
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
            ( __mcp_copy w `total` wo )
            ( json_obj_set out `window` wo )
        }
        F _ → {}
    }
    ?? ( json_obj_get b `aggregate` ) {
        T ag → {
            : Json ao ( json_obj_new )
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
                ( __mcp_copy v `margin` one )
                ( __mcp_copy v `n` one )
                ( __mcp_copy v `flagged` one )
                ( __mcp_copy_rounded v `rate` one 4 )
                ( __mcp_copy_rounded v `worst` one 4 )
                ( __mcp_copy_rounded v `median` one 4 )
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
    ( json_obj_set out `reading` ( json_str_lit `A version flags a row when its score is at or below -margin (score = decision function; the more negative, the more anomalous); rate = flagged / n over this window. margin_for_rate gives, per requested rate, the nearest margin the window's scores can supply: when scores tie at the cut the achieved rate differs from the requested one (exact = false) — a run of identical scores is taken or left whole. Margins are shown exactly as stored. finetune {model, rate} sets them.` ) )
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

@ __mcp_t_score_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
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
            ^ ( __mcp_pass o )
        }
        F _ → { ( string_free model ) ^ ( __mcp_no_values ) }
    }
}

@ __mcp_t_ingest_point Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
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
            ^ ( __mcp_pass o )
        }
        F _ → { ( string_free model ) ^ ( __mcp_no_values ) }
    }
}

// ── Tools: files, tasks, analyses ────────────────────────────────────

@ __mcp_t_get Json ctx s path → Json {
    : String q ( string_new )
    : ApiOut o ( __mcp_api ctx `GET` path q @ ?Json { F @ Json { JNull } } )
    ( string_free q )
    ^ ( __mcp_pass o )
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
@ __mcp_file_arg Json a String text → s {
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
    ^ ( mcp_tool_result_error `csv or rows: required — csv is the file's text (header row first); rows is an array of objects, one per point` )
}

// The import/analyze query the two share: format, time, tz, calendar, clock.
@ __mcp_q_file Json a String q s content_type → v {
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
    : ApiOut o ( __mcp_api_send ctx `POST` `/api/analyze` q ct ( string_data text ) )
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
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : String text ( string_new )
    : s ct ( __mcp_file_arg a text )
    ? > ( nurl_str_len ct ) 0 {} { ( string_free text ) ( string_free model ) ^ ( __mcp_no_file ) }
    : String q ( string_new )
    ( __mcp_q_file a q ct )
    : String path ( __mcp_model_path `/models/dynamic/` model `/import` )
    : ApiOut o ( __mcp_api_send ctx `POST` ( string_data path ) q ct ( string_data text ) )
    ( string_free path )
    ( string_free q )
    ( string_free text )
    ( string_free model )
    ^ ( __mcp_pass o )
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
    ? | | < from 0 < to 0 < last 0 {
        ( json_free body )
        ( string_free name )
        ( string_free src )
        ^ ( mcp_tool_result_error `from/to: ISO-8601 or Unix seconds; last: seconds or 24h / 7d / 2w` )
    } {}
    ? > from 0 { ( json_obj_set body `from` ( json_int from ) ) } {}
    ? > to 0 { ( json_obj_set body `to` ( json_int to ) ) } {}
    ? > last 0 { ( json_obj_set body `last` ( json_int last ) ) } {}
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
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json out ( __mcp_model_post ctx `/force_train/` model `` `POST` @ ?Json { F @ Json { JNull } } )
    ( string_free model )
    ^ out
}

@ __mcp_t_train_autoencoder Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json body ( json_obj_new )
    ?? ( __mcp_arg a `hidden` ) {
        T hv → { ? ( json_is_arr hv ) { ( json_obj_set body `hidden` ( json_clone hv ) ) } {} }
        F _ → {}
    }
    ? ( __mcp_arg_has a `contamination` ) { ( json_obj_set body `contamination` ( json_float ( __mcp_arg_f a `contamination` 0.0 ) ) ) } {}
    : Json out ( __mcp_model_post ctx `/train/autoencoder/` model `` `POST` @ ?Json { T body } )
    ( json_free body )
    ( string_free model )
    ^ out
}

@ __mcp_t_finetune Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    : Json body ( json_obj_new )
    ? ( __mcp_arg_has a `rate` ) { ( json_obj_set body `rate` ( json_float ( __mcp_arg_f a `rate` 0.01 ) ) ) } {}
    // `last`: a span, or the words the API knows ("all", "own").
    ?? ( __mcp_arg a `last` ) {
        T lv → {
            ? ( json_is_str lv ) {
                : s raw ( json_str_data lv )
                : i span ( imp_span_of_text raw )
                ? > span 0 { ( json_obj_set body `last` ( json_int span ) ) }
                { ( json_obj_set body `last` ( json_str_lit raw ) ) }
            } {
                ? ( json_is_num lv ) { ( json_obj_set body `last` ( json_int ( json_as_int lv ) ) ) } {}
            }
        }
        F _ → {}
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
    : Json out ( __mcp_model_post ctx `/api/dynamic/` model `/finetune` `POST` @ ?Json { T body } )
    ( json_free body )
    ( string_free model )
    ^ out
}

@ __mcp_t_edit_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ?? ( __mcp_arg a `patch` ) {
        T pv → {
            ? & ( json_is_obj pv ) > ( __mcp_obj_len pv ) 0 {} {
                ( string_free model )
                ^ ( mcp_tool_result_error `patch: required — an object with one or more of alias, clock, schedule, max_data_points, versions (describe_model lists editable_fields and the current values)` )
            }
            : Json out ( __mcp_model_post ctx `/models/dynamic/` model `/metadata` `PUT` @ ?Json { T pv } )
            ( string_free model )
            ^ out
        }
        F _ → {
            ( string_free model )
            ^ ( mcp_tool_result_error `patch: required — an object with one or more of alias, clock, schedule, max_data_points, versions` )
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
    : String model ( __mcp_need_model a )
    ? > ( string_len model ) 0 {} { ( string_free model ) ^ ( __mcp_no_model ) }
    ? ( __mcp_arg_bool a `confirm` F ) {} {
        ( string_free model )
        ^ ( mcp_tool_result_error `confirm: true is required — reset drops every stored point and forest of the model and cannot be undone` )
    }
    : Json out ( __mcp_model_post ctx `/models/dynamic/` model `/reset` `POST` @ ?Json { F @ Json { JNull } } )
    ( string_free model )
    ^ out
}

@ __mcp_t_delete_model Json a Json ctx → Json {
    : String model ( __mcp_need_model a )
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
    : String model ( __mcp_need_model a )
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

// ── Schemas ──────────────────────────────────────────────────────────

@ __mcp_sc_model → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `model` `string` `Model name, as list_models shows it.` T )
    ^ sc
}

// from / to / last on a schema — the window vocabulary every reader shares.
@ __mcp_sc_window Json sc → v {
    ( mcp_schema_prop sc `last` `string` `A span back from the newest stored point (not from now): "24h", "7d", "2w", "90m", or seconds. A model that stopped receiving data still answers about its last day.` F )
    ( mcp_schema_prop sc `from` `string` `Window start: ISO-8601 ("2026-09-01" or "2026-09-01T06:00:00Z"; a bare stamp is read in the server's zone) or Unix seconds.` F )
    ( mcp_schema_prop sc `to` `string` `Window end, same forms as from. With last, the span ends here.` F )
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
    ( mcp_schema_prop sc `fields` `array` `Which of the row's columns to include as values (default: all of them).` F )
    ( mcp_schema_prop sc `contributions` `integer` `Per flagged row, the N features the autoencoder blames most, with the value it saw and the value it expected (default 3, 0 = none). Needs a trained autoencoder.` F )
    ^ sc
}

@ __mcp_sc_summary → Json {
    : Json sc ( __mcp_sc_model_window )
    ( mcp_schema_prop sc `buckets` `integer` `Timeline slices between the first and the latest anomaly (default 12, max 48).` F )
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

@ __mcp_sc_values → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `values` `object` `One point: the model's columns and their values, e.g. {"temperature": 21.5, "state": "on"}. Columns the model does not know are ignored; missing ones are an error.` T )
    ^ sc
}

@ __mcp_sc_id → Json {
    : Json sc ( mcp_schema_obj )
    ( mcp_schema_prop sc `id` `string` `The task_id.` T )
    ^ sc
}

// csv / rows / format / time / tz / calendar / clock — the file vocabulary.
@ __mcp_sc_file Json sc → v {
    ( mcp_schema_prop sc `csv` `string` `The file as text: a header row, then one row per point. Either csv or rows.` F )
    ( mcp_schema_prop sc `rows` `array` `The points as an array of objects (one key per column). Either csv or rows.` F )
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

@ __mcp_sc_finetune → Json {
    : Json sc ( __mcp_sc_model )
    ( mcp_schema_prop sc `rate` `number` `Target alert rate: the share of the window each version should flag, e.g. 0.01 for 1% (default 0.01).` F )
    ( mcp_schema_prop sc `last` `string` `Window: a span ("7d", "24h", seconds), "all" for the whole ring, or "own" for each version's own training period (the default).` F )
    ( mcp_schema_prop sc `from` `string` `Window start, ISO-8601 or Unix seconds.` F )
    ( mcp_schema_prop sc `to` `string` `Window end.` F )
    ( mcp_schema_prop sc `versions` `array` `Only these versions (default: every enabled, trained one).` F )
    ( mcp_schema_prop sc `dry_run` `boolean` `true: report the margins it would set without writing them.` F )
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
    ^ `Anomaly detection over an organisation's sensor and event streams: every model watches one stream, stores its recent points in a ring, and flags points its versions (isolation forests over different windows, and an autoencoder that sees the relations between fields) score as unusual. You act with the signed-in user's permissions, inside their organisation.

Start with list_models. Then anomalies {model, last: "24h"} for the newest flagged rows with the features that caused them, anomaly_summary for counts, timeline and the features blamed most, point for one row in full, describe_model for how a model is built, calibration for how its margins sit against the recent data. Times are ISO-8601 UTC; a model on a count clock numbers its rows instead. "last" counts back from the model's newest point, not from now. Scores run downward into anomaly: a point is flagged when its score falls below minus the version's decision_margin, so the lowest score is the worst point.

Every member may build scratch models named llm_… (fork_model: a slice of an existing model's history, optionally fewer columns), tune them (finetune, train_autoencoder, retrain), edit and delete them — use them to test a hypothesis without touching production models. Changing or deleting any other model needs the administrator role; the reply says so when it does. Sending new points (ingest_point, import_data) needs the ingest capability. analyze_data scores a file you provide without creating a model.`
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
    `Every model the organisation has: name, columns, points seen, last training time, and each version's margin. Start here; a name from this list is what the other tools take as "model".`
    ( mcp_schema_empty ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_list_models a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `describe_model`
    `How one model is built: column types, categories, feature names, the retraining schedule, every version's geometry and margin, the autoencoder's state, the owner — and which fields edit_model may change.`
    ( __mcp_sc_model ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_describe_model a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `anomalies`
    `The newest flagged points of a model in a window (default: everything stored): each with its time, score, the versions that flagged it, its values, and the features the autoencoder blames with what it expected instead. The reply says how many anomalies the window held, so a partial list is never mistaken for the whole. all_points=true lists unflagged rows too.`
    ( __mcp_sc_anomalies ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_anomalies a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `anomaly_summary`
    `A window in one screen: points and anomalies counted, the rate, counts per version, first/latest/worst anomaly, a timeline of anomaly counts, and the features blamed most often. Cheap enough to call before anomalies; call it for "how has <model> been doing".`
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
    `How each version's margin sits against a window: how much it flags now, the worst and median scores, and the margin that would flag 0.1%, 1%, 5% … — the numbers to read before finetune. Says whether a model is too quiet or too loud.`
    ( __mcp_sc_model_window ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_calibration a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `score_point`
    `Score one hypothetical point against a model WITHOUT storing it: the verdict of every version and the scores. For "would the model flag this".`
    ( __mcp_sc_values ) T F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_score_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `analyze_data`
    `Score a file you provide (csv text or rows) on its own, with no model kept: a self-trained model finds the time column, learns the file, and reports its anomalies, margins and notes. For a one-off "what is odd in this data". Big files return a task to poll with task.`
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
    ( __mcp_add srv `finetune`
    `Set every version's margin so that a chosen share of a window is flagged (rate 0.01 = 1%). dry_run=true shows the margins without applying them; calibration shows the same numbers for several rates at once. Members: llm_… models only; administrators: any.`
    ( __mcp_sc_finetune ) F F T F member
    \ Json a McpCall c → Json { ^ ( __mcp_t_finetune a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `edit_model`
    `Change a model's settings: alias, clock, retraining schedule, ring size, and per-version enabled / decision_margin / geometry. Rejected fields come back with the reason. Members: llm_… models only; administrators: any.`
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
    ( __mcp_sc_values ) F F F F ingest
    \ Json a McpCall c → Json { ^ ( __mcp_t_ingest_point a ( mcp_call_context c ) ) } )
    ( __mcp_add srv `import_data`
    `Load a file of history (csv text or rows) into a model — a new one or an existing one. The time column is detected (or named with time); rows are stamped, stored and the model trained. Returns counts of imported / skipped rows and the scan.`
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
