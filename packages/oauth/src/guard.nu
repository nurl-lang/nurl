// oauth/guard.nu — the resource-server side: a route that knows who
// called it.
//
// The client half of this package gets tokens; this half spends them.
// Wrap a handler and it only ever runs for a request that carried a
// valid `Authorization: Bearer <JWT>`, with the caller's verified
// identity handed straight in:
//
//   ( http_app_get a `/me`
//       ( with_oidc_bearer p pol
//           \ HttpRequest req OidcIdentity id → HttpResponse {
//               ^ ( response_text 200 ( string_data ( oidc_identity_describe id ) ) )
//           } ) )
//
// Everything a bearer token can be wrong about — no token, a token from
// another issuer, for another audience, expired, signed with a key the
// provider never published, signed with `alg: none` — becomes a 401 with
// the RFC 6750 §3 challenge naming the reason. A token that is valid but
// does not carry the scope the route needs is a 403 `insufficient_scope`
// (`with_oidc_scope`), because that is a different answer: re-
// authenticating will not help, asking for more scope will.
//
// `id` is BORROWED by the handler — the middleware frees it (and the
// claims behind it) once the handler returns.
//
// The wrapper closure lives as long as the app that routes to it, the
// same as with_jwt_* / with_cors_default: build it once at startup.

$ `stdlib/core/string.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_auth.nu`
$ `errors.nu`
$ `claims.nu`
$ `provider.nu`

// Append `value` as the inside of an RFC 7235 quoted-string, keeping only
// bytes that are legal there and capping the length.
//
// This is load-bearing, not hygiene: the description we render comes from
// `oidc_provider_last_error`, and some of what lands there is quoted from
// the TOKEN — an attacker-supplied `kid`, a provider's error_description.
// A CR or LF echoed into a response header is response splitting; a `"`
// ends the parameter early. Neither reaches the wire.
@ _oidc_safe_param String out s value → v {
    : i n ( nurl_str_len value )
    : i cap ? > n 200 200 n
    : ~ i k 0
    ~ < k cap {
        : i c ( nurl_str_get value k )
        ? | < c 32 == c 127 {
            ( string_push_char out 32 )
        } {
            ? | == c 34 == c 92 {
                ( string_push_char out 32 )
            } {
                ( string_push_char out c )
            }
        }
        = k + k 1
    }
    ? > n cap { ( string_push_str out `...` ) } {}
}

// 401 with a Bearer challenge. `code` is the RFC 6750 error token, empty
// for a missing credential (§3.1: no error code when none was offered).
@ _oidc_unauthorized s code s desc → HttpResponse {
    : HttpResponse r ( response_text 401 `Unauthorized\n` )
    : String chal ( string_with_cap 96 )
    ( string_push_str chal `Bearer` )
    ? > ( nurl_str_len code ) 0 {
        ( string_push_str chal ` error="` )
        ( _oidc_safe_param chal code )
        ( string_push_char chal 34 )
        ? > ( nurl_str_len desc ) 0 {
            ( string_push_str chal `, error_description="` )
            ( _oidc_safe_param chal desc )
            ( string_push_char chal 34 )
        } {}
    } {}
    ( response_set_header r `WWW-Authenticate` ( string_data chal ) )
    ( string_free chal )
    ^ r
}

// 403: the caller is who they say, and still may not do this.
@ _oidc_forbidden s scope → HttpResponse {
    : HttpResponse r ( response_text 403 `Forbidden\n` )
    : String chal ( string_with_cap 96 )
    ( string_push_str chal `Bearer error="insufficient_scope"` )
    ? > ( nurl_str_len scope ) 0 {
        ( string_push_str chal `, scope="` )
        ( _oidc_safe_param chal scope )
        ( string_push_char chal 34 )
    } {}
    ( response_set_header r `WWW-Authenticate` ( string_data chal ) )
    ( string_free chal )
    ^ r
}

// Verify the request's bearer token directly — for a handler that wants
// the identity without being wrapped, or for a protocol other than HTTP
// routing (a WebSocket upgrade, an MCP session).
@ oidc_request_identity * OidcProvider p * OidcPolicy pol HttpRequest req → !OidcIdentity OauthErr {
    ?? ( parse_bearer_auth req ) {
        T t → {
            : !OidcIdentity OauthErr r ( oidc_verify_token p pol ( string_data t ) )
            ( string_free t )
            ^ r
        }
        F _ → {
            ( _oidc_err p `no bearer token` )
            ^ @ !OidcIdentity OauthErr { F OaBadToken }
        }
    }
}

// Only run `inner` for an authenticated caller.
@ with_oidc_bearer * OidcProvider p * OidcPolicy pol ( @ HttpResponse HttpRequest OidcIdentity ) inner → ( @ HttpResponse HttpRequest ) {
    : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
        ?? ( parse_bearer_auth req ) {
            T t → {
                : !OidcIdentity OauthErr vr ( oidc_verify_token p pol ( string_data t ) )
                ( string_free t )
                ^ ?? vr {
                    T id → {
                        : HttpResponse resp ( inner req id )
                        ( oidc_identity_free id )
                        ^ resp
                    }
                    F e → ( _oidc_unauthorized ( oauth_err_bearer_code # OauthErr e ) ( oidc_provider_last_error p ) )
                }
            }
            F _ → { ^ ( _oidc_unauthorized `` `` ) }
        }
    }
    ^ wrapped
}

// Authenticated AND carrying `scope`.
@ with_oidc_scope * OidcProvider p * OidcPolicy pol s scope ( @ HttpResponse HttpRequest OidcIdentity ) inner → ( @ HttpResponse HttpRequest ) {
    : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
        ?? ( parse_bearer_auth req ) {
            T t → {
                : !OidcIdentity OauthErr vr ( oidc_verify_token p pol ( string_data t ) )
                ( string_free t )
                ^ ?? vr {
                    T id → {
                        ? ( oidc_identity_has_scope id scope ) {
                            : HttpResponse resp ( inner req id )
                            ( oidc_identity_free id )
                            ^ resp
                        } {
                            ( oidc_identity_free id )
                            ^ ( _oidc_forbidden scope )
                        }
                    }
                    F e → ( _oidc_unauthorized ( oauth_err_bearer_code # OauthErr e ) ( oidc_provider_last_error p ) )
                }
            }
            F _ → { ^ ( _oidc_unauthorized `` `` ) }
        }
    }
    ^ wrapped
}
