// tests/provider.nu — a real (if minimal) OpenID Connect provider, so the
// package is tested against the protocol rather than against a mock of
// itself. It discovers, publishes a JWKS, mints ES256-signed ID tokens
// with a `kid`, and CHECKS PKCE on the token request.
//
// It is stateless by design: the authorization code carries what a real
// provider would have stored server-side —
//
//     code = "c." <code_challenge> "." <nonce>
//
// — so /token can verify that S256(code_verifier) is the challenge the
// authorization request committed to, and can put the right nonce in the
// ID token, without a session store. Everything on the wire is the
// standard shape; only the code's INTERNAL format is a shortcut.
//
// /mint/<kind> hands out deliberately broken tokens for the negative
// tests: expired, badsig, none (alg: none), unknownkid, wrongaud, hs256.
//
//   provider --port N

$ `stdlib/std/args.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

: ~ i g_port 0

@ prov_kid → s { ^ `k1` }

@ prov_client_id → s { ^ `test-client` }

@ prov_api_audience → s { ^ `test-api` }

@ prov_subject → s { ^ `user-42` }

// A fixed test scalar — this key is public by construction, which is
// exactly what a test key should be.
@ prov_sk → ( Vec u ) {
    ?? ( bytes_from_hex `c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721` ) {
        T v → { ^ v }
        F _ → { ^ ( vec_new [u] ) }
    }
}

// A SECOND key, published beside the real one and never used to sign —
// the decoy a relying party must walk past when the token names no kid.
@ prov_sk2 → ( Vec u ) {
    ?? ( bytes_from_hex `1122334455667788990011223344556677889900112233445566778899001122` ) {
        T v → { ^ v }
        F _ → { ^ ( vec_new [u] ) }
    }
}

@ prov_base → String {
    : String out ( string_from `http://127.0.0.1:` )
    ( string_push_int out g_port )
    ^ out
}

@ prov_url s path → String {
    : String out ( prov_base )
    ( string_push_str out path )
    ^ out
}

// ── JSON out ───────────────────────────────────────────────────────

@ prov_json i status String body → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `application/json` )
    ( response_set_body_str r ( string_data body ) )
    ( string_free body )
    ^ r
}

@ prov_kv String out s key s value b first → v {
    ? first {} { ( string_push_char out 44 ) }
    ( string_push_char out 34 )
    ( string_push_str out key )
    ( string_push_str out `":"` )
    ( string_push_str out value )
    ( string_push_char out 34 )
}

// ── Signing ────────────────────────────────────────────────────────

// header '.' payload '.' signature — `corrupt` flips a signature bit so
// the token is well-formed and wrong, which is the interesting case.
@ prov_sign s header s payload b corrupt → String {
    : String h64 ( b64_url_encode header )
    : String p64 ( b64_url_encode payload )
    : String signing ( string_with_cap 512 )
    ( string_push_str signing ( string_data h64 ) )
    ( string_push_char signing 46 )
    ( string_push_str signing ( string_data p64 ) )
    ( string_free h64 )
    ( string_free p64 )

    : ( Vec u ) msg ( bytes_from_str ( string_data signing ) )
    : ( Vec u ) h ( sha256_pure msg )
    ( vec_free [u] msg )
    : ( Vec u ) sk ( prov_sk )
    : ( Vec u ) sig ( ecdsa_p256_sign sk h )
    ( vec_free [u] sk )
    ( vec_free [u] h )
    ? corrupt {
        ?? ( vec_get [u] sig 0 ) {
            T b0 → { : b _ok ( vec_set [u] sig 0 # u ^^ # i b0 1 ) }
            F _ → {}
        }
    } {}
    : String s64 ( b64_url_encode_vec sig )
    ( vec_free [u] sig )
    ( string_push_char signing 46 )
    ( string_push_str signing ( string_data s64 ) )
    ( string_free s64 )
    ^ signing
}

// The JSON-source text `x\r\nX-Injected: yes` — which the JOSE header
// parser decodes into a kid containing a real CR LF.
@ prov_evil_kid → String {
    : String out ( string_from `x` )
    ( string_push_char out 92 ) ( string_push_char out 114 )
    ( string_push_char out 92 ) ( string_push_char out 110 )
    ( string_push_str out `X-Injected: yes` )
    ^ out
}

@ prov_header s alg s kid → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out `{"alg":"` )
    ( string_push_str out alg )
    ( string_push_str out `","typ":"JWT"` )
    ? > ( nurl_str_len kid ) 0 {
        ( string_push_str out `,"kid":"` )
        ( string_push_str out kid )
        ( string_push_char out 34 )
    } {}
    ( string_push_char out 125 )
    ^ out
}

