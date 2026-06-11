// http_router.nu — Phase 6 acceptance test for stdlib/ext/http_router.nu.
// Pure-router exercise: builds synthetic HttpRequests, dispatches via
// `router_handle`, prints status + body + selected captured params.
// No socket, no curl — runs unconditionally, like
// http_request_parser.nu and http_response_builder.nu.
//
// Coverage:
//   * Static literal route hit
//   * Method dispatch (GET vs POST same pattern)
//   * Named param `/users/:id`
//   * Multiple named params `/repos/:owner/:repo`
//   * Tail wildcard `/static/*path` capturing slashes
//   * Strict trailing-slash mismatch (no auto-redirect)
//   * 404 fallback on no match
//   * 404 fallback on method mismatch (cannot distinguish 404 vs 405 in v1)
//   * `router_any` accepts any method via "*"
//   * params_get hit + miss
//   * Middleware composition: with_log_requests + with_cors_default
//     (logs go to stderr — captured separately by the test runner;
//     stdout shows only the response status/body so the snapshot is
//     deterministic.)

$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_int s prefix i n → v {
    ( nurl_print prefix )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

// Build a synthetic request. Handlers reach into String fields via
// `string_data`, so we just push raw bytes into the empty allocations
// `request_new` set up for us.
@ make_req s method s path → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ^ req
}

// Read the response body Vec[u] as a freshly-owned String (zero-copy
// would alias the response body buffer, which is freed below — the
// owned copy lets us print AFTER http_response_free).
@ body_to_string HttpResponse r → String {
    : i n ( vec_len [u] . r body )
    : *u data ( vec_data [u] . r body )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : u byte . data k
        ( string_push_char out # i byte )
        = k + k 1
    }
    ^ out
}

@ run_dispatch Router router s label s method s path → v {
    ( nurl_print `── ` ) ( nurl_print label ) ( nurl_print ` ──\n` )
    : HttpRequest req ( make_req method path )
    : HttpResponse resp ( router_handle router req )
    ( println_int `  status=` . resp status )
    : String body ( body_to_string resp )
    ( println_str `  body=` ( string_data body ) )
    ( string_free body )
    ( http_response_free resp )
    ( request_free req )
}

// Stock handlers. Each pulls something out of req or params and bakes
// it into a 200 text response. They live as top-level @-functions so
// we can hand thin closure wrappers to the router (bare @-functions
// don't auto-coerce to closure-typed parameters, so we wrap them).

@ h_root HttpRequest req Params params → HttpResponse {
    ^ ( response_text 200 `root\n` )
}

@ h_about HttpRequest req Params params → HttpResponse {
    ^ ( response_text 200 `about us\n` )
}

@ h_create_user HttpRequest req Params params → HttpResponse {
    ^ ( response_text 201 `user created\n` )
}

@ h_user_show HttpRequest req Params params → HttpResponse {
    : ?String got ( params_get params `id` )
    ?? got {
        T id → {
            : String body ( string_with_cap 64 )
            ( string_push_str body `user id=` )
            ( string_push_str body ( string_data id ) )
            ( string_push_char body 10 )
            : HttpResponse r ( response_text 200 ( string_data body ) )
            ( string_free body )
            ( string_free id )
            ^ r
        }
        F empty → {
            ( string_free empty )
            ^ ( response_text 500 `missing id capture\n` )
        }
    }
}

@ h_repo_show HttpRequest req Params params → HttpResponse {
    : ?String go ( params_get params `owner` )
    : ?String gr ( params_get params `repo` )
    ?? go {
        T owner → {
            ?? gr {
                T repo → {
                    : String body ( string_with_cap 64 )
                    ( string_push_str body `repo=` )
                    ( string_push_str body ( string_data owner ) )
                    ( string_push_char body 47 )
                    ( string_push_str body ( string_data repo ) )
                    ( string_push_char body 10 )
                    : HttpResponse r ( response_text 200 ( string_data body ) )
                    ( string_free body )
                    ( string_free owner )
                    ( string_free repo )
                    ^ r
                }
                F er → {
                    ( string_free owner )
                    ( string_free er )
                    ^ ( response_text 500 `missing repo capture\n` )
                }
            }
        }
        F eo → {
            ( string_free eo )
            ?? gr {
                T r → ( string_free r )
                F er → ( string_free er )
            }
            ^ ( response_text 500 `missing owner capture\n` )
        }
    }
}

@ h_static HttpRequest req Params params → HttpResponse {
    : ?String got ( params_get params `path` )
    ?? got {
        T p → {
            : String body ( string_with_cap 64 )
            ( string_push_str body `static path=` )
            ( string_push_str body ( string_data p ) )
            ( string_push_char body 10 )
            : HttpResponse r ( response_text 200 ( string_data body ) )
            ( string_free body )
            ( string_free p )
            ^ r
        }
        F empty → {
            ( string_free empty )
            ^ ( response_text 500 `missing path capture\n` )
        }
    }
}

@ h_health HttpRequest req Params params → HttpResponse {
    : String body ( string_with_cap 32 )
    ( string_push_str body `method=` )
    ( string_push_str body ( string_data . req method ) )
    ( string_push_char body 10 )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( string_free body )
    ^ r
}

