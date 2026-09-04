// oauth/flow.nu — the authorization-code flow, end to end.
//
// Three requests and one redirect:
//
//   1. ( oauth_authorize_url p cfg state nonce pk )
//        → send the user's browser here. The URL carries the PKCE
//          challenge, the state and the nonce; the secrets behind them
//          stay on this side.
//   2. the provider redirects back to the client's redirect_uri with
//      `?code=…&state=…` — ( oauth_callback_code query state ) checks
//      the state and hands back the code (or names the provider's own
//      error, which arrives the same way).
//   3. ( oauth_exchange_code p cfg code verifier )
//        → POST to the token endpoint: the code plus the PKCE verifier,
//          answered with the access token and — this is the point — the
//          ID TOKEN, a signed JWT stating who just logged in.
//
// Then ( oidc_verify_id_token p pol ( token_set_id_token ts ) ) turns
// that into an OidcIdentity. `oauth_userinfo` fetches the same profile
// from the UserInfo endpoint when the ID token is deliberately thin.
//
// Also here: `oauth_refresh` (a new access token without the user) and
// `oauth_client_credentials` (a machine identity — no user at all).
//
// Client authentication is `client_secret_post` by default and
// `client_secret_basic` on request (RFC 6749 §2.3.1); a public client
// simply sets no secret and relies on PKCE, which is the OAuth 2.1
// shape for anything running on the user's machine.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/json.nu`
$ `deps/http-client/src/http_client.nu`
$ `errors.nu`
$ `claims.nu`
$ `pkce.nu`
$ `provider.nu`

// ── Client configuration ───────────────────────────────────────────

: OauthConfig {
    String client_id
    String client_secret  // empty = a public client (PKCE only)
    String redirect_uri
    String scope  // space-separated; "openid" is what makes it OIDC
    String audience  // a resource indicator, when the provider wants one
    String prompt  // "none" · "login" · "consent" — empty to omit
    b basic_auth  // client_secret_basic instead of client_secret_post
}

@ oauth_config_new s client_id s redirect_uri s scope → *OauthConfig {
    : *OauthConfig c # *OauthConfig ( nurl_malloc Z OauthConfig )
    = . c client_id ( string_from client_id )
    = . c client_secret ( string_new )
    = . c redirect_uri ( string_from redirect_uri )
    = . c scope ( string_from scope )
    = . c audience ( string_new )
    = . c prompt ( string_new )
    = . c basic_auth F
    ^ c
}