// An ID token: the standard claim set plus the profile.
@ prov_id_claims s aud s nonce i exp_delta → String {
    : i now ( now_seconds )
    : String base ( prov_base )
    : String out ( string_with_cap 512 )
    ( string_push_char out 123 )
    ( prov_kv out `iss` ( string_data base ) T )
    ( prov_kv out `sub` ( prov_subject ) F )
    ( prov_kv out `aud` aud F )
    ( string_free base )
    ? > ( nurl_str_len nonce ) 0 { ( prov_kv out `nonce` nonce F ) } {}
    ( prov_kv out `email` `user42@example.com` F )
    ( prov_kv out `name` `Test User` F )
    ( prov_kv out `preferred_username` `tuser` F )
    ( string_push_str out `,"email_verified":true` )
    ( string_push_str out `,"iat":` )
    ( string_push_int out now )
    ( string_push_str out `,"auth_time":` )
    ( string_push_int out now )
    ( string_push_str out `,"exp":` )
    ( string_push_int out + now exp_delta )
    ( string_push_char out 125 )
    ^ out
}

// An access token in the RFC 9068 shape: audience = the API, with scopes.
@ prov_access_claims → String {
    ^ ( prov_access_claims_scope `openid profile read:things` )
}

@ prov_access_claims_scope s scope → String {
    : i now ( now_seconds )
    : String base ( prov_base )
    : String out ( string_with_cap 384 )
    ( string_push_char out 123 )
    ( prov_kv out `iss` ( string_data base ) T )
    ( prov_kv out `sub` ( prov_subject ) F )
    ( prov_kv out `aud` ( prov_api_audience ) F )
    ( prov_kv out `scope` scope F )
    ( string_free base )
    ( string_push_str out `,"iat":` )
    ( string_push_int out now )
    ( string_push_str out `,"exp":` )
    ( string_push_int out + now 300 )
    ( string_push_char out 125 )
    ^ out
}

// ── Endpoints ──────────────────────────────────────────────────────

@ prov_discovery → HttpResponse {
    : String out ( string_with_cap 512 )
    : String base ( prov_base )
    : String auth ( prov_url `/authorize` )
    : String tok ( prov_url `/token` )
    : String ui ( prov_url `/userinfo` )
    : String jwks ( prov_url `/jwks.json` )
    ( string_push_char out 123 )
    ( prov_kv out `issuer` ( string_data base ) T )
    ( prov_kv out `authorization_endpoint` ( string_data auth ) F )
    ( prov_kv out `token_endpoint` ( string_data tok ) F )
    ( prov_kv out `userinfo_endpoint` ( string_data ui ) F )
    ( prov_kv out `jwks_uri` ( string_data jwks ) F )
    ( string_push_str out `,"response_types_supported":["code"]` )
    ( string_push_str out `,"id_token_signing_alg_values_supported":["ES256"]` )
    ( string_push_str out `,"code_challenge_methods_supported":["S256"]` )
    ( string_push_char out 125 )
    ( string_free base ) ( string_free auth ) ( string_free tok )
    ( string_free ui ) ( string_free jwks )
    ^ ( prov_json 200 out )
}

// One JWK object for a private scalar, under `kid`.
@ prov_jwk_for ( Vec u ) sk s kid → String {
    : ( Vec u ) point ( p256_ecdh_keygen sk )
    : ( Vec u ) x ( bytes_slice point 1 33 )
    : ( Vec u ) y ( bytes_slice point 33 65 )
    ( vec_free [u] point )
    : String x64 ( b64_url_encode_vec x )
    : String y64 ( b64_url_encode_vec y )
    ( vec_free [u] x ) ( vec_free [u] y )
    : String out ( string_with_cap 256 )
    ( string_push_str out `{"kty":"EC","crv":"P-256","use":"sig","alg":"ES256","kid":"` )
    ( string_push_str out kid )
    ( string_push_str out `","x":"` )
    ( string_push_str out ( string_data x64 ) )
    ( string_push_str out `","y":"` )
    ( string_push_str out ( string_data y64 ) )
    ( string_push_str out `"}` )
    ( string_free x64 ) ( string_free y64 )
    ^ out
}