// ── params_get direct unit ───────────────────────────────────────────

@ run_params_unit → v {
    ( nurl_print `── params_get ──\n` )
    : Params p ( params_new )
    // Hand-build entries so the test isn't entangled with the matcher.
    : QueryPair a @ QueryPair { ( string_from `name` ) ( string_from `alice` ) }
    : QueryPair b @ QueryPair { ( string_from `age` ) ( string_from `30` ) }
    ( vec_push [QueryPair] . p entries a )
    ( vec_push [QueryPair] . p entries b )
    ( println_int `  count=` ( params_count p ) )

    : ?String hit ( params_get p `name` )
    ?? hit {
        T s → { ( println_str `  name=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  name=` `<absent>` ) ( string_free e ) }
    }

    : ?String miss ( params_get p `missing` )
    ?? miss {
        T s → { ( println_str `  missing=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  missing=` `<absent>` ) ( string_free e ) }
    }

    ( params_free p )
}

// ── Middleware composition ───────────────────────────────────────────

@ run_middleware → v {
    ( nurl_print `── middleware (log + cors) ──\n` )
    // A tiny single-route router for the middleware test.
    : Router r ( router_new )
    ( router_get r `/ping` \ HttpRequest req Params params → HttpResponse { ^ ( response_text 200 `pong\n` ) } )

    // Build the base handler: dispatch through the router.
    : ( @ HttpResponse HttpRequest ) base
    \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }

    // Compose: log on the OUTSIDE, CORS in the middle, dispatch inside.
    : ( @ HttpResponse HttpRequest ) cors ( with_cors_default base )
    : ( @ HttpResponse HttpRequest ) wrapped ( with_log_requests cors )

    // GET /ping — should run the route + add CORS headers.
    : HttpRequest req1 ( make_req `GET` `/ping` )
    : HttpResponse resp1 ( wrapped req1 )
    ( println_int `  GET /ping status=` . resp1 status )
    : String body1 ( body_to_string resp1 )
    ( println_str `  GET /ping body=` ( string_data body1 ) )
    : ?String acao ( header_get . resp1 headers `Access-Control-Allow-Origin` )
    ?? acao {
        T s → { ( println_str `  CORS=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  CORS=` `<absent>` ) ( string_free e ) }
    }
    ( string_free body1 )
    ( http_response_free resp1 )
    ( request_free req1 )

    // OPTIONS /ping — should short-circuit to 204 in the CORS layer.
    : HttpRequest req2 ( make_req `OPTIONS` `/ping` )
    : HttpResponse resp2 ( wrapped req2 )
    ( println_int `  OPTIONS /ping status=` . resp2 status )
    : ?String acam ( header_get . resp2 headers `Access-Control-Allow-Methods` )
    ?? acam {
        T s → { ( println_str `  Allow-Methods=` ( string_data s ) ) ( string_free s ) }
        F e → { ( println_str `  Allow-Methods=` `<absent>` ) ( string_free e ) }
    }
    ( http_response_free resp2 )
    ( request_free req2 )

    ( router_free r )
}

@ main → i {
    // Build the test router. Closure literals wrap each top-level handler
    // so it conforms to the closure-typed parameter.
    : Router r ( router_new )

    ( router_get r `/`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_root req params ) } )

    ( router_get r `/about`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_about req params ) } )

    ( router_post r `/users`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_create_user req params ) } )

    ( router_get r `/users/:id`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_user_show req params ) } )

    ( router_get r `/repos/:owner/:repo`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_repo_show req params ) } )

    ( router_get r `/static/*path`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_static req params ) } )

    ( router_any r `*` `/health`
    \ HttpRequest req Params params → HttpResponse { ^ ( h_health req params ) } )

    ( println_int `route_count=` ( router_count r ) )

    // Dispatch a battery of cases. Each one prints status + body so the
    // snapshot tightly verifies routing behaviour.
    ( run_dispatch r `static_root` `GET` `/` )
    ( run_dispatch r `static_about` `GET` `/about` )
    ( run_dispatch r `method_post_users` `POST` `/users` )
    ( run_dispatch r `param_user` `GET` `/users/42` )
    ( run_dispatch r `param_user_alpha` `GET` `/users/alice` )
    ( run_dispatch r `param_two` `GET` `/repos/octocat/hello-world` )
    ( run_dispatch r `wildcard_one` `GET` `/static/css/main.css` )
    ( run_dispatch r `wildcard_deep` `GET` `/static/a/b/c/d.png` )
    ( run_dispatch r `any_method_get` `GET` `/health` )
    ( run_dispatch r `any_method_delete` `DELETE` `/health` )

    // Negative cases.
    ( run_dispatch r `not_found` `GET` `/nope` )
    ( run_dispatch r `method_mismatch` `DELETE` `/users` )
    ( run_dispatch r `trailing_slash` `GET` `/about/` )
    ( run_dispatch r `param_empty_seg` `GET` `/users/` )

    ( router_free r )

    ( run_params_unit )
    ( run_middleware )

    ^ 0
}