@ oauth_config_free * OauthConfig c → v {
    ( string_free . c client_id )
    ( string_free . c client_secret )
    ( string_free . c redirect_uri )
    ( string_free . c scope )
    ( string_free . c audience )
    ( string_free . c prompt )
    ( nurl_free # s c )
}

@ oauth_config_set_secret * OauthConfig c s secret → v {
    ( string_free . c client_secret )
    = . c client_secret ( string_from secret )
}

@ oauth_config_set_audience * OauthConfig c s audience → v {
    ( string_free . c audience )
    = . c audience ( string_from audience )
}

@ oauth_config_set_prompt * OauthConfig c s prompt → v {
    ( string_free . c prompt )
    = . c prompt ( string_from prompt )
}

@ oauth_config_set_basic_auth * OauthConfig c b on → v { = . c basic_auth on }

// ── Form / query encoding ──────────────────────────────────────────

// Append `key=value`, percent-encoded, with a separating '&' when the
// buffer already holds a pair. An empty value is omitted entirely — an
// OAuth request must not carry `scope=` with nothing after it.
@ __oaf_kv String q s key s value → v {
    ? > ( nurl_str_len value ) 0 {
        ? > ( string_len q ) 0 { ( string_push_char q 38 ) } {}
        : String ek ( url_percent_encode key )
        : String ev ( url_percent_encode value )
        ( string_push_str q ( string_data ek ) )
        ( string_push_char q 61 )  // '='
        ( string_push_str q ( string_data ev ) )
        ( string_free ek )
        ( string_free ev )
    } {}
}

// ── Authorization request ──────────────────────────────────────────

// The URL to send the user's browser to. `state` and `nonce` are the
// values the caller minted (pkce.nu) and must remember: state is
// compared on the way back, nonce is compared inside the ID token.
@ oauth_authorize_url * OidcProvider p * OauthConfig cfg s state s nonce Pkce pk → String {
    : String q ( string_with_cap 512 )
    ( __oaf_kv q `response_type` `code` )
    ( __oaf_kv q `client_id` ( string_data . cfg client_id ) )
    ( __oaf_kv q `redirect_uri` ( string_data . cfg redirect_uri ) )
    ( __oaf_kv q `scope` ( string_data . cfg scope ) )
    ( __oaf_kv q `state` state )
    ( __oaf_kv q `nonce` nonce )
    ( __oaf_kv q `code_challenge` ( string_data . pk challenge ) )
    ( __oaf_kv q `code_challenge_method` ( string_data . pk method ) )
    ( __oaf_kv q `audience` ( string_data . cfg audience ) )
    ( __oaf_kv q `prompt` ( string_data . cfg prompt ) )
    : String out ( string_from ( string_data . p authorization_endpoint ) )
    // The endpoint may already carry a query of its own (RFC 6749 §3.1).
    ? ( string_contains out `?` ) {
        ( string_push_char out 38 )
    } {
        ( string_push_char out 63 )  // '?'
    }
    ( string_push_str out ( string_data q ) )
    ( string_free q )
    ^ out
}

// ── The redirect back ──────────────────────────────────────────────

: CallbackParams {
    String code
    String state
    String error
    String error_description
}

@ callback_params_free CallbackParams cb → v {
    ( string_free . cb code )
    ( string_free . cb state )
    ( string_free . cb error )
    ( string_free . cb error_description )
}

@ __oaf_param ( Vec UrlParam ) ps s key → String {
    : i n ( vec_len [UrlParam] ps )
    : *UrlParam data ( vec_data [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        : UrlParam pp . data k
        ? == 1 ( nurl_str_eq ( string_data . pp key ) key ) {
            ^ ( string_from ( string_data . pp val ) )
        } {}
        = k + k 1
    }
    ^ ( string_new )
}

// Parse the query string of the redirect the provider sent the browser.
@ oauth_callback_parse s query → CallbackParams {
    : ( Vec UrlParam ) ps ( url_query_decode query )
    : CallbackParams cb @ CallbackParams {
        ( __oaf_param ps `code` )
        ( __oaf_param ps `state` )
        ( __oaf_param ps `error` )
        ( __oaf_param ps `error_description` )
    }
    ( url_params_free ps )
    ^ cb
}

// The authorization code, once the callback is proven to be the answer
// to the request WE started. A `state` that does not match is not a
// recoverable condition — it is someone else's login being fed to us.
@ oauth_callback_code s query s expected_state → !String OauthErr {
    : CallbackParams cb ( oauth_callback_parse query )
    // The provider said no (`error=access_denied`, …). Read the detail
    // from `oauth_callback_parse` when you want to show it.
    ? > ( string_len . cb error ) 0 {
        ( callback_params_free cb )
        ^ @ !String OauthErr { F OaServer }
    } {}
    ? > ( nurl_str_len expected_state ) 0 {
        ? == 1 ( nurl_str_eq ( string_data . cb state ) expected_state ) {} {
            ( callback_params_free cb )
            ^ @ !String OauthErr { F OaState }
        }
    } {}
    ? == 0 ( string_len . cb code ) {
        ( callback_params_free cb )
        ^ @ !String OauthErr { F OaBadResponse }
    } {}
    : String code ( string_from ( string_data . cb code ) )
    ( callback_params_free cb )
    ^ @ !String OauthErr { T code }
}

// ── Tokens ─────────────────────────────────────────────────────────

: TokenSet {
    String access_token
    String id_token  // the signed statement of WHO — empty for a
    // non-OIDC grant (client_credentials, plain OAuth)
    String refresh_token
    String token_type  // "Bearer"
    String scope  // what the provider actually granted
    i expires_in  // seconds, −1 when the provider said nothing
    i obtained_at  // our clock when the response arrived
}

@ token_set_free TokenSet t → v {
    ( string_free . t access_token )
    ( string_free . t id_token )
    ( string_free . t refresh_token )
    ( string_free . t token_type )
    ( string_free . t scope )
}

@ token_set_access_token TokenSet t → s { ^ ( string_data . t access_token ) }

@ token_set_id_token TokenSet t → s { ^ ( string_data . t id_token ) }

@ token_set_refresh_token TokenSet t → s { ^ ( string_data . t refresh_token ) }

@ token_set_token_type TokenSet t → s { ^ ( string_data . t token_type ) }

@ token_set_scope TokenSet t → s { ^ ( string_data . t scope ) }

// When the access token stops being usable; −1 when unknown.
@ token_set_expires_at TokenSet t → i {
    ? < . t expires_in 0 { ^ -1 } {}
    ^ + . t obtained_at . t expires_in
}

// Refresh a minute early — a token that expires in flight is a 401 the
// caller has to retry, and the clocks are not the same clock.
@ token_set_stale TokenSet t i now → b {
    : i at ( token_set_expires_at t )
    ? < at 0 { ^ F } {}
    ^ >= + now 60 at
}

@ __oaf_token_set_from_json Json j → TokenSet {
    ^ @ TokenSet {
        ( claims_str j `access_token` )
        ( claims_str j `id_token` )
        ( claims_str j `refresh_token` )
        ( claims_str j `token_type` )
        ( claims_str j `scope` )
        ( claims_int_or j `expires_in` -1 )
        ( now_seconds )
    }
}

// ── The token endpoint ─────────────────────────────────────────────

// Add whichever client authentication the config asks for: the secret in
// the body, or an Authorization header the caller then sends.
@ __oaf_auth_header * OauthConfig cfg → String {
    : String out ( string_new )
    ? & . cfg basic_auth > ( string_len . cfg client_secret ) 0 {
        : String ek ( url_percent_encode ( string_data . cfg client_id ) )
        : String es ( url_percent_encode ( string_data . cfg client_secret ) )
        : String pair ( string_with_cap 128 )
        ( string_push_str pair ( string_data ek ) )
        ( string_push_char pair 58 )  // ':'
        ( string_push_str pair ( string_data es ) )
        : String enc ( b64_encode ( string_data pair ) )
        ( string_push_str out `Basic ` )
        ( string_push_str out ( string_data enc ) )
        ( string_free ek ) ( string_free es )
        ( string_free pair ) ( string_free enc )
    } {}
    ^ out
}

// POST a form to the token endpoint and read the token response.
@ __oaf_token_request * OidcProvider p * OauthConfig cfg String form → !TokenSet OauthErr {
    ? == 0 ( string_len . p token_endpoint ) {
        ( _oidc_err p `no token_endpoint — run discovery or set one` )
        ^ @ !TokenSet OauthErr { F OaConfig }
    } {}
    : String auth ( __oaf_auth_header cfg )
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `content-type` `application/x-www-form-urlencoded` ) )
    ( vec_push [Header] hs ( header_new `accept` `application/json` ) )
    ? > ( string_len auth ) 0 {
        ( vec_push [Header] hs ( header_new `authorization` ( string_data auth ) ) )
    } {}
    ( string_free auth )
    : ( Vec u ) body ( bytes_from_str ( string_data form ) )
    : !HttpResponse HttpClientErr rr ( http_client_request . p http `POST` ( string_data . p token_endpoint ) hs body )
    ( vec_free [u] body )
    ?? rr {
        T r → {
            : i status ( http_client_status r )
            : !Json JsonError pj ( json_parse_bytes . r body )
            ( http_response_free r )
            ?? pj {
                T j → {
                    // An OAuth error response is JSON too (RFC 6749 §5.2),
                    // and it is the only place the reason is stated.
                    : String oerr ( claims_str j `error` )
                    ? > ( string_len oerr ) 0 {
                        : String desc ( claims_str j `error_description` )
                        : String msg ( string_with_cap 128 )
                        ( string_push_str msg `token endpoint: ` )
                        ( string_push_str msg ( string_data oerr ) )
                        ? > ( string_len desc ) 0 {
                            ( string_push_str msg ` — ` )
                            ( string_push_str msg ( string_data desc ) )
                        } {}
                        ( _oidc_err p ( string_data msg ) )
                        ( string_free msg ) ( string_free desc ) ( string_free oerr )
                        ( json_free j )
                        ^ @ !TokenSet OauthErr { F OaServer }
                    } {}
                    ( string_free oerr )
                    ? & >= status 200 < status 300 {} {
                        ( _oidc_err_status p `token endpoint` status )
                        ( json_free j )
                        ^ @ !TokenSet OauthErr { F OaHttpStatus }
                    }
                    : TokenSet ts ( __oaf_token_set_from_json j )
                    ( json_free j )
                    ? == 0 ( string_len . ts access_token ) {
                        ( token_set_free ts )
                        ( _oidc_err p `token response carries no access_token` )
                        ^ @ !TokenSet OauthErr { F OaBadResponse }
                    } {}
                    ^ @ !TokenSet OauthErr { T ts }
                }
                F _ → {
                    ( _oidc_err_status p `token endpoint (non-JSON)` status )
                    ^ @ !TokenSet OauthErr { F OaBadResponse }
                }
            }
        }
        F e → {
            ( _oidc_err2 p `token endpoint: ` ( http_client_err_name e ) )
            ^ @ !TokenSet OauthErr { F OaNetwork }
        }
    }
}