// The decoy is published FIRST, so a token with no `kid` only verifies
// for a relying party that walks past a key that does not fit.
@ prov_jwks → HttpResponse {
    : ( Vec u ) sk2 ( prov_sk2 )
    : String decoy ( prov_jwk_for sk2 `k0` )
    ( vec_free [u] sk2 )
    : ( Vec u ) sk ( prov_sk )
    : String real ( prov_jwk_for sk ( prov_kid ) )
    ( vec_free [u] sk )
    : String out ( string_with_cap 640 )
    ( string_push_str out `{"keys":[` )
    ( string_push_str out ( string_data decoy ) )
    ( string_push_char out 44 )
    ( string_push_str out ( string_data real ) )
    ( string_push_str out `]}` )
    ( string_free decoy ) ( string_free real )
    ^ ( prov_json 200 out )
}

@ prov_param ( Vec UrlParam ) ps s key → String {
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

@ prov_error i status s code s desc → HttpResponse {
    : String out ( string_with_cap 128 )
    ( string_push_char out 123 )
    ( prov_kv out `error` code T )
    ( prov_kv out `error_description` desc F )
    ( string_push_char out 125 )
    ^ ( prov_json status out )
}

// The i-th '.'-separated field of the code, or "".
@ prov_code_field String code i want → String {
    : ( Vec String ) parts ( string_split code `.` )
    : ~ String out ( string_new )
    ?? ( vec_get [String] parts want ) {
        T p → { ( string_free out ) = out ( string_from ( string_data p ) ) }
        F _ → {}
    }
    ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
    ^ out
}

@ prov_token HttpRequest req → HttpResponse {
    : String body ( bytes_to_str . req body )
    : ( Vec UrlParam ) ps ( url_query_decode ( string_data body ) )
    ( string_free body )
    : String grant ( prov_param ps `grant_type` )
    : String client ( prov_param ps `client_id` )
    : String code ( prov_param ps `code` )
    : String verifier ( prov_param ps `code_verifier` )
    : String refresh ( prov_param ps `refresh_token` )
    ( url_params_free ps )

    : ~ HttpResponse resp ( response_new 0 )
    : ~ b done F

    ? == 0 ( nurl_str_eq ( string_data client ) ( prov_client_id ) ) {
        ( http_response_free resp )
        = resp ( prov_error 401 `invalid_client` `unknown client_id` )
        = done T
    } {}

    ? done {} {
        ? == 1 ( nurl_str_eq ( string_data grant ) `authorization_code` ) {
            : String want ( prov_code_field code 1 )
            : String nonce ( prov_code_field code 2 )
            : ( Vec u ) msg ( bytes_from_str ( string_data verifier ) )
            : ( Vec u ) h ( sha256_pure msg )
            ( vec_free [u] msg )
            : String got ( b64_url_encode_vec h )
            ( vec_free [u] h )
            ? & > ( string_len want ) 0 ( string_eq got want ) {
                : String idc ( prov_id_claims ( prov_client_id ) ( string_data nonce ) 300 )
                : String hdr ( prov_header `ES256` ( prov_kid ) )
                : String idt ( prov_sign ( string_data hdr ) ( string_data idc ) F )
                : String ac ( prov_access_claims )
                : String at ( prov_sign ( string_data hdr ) ( string_data ac ) F )
                : String out ( string_with_cap 2048 )
                ( string_push_char out 123 )
                ( prov_kv out `access_token` ( string_data at ) T )
                ( prov_kv out `id_token` ( string_data idt ) F )
                ( prov_kv out `refresh_token` `rt-1` F )
                ( prov_kv out `token_type` `Bearer` F )
                ( prov_kv out `scope` `openid profile read:things` F )
                ( string_push_str out `,"expires_in":300}` )
                ( string_free idc ) ( string_free hdr ) ( string_free idt )
                ( string_free ac ) ( string_free at )
                ( http_response_free resp )
                = resp ( prov_json 200 out )
            } {
                ( http_response_free resp )
                = resp ( prov_error 400 `invalid_grant` `PKCE verification failed` )
            }
            ( string_free want ) ( string_free nonce ) ( string_free got )
            = done T
        } {}
    }

    ? done {} {
        ? == 1 ( nurl_str_eq ( string_data grant ) `refresh_token` ) {
            ? == 1 ( nurl_str_eq ( string_data refresh ) `rt-1` ) {
                : String hdr ( prov_header `ES256` ( prov_kid ) )
                : String ac ( prov_access_claims )
                : String at ( prov_sign ( string_data hdr ) ( string_data ac ) F )
                : String out ( string_with_cap 1024 )
                ( string_push_char out 123 )
                ( prov_kv out `access_token` ( string_data at ) T )
                ( prov_kv out `token_type` `Bearer` F )
                ( prov_kv out `refresh_token` `rt-2` F )
                ( string_push_str out `,"expires_in":300}` )
                ( string_free hdr ) ( string_free ac ) ( string_free at )
                ( http_response_free resp )
                = resp ( prov_json 200 out )
            } {
                ( http_response_free resp )
                = resp ( prov_error 400 `invalid_grant` `unknown refresh token` )
            }
            = done T
        } {}
    }

    ? done {} {
        ? == 1 ( nurl_str_eq ( string_data grant ) `client_credentials` ) {
            : String hdr ( prov_header `ES256` ( prov_kid ) )
            : String ac ( prov_access_claims )
            : String at ( prov_sign ( string_data hdr ) ( string_data ac ) F )
            : String out ( string_with_cap 1024 )
            ( string_push_char out 123 )
            ( prov_kv out `access_token` ( string_data at ) T )
            ( prov_kv out `token_type` `Bearer` F )
            ( string_push_str out `,"expires_in":300}` )
            ( string_free hdr ) ( string_free ac ) ( string_free at )
            ( http_response_free resp )
            = resp ( prov_json 200 out )
        } {
            ( http_response_free resp )
            = resp ( prov_error 400 `unsupported_grant_type` `no such grant` )
        }
    }

    ( string_free grant ) ( string_free client ) ( string_free code )
    ( string_free verifier ) ( string_free refresh )
    ^ resp
}

@ prov_userinfo HttpRequest req → HttpResponse {
    : ~ b authed F
    ?? ( header_get . req headers `Authorization` ) {
        T v → {
            = authed == 1 ( nurl_str_starts ( string_data v ) `Bearer ` )
            ( string_free v )
        }
        F _ → {}
    }
    ? authed {} {
        : HttpResponse r ( response_text 401 `Unauthorized\n` )
        ( response_set_header r `WWW-Authenticate` `Bearer` )
        ^ r
    }
    : String out ( string_with_cap 256 )
    ( string_push_char out 123 )
    ( prov_kv out `sub` ( prov_subject ) T )
    ( prov_kv out `email` `user42@example.com` F )
    ( prov_kv out `name` `Test User` F )
    ( string_push_str out `,"email_verified":true}` )
    ^ ( prov_json 200 out )
}

// Deliberately broken tokens, one per failure mode the verifier must
// catch. Served as text/plain so the test can feed them in directly.
@ prov_mint String kind → HttpResponse {
    : String hdr_ok ( prov_header `ES256` ( prov_kid ) )
    : ~ String token ( string_new )
    ? ( string_eq kind ( string_from `expired` ) ) {
        : String c ( prov_id_claims ( prov_client_id ) `` -600 )
        ( string_free token )
        = token ( prov_sign ( string_data hdr_ok ) ( string_data c ) F )
        ( string_free c )
    } {}
    ? ( string_eq kind ( string_from `badsig` ) ) {
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        ( string_free token )
        = token ( prov_sign ( string_data hdr_ok ) ( string_data c ) T )
        ( string_free c )
    } {}
    ? ( string_eq kind ( string_from `wrongaud` ) ) {
        : String c ( prov_id_claims `someone-else` `` 300 )
        ( string_free token )
        = token ( prov_sign ( string_data hdr_ok ) ( string_data c ) F )
        ( string_free c )
    } {}
    ? ( string_eq kind ( string_from `unknownkid` ) ) {
        : String h ( prov_header `ES256` `rotated-away` )
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        ( string_free token )
        = token ( prov_sign ( string_data h ) ( string_data c ) F )
        ( string_free c ) ( string_free h )
    } {}
    ? ( string_eq kind ( string_from `none` ) ) {
        // alg: none — header and claims, and an EMPTY signature.
        : String h ( string_from `{"alg":"none","typ":"JWT"}` )
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        : String h64 ( b64_url_encode ( string_data h ) )
        : String c64 ( b64_url_encode ( string_data c ) )
        ( string_free token )
        = token ( string_with_cap 512 )
        ( string_push_str token ( string_data h64 ) )
        ( string_push_char token 46 )
        ( string_push_str token ( string_data c64 ) )
        ( string_push_char token 46 )
        ( string_free h ) ( string_free c ) ( string_free h64 ) ( string_free c64 )
    } {}
    ? ( string_eq kind ( string_from `evilkid` ) ) {
        // A `kid` carrying CR LF and a header of its own. It names no
        // published key, so the token is refused — the point is what the
        // refusal PUTS IN THE RESPONSE.
        : String ek ( prov_evil_kid )
        : String h ( prov_header `ES256` ( string_data ek ) )
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        ( string_free token )
        = token ( prov_sign ( string_data h ) ( string_data c ) F )
        ( string_free c ) ( string_free h ) ( string_free ek )
    } {}
    ? ( string_eq kind ( string_from `nokid` ) ) {
        // Legal, and common: no `kid` at all. The verifier has to try
        // every key the algorithm admits.
        : String h ( prov_header `ES256` `` )
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        ( string_free token )
        = token ( prov_sign ( string_data h ) ( string_data c ) F )
        ( string_free c ) ( string_free h )
    } {}
    ? ( string_eq kind ( string_from `access` ) ) {
        : String c ( prov_access_claims )
        ( string_free token )
        = token ( prov_sign ( string_data hdr_ok ) ( string_data c ) F )
        ( string_free c )
    } {}
    ? ( string_eq kind ( string_from `noscope` ) ) {
        : String c ( prov_access_claims_scope `openid` )
        ( string_free token )
        = token ( prov_sign ( string_data hdr_ok ) ( string_data c ) F )
        ( string_free c )
    } {}
    ? ( string_eq kind ( string_from `hs256` ) ) {
        // HS256 over the same claims, "signed" with the PUBLIC x
        // coordinate — the key-confusion attack, spelled out.
        : ( Vec u ) sk ( prov_sk )
        : ( Vec u ) point ( p256_ecdh_keygen sk )
        ( vec_free [u] sk )
        : ( Vec u ) x ( bytes_slice point 1 33 )
        ( vec_free [u] point )
        : String h ( prov_header `HS256` ( prov_kid ) )
        : String c ( prov_id_claims ( prov_client_id ) `` 300 )
        : String h64 ( b64_url_encode ( string_data h ) )
        : String c64 ( b64_url_encode ( string_data c ) )
        : String signing ( string_with_cap 512 )
        ( string_push_str signing ( string_data h64 ) )
        ( string_push_char signing 46 )
        ( string_push_str signing ( string_data c64 ) )
        : ( Vec u ) msg ( bytes_from_str ( string_data signing ) )
        : ( Vec u ) mac ( hmac_sha256_pure x msg )
        : String m64 ( b64_url_encode_vec mac )
        ( string_push_char signing 46 )
        ( string_push_str signing ( string_data m64 ) )
        ( string_free token )
        = token signing
        ( vec_free [u] x ) ( vec_free [u] msg ) ( vec_free [u] mac )
        ( string_free h ) ( string_free c ) ( string_free h64 )
        ( string_free c64 ) ( string_free m64 )
    } {}
    ( string_free hdr_ok )
    ? == 0 ( string_len token ) {
        ( string_free token )
        ^ ( response_text 404 `no such mint\n` )
    } {}
    : HttpResponse r ( response_text 200 ( string_data token ) )
    ( string_free token )
    ^ r
}

@ prov_handle HttpRequest req → HttpResponse {
    : s path ( string_data . req path )
    ? == 1 ( nurl_str_eq path `/.well-known/openid-configuration` ) { ^ ( prov_discovery ) } {}
    ? == 1 ( nurl_str_eq path `/jwks.json` ) { ^ ( prov_jwks ) } {}
    ? == 1 ( nurl_str_eq path `/token` ) { ^ ( prov_token req ) } {}
    ? == 1 ( nurl_str_eq path `/userinfo` ) { ^ ( prov_userinfo req ) } {}
    ? == 1 ( nurl_str_starts path `/mint/` ) {
        : String kind ( string_substr . req path 6 - ( string_len . req path ) 6 )
        : HttpResponse r ( prov_mint kind )
        ( string_free kind )
        ^ r
    } {}
    ^ ( response_text 404 `not found\n` )
}

@ main → i {
    : ArgParser ap ( args_new `provider` `test OIDC provider` )
    ( args_opt ap `port` 112 `N` `bind port on 127.0.0.1` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }
    ?? ( args_value ap `port` ) {
        T v → {
            ?? ( string_to_int v ) { T x → { = g_port x } F _ → {} }
            ( string_free v )
        }
        F _ → {}
    }
    ( args_free ap )
    ? == g_port 0 { ( nurl_eprintln `provider: --port is required` ) ^ 2 } {}

    ?? ( tcp_listen `127.0.0.1` g_port ) {
        T l → {
            // A pool, not one serial accept loop: a relying party's HTTP
            // client keeps its connection to the provider alive, and a
            // single-connection provider would then starve every other
            // caller — including the curl in the test script.
            : HttpServer srv ( server_new l \ HttpRequest req → HttpResponse { ^ ( prov_handle req ) } )
            ?? ( server_run_pool srv 4 ) {
                T _ → { ^ 0 }
                F _ → { ( nurl_eprintln `provider: listener failed` ) ^ 1 }
            }
        }
        F _ → {
            ( nurl_eprintln `provider: cannot bind` )
            ^ 1
        }
    }
}
