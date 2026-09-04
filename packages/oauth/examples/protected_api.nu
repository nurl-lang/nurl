// examples/protected_api.nu — an HTTP API that knows who is calling.
//
// The resource-server side: every request must carry an access token
// this issuer signed, for this audience, unexpired — and the handler is
// only ever entered with the caller's verified identity in hand.
//
//   protected-api --issuer https://accounts.example.com \
//                 --audience <api-audience> \
//                 [--scope read:things] [--port 8080]
//
//   GET /me      → the identity as JSON
//   GET /whoami  → "sub@issuer" as text
//
// With --scope the whole surface is wrapped in `with_oidc_scope`, which
// answers 403 `insufficient_scope` for a caller who authenticates but
// was not granted it; without it, `with_oidc_bearer` requires only a
// valid token. Both answer 401 with an RFC 6750 challenge naming the
// reason when the token is missing, expired, forged or for someone else.
//
// Try it against the package's own test provider:
//
//   ./tests/provider --port 9000 &
//   ./protected-api --issuer http://127.0.0.1:9000 --audience test-api \
//                   --scope read:things --port 8080
//   curl -H "Authorization: Bearer $(curl -s 127.0.0.1:9000/mint/access)" \
//        127.0.0.1:8080/me

$ `stdlib/std/args.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/json.nu`
$ `../src/oauth.nu`

// The whole API, entered only for a caller we can name.
@ api_handle HttpRequest req OidcIdentity id → HttpResponse {
    : s path ( string_data . req path )
    ? == 1 ( nurl_str_eq path `/whoami` ) {
        : String key ( oidc_identity_key id )
        : HttpResponse r ( response_text 200 ( string_data key ) )
        ( string_free key )
        ^ r
    } {}
    ? == 1 ( nurl_str_eq path `/me` ) {
        : Json out ( json_obj_new )
        ( json_obj_set out `subject` ( json_str_lit ( string_data . id subject ) ) )
        ( json_obj_set out `issuer` ( json_str_lit ( string_data . id issuer ) ) )
        ( json_obj_set out `email` ( json_str_lit ( string_data . id email ) ) )
        ( json_obj_set out `name` ( json_str_lit ( string_data . id name ) ) )
        ( json_obj_set out `expires_at` ( json_int . id expires_at ) )
        : HttpResponse r ( response_json 200 out )
        ( json_free out )
        ^ r
    } {}
    ^ ( response_text 404 `not found\n` )
}

@ main → i {
    : ArgParser ap ( args_new `protected-api` `an HTTP API behind OpenID Connect` )
    ( args_opt ap `issuer` 105 `URL` `the issuer whose tokens this API accepts` )
    ( args_opt ap `audience` 97 `AUD` `this API's audience, required in aud` )
    ( args_opt ap `scope` 111 `SCOPE` `require this scope on every request` )
    ( args_opt ap `port` 112 `N` `bind port on 127.0.0.1 (default 8080)` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }
    : String issuer ( args_value_or ap `issuer` `` )
    : String audience ( args_value_or ap `audience` `` )
    : String scope ( args_value_or ap `scope` `` )
    : String port_s ( args_value_or ap `port` `8080` )
    ( args_free ap )
    : ~ i port 8080
    ?? ( string_to_int port_s ) { T x → { = port x } F _ → {} }
    ( string_free port_s )

    ? == 0 ( string_len issuer ) {
        ( nurl_eprintln `protected-api: --issuer is required` )
        ^ 2
    } {}

    : ~ i rc 1
    // Discovery happens once, at startup: a resource server that cannot
    // reach its issuer's metadata cannot authenticate anyone, and should
    // say so now rather than 500 on the first request.
    ?? ( oidc_provider_discover ( string_data issuer ) ) {
        F e → { ( nurl_eprintln ( oauth_err_name e ) ) }
        T p → {
            : *OidcPolicy pol ( oidc_policy_new ( string_data issuer ) ( string_data audience ) )
            ?? ( tcp_listen `127.0.0.1` port ) {
                F _ → { ( nurl_eprintln `protected-api: cannot bind` ) }
                T l → {
                    ? > ( string_len scope ) 0 {
                        : HttpServer srv ( server_new l ( with_oidc_scope p pol ( string_data scope )
                        \ HttpRequest req OidcIdentity id → HttpResponse { ^ ( api_handle req id ) } ) )
                        ?? ( server_run srv ) { T _ → { = rc 0 } F _ → {} }
                    } {
                        : HttpServer srv ( server_new l ( with_oidc_bearer p pol
                        \ HttpRequest req OidcIdentity id → HttpResponse { ^ ( api_handle req id ) } ) )
                        ?? ( server_run srv ) { T _ → { = rc 0 } F _ → {} }
                    }
                }
            }
            ( oidc_policy_free pol )
            ( oidc_provider_free p )
        }
    }
    ( string_free issuer ) ( string_free audience ) ( string_free scope )
    ^ rc
}