// Exchange the authorization code for tokens. `verifier` is the PKCE
// secret whose challenge went out with the authorization request.
@ oauth_exchange_code * OidcProvider p * OauthConfig cfg s code s verifier → !TokenSet OauthErr {
    : String form ( string_with_cap 512 )
    ( __oaf_kv form `grant_type` `authorization_code` )
    ( __oaf_kv form `code` code )
    ( __oaf_kv form `redirect_uri` ( string_data . cfg redirect_uri ) )
    ( __oaf_kv form `client_id` ( string_data . cfg client_id ) )
    ( __oaf_kv form `code_verifier` verifier )
    ? . cfg basic_auth {} {
        ( __oaf_kv form `client_secret` ( string_data . cfg client_secret ) )
    }
    : !TokenSet OauthErr r ( __oaf_token_request p cfg form )
    ( string_free form )
    ^ r
}

// A new access token from a refresh token — no user interaction.
@ oauth_refresh * OidcProvider p * OauthConfig cfg s refresh_token → !TokenSet OauthErr {
    : String form ( string_with_cap 512 )
    ( __oaf_kv form `grant_type` `refresh_token` )
    ( __oaf_kv form `refresh_token` refresh_token )
    ( __oaf_kv form `client_id` ( string_data . cfg client_id ) )
    ( __oaf_kv form `scope` ( string_data . cfg scope ) )
    ? . cfg basic_auth {} {
        ( __oaf_kv form `client_secret` ( string_data . cfg client_secret ) )
    }
    : !TokenSet OauthErr r ( __oaf_token_request p cfg form )
    ( string_free form )
    ^ r
}

// The machine grant: this service authenticating as itself, with no user
// behind it (RFC 6749 §4.4).
@ oauth_client_credentials * OidcProvider p * OauthConfig cfg → !TokenSet OauthErr {
    : String form ( string_with_cap 512 )
    ( __oaf_kv form `grant_type` `client_credentials` )
    ( __oaf_kv form `client_id` ( string_data . cfg client_id ) )
    ( __oaf_kv form `scope` ( string_data . cfg scope ) )
    ( __oaf_kv form `audience` ( string_data . cfg audience ) )
    ? . cfg basic_auth {} {
        ( __oaf_kv form `client_secret` ( string_data . cfg client_secret ) )
    }
    : !TokenSet OauthErr r ( __oaf_token_request p cfg form )
    ( string_free form )
    ^ r
}

// ── UserInfo ───────────────────────────────────────────────────────

// The profile as the provider will state it right now, fetched with the
// access token (OIDC core §5.3). Returns the owned claims object.
@ oauth_userinfo * OidcProvider p s access_token → !Json OauthErr {
    ? == 0 ( string_len . p userinfo_endpoint ) {
        ( _oidc_err p `no userinfo_endpoint — run discovery or set one` )
        ^ @ !Json OauthErr { F OaConfig }
    } {}
    : String auth ( string_with_cap 64 )
    ( string_push_str auth `Bearer ` )
    ( string_push_str auth access_token )
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `authorization` ( string_data auth ) ) )
    ( vec_push [Header] hs ( header_new `accept` `application/json` ) )
    ( string_free auth )
    : ( Vec u ) body ( vec_new [u] )
    : !HttpResponse HttpClientErr rr ( http_client_request . p http `GET` ( string_data . p userinfo_endpoint ) hs body )
    ( vec_free [u] body )
    ?? rr {
        T r → {
            : i status ( http_client_status r )
            ? & >= status 200 < status 300 {} {
                ( _oidc_err_status p `userinfo` status )
                ( http_response_free r )
                ^ @ !Json OauthErr { F OaHttpStatus }
            }
            : !Json JsonError pj ( json_parse_bytes . r body )
            ( http_response_free r )
            ?? pj {
                T j → { ^ @ !Json OauthErr { T j } }
                F _ → {
                    ( _oidc_err p `userinfo did not return JSON` )
                    ^ @ !Json OauthErr { F OaBadResponse }
                }
            }
        }
        F e → {
            ( _oidc_err2 p `userinfo: ` ( http_client_err_name e ) )
            ^ @ !Json OauthErr { F OaNetwork }
        }
    }
}

// The identity behind an access token, taken from UserInfo rather than
// from a signed token — for a provider whose access tokens are opaque.
// The `sub` MUST match the ID token's when both are in play (OIDC core
// §5.3.2); with no ID token in hand, pass "" to skip that.
@ oauth_userinfo_identity * OidcProvider p s access_token s expect_sub → !OidcIdentity OauthErr {
    ?? ( oauth_userinfo p access_token ) {
        T j → {
            ? > ( nurl_str_len expect_sub ) 0 {
                : String sub ( claims_str j `sub` )
                : b same == 1 ( nurl_str_eq ( string_data sub ) expect_sub )
                ( string_free sub )
                ? same {} {
                    ( _oidc_err p `userinfo sub does not match the ID token` )
                    ( json_free j )
                    ^ @ !OidcIdentity OauthErr { F OaClaims }
                }
            } {}
            ^ @ !OidcIdentity OauthErr { T ( oidc_identity_from_claims j ) }
        }
        F e → { ^ @ !OidcIdentity OauthErr { F # OauthErr e } }
    }
}
