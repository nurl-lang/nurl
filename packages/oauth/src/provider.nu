// oauth/provider.nu — the identity provider: discovery, keys, verdict.
//
// Everything a relying party needs to know about a provider is published
// by the provider itself. `OidcProvider` is that knowledge, fetched once
// and kept:
//
//   ( oidc_provider_discover issuer )   → ! *OidcProvider OauthErr
//       GET <issuer>/.well-known/openid-configuration (RFC 8414 §3), and
//       CHECK that the document's own `issuer` is the one we asked for —
//       otherwise a redirect to an attacker's metadata would silently
//       repoint the token and userinfo endpoints.
//
//   ( oidc_verify_id_token p pol token ) → ! OidcIdentity OauthErr
//       The whole answer to "who is this": parse the JOSE header, find
//       the key it names in the provider's JWKS (fetching the set on
//       first use, and re-fetching when a `kid` we have never seen shows
//       up — that is key rotation, and it must not need a restart),
//       verify the signature, apply the claim policy, and hand back the
//       identity with the full claim set attached.
//
// The JWKS re-fetch is rate-limited (`oidc_provider_set_min_refetch`,
// default 300 s): an unknown `kid` is also what a flood of forged tokens
// looks like, and a verifier that fetches on every one of them is a
// denial-of-service amplifier pointed at its own provider.
//
// A failure that has detail the enum cannot carry — the HTTP status, the
// claim that was wrong, the provider's own `error_description` — leaves
// it in `oidc_provider_last_error`.
//
// THREADING: an `*OidcProvider` owns one HTTP client and one mutable key
// cache, and takes no lock. One provider per thread, or one thread that
// owns it — sharing it across a server's worker pool is a data race, not
// a slow path. (An `*OidcPolicy` is read-only once built and IS safe to
// share; so is a verified `OidcIdentity`, which is a value.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `deps/http-client/src/http_client.nu`
$ `errors.nu`
$ `jwk.nu`
$ `jws.nu`
$ `claims.nu`

: OidcProvider {
    String issuer
    String authorization_endpoint
    String token_endpoint
    String userinfo_endpoint
    String jwks_uri
    String end_session_endpoint
    String device_authorization_endpoint
    String introspection_endpoint
    String revocation_endpoint
    ( Vec JwkKey ) keys
    i keys_at  // epoch seconds of the last JWKS fetch (0 = never)
    i min_refetch  // seconds that must pass before another JWKS fetch
    b discovered
    String last_error
    * HttpClient http
}

// ── Lifecycle ──────────────────────────────────────────────────────

@ oidc_provider_new s issuer → *OidcProvider {
    : *OidcProvider p # *OidcProvider ( nurl_malloc Z OidcProvider )
    = . p issuer ( string_from issuer )
    = . p authorization_endpoint ( string_new )
    = . p token_endpoint ( string_new )
    = . p userinfo_endpoint ( string_new )
    = . p jwks_uri ( string_new )
    = . p end_session_endpoint ( string_new )
    = . p device_authorization_endpoint ( string_new )
    = . p introspection_endpoint ( string_new )
    = . p revocation_endpoint ( string_new )
    = . p keys ( vec_new [JwkKey] )
    = . p keys_at 0
    = . p min_refetch 300
    = . p discovered F
    = . p last_error ( string_new )
    = . p http ( http_client_new )
    ^ p
}

@ oidc_provider_free * OidcProvider p → v {
    ( string_free . p issuer )
    ( string_free . p authorization_endpoint )
    ( string_free . p token_endpoint )
    ( string_free . p userinfo_endpoint )
    ( string_free . p jwks_uri )
    ( string_free . p end_session_endpoint )
    ( string_free . p device_authorization_endpoint )
    ( string_free . p introspection_endpoint )
    ( string_free . p revocation_endpoint )
    ( string_free . p last_error )
    ( jwks_free . p keys )
    ( http_client_free . p http )
    ( nurl_free # s p )
}

// The HTTP client every request goes through — exposed so a caller can
// set a timeout, turn off certificate verification for a test provider,
// or pin HTTP/3.
@ oidc_provider_http * OidcProvider p → *HttpClient { ^ . p http }

@ oidc_provider_last_error * OidcProvider p → s { ^ ( string_data . p last_error ) }

@ oidc_provider_set_min_refetch * OidcProvider p i secs → v { = . p min_refetch secs }

@ _oidc_err * OidcProvider p s msg → v {
    ( string_free . p last_error )
    = . p last_error ( string_from msg )
}

@ _oidc_err2 * OidcProvider p s msg s detail → v {
    : String out ( string_with_cap 96 )
    ( string_push_str out msg )
    ( string_push_str out detail )
    ( string_free . p last_error )
    = . p last_error out
}

@ _oidc_err_status * OidcProvider p s what i status → v {
    : String out ( string_with_cap 96 )
    ( string_push_str out what )
    ( string_push_str out ` returned HTTP ` )
    ( string_push_int out status )
    ( string_free . p last_error )
    = . p last_error out
}

// ── Field setters (for a provider configured by hand) ──────────────

@ oidc_provider_set_jwks_uri * OidcProvider p s uri → v {
    ( string_free . p jwks_uri )
    = . p jwks_uri ( string_from uri )
}

@ oidc_provider_set_token_endpoint * OidcProvider p s uri → v {
    ( string_free . p token_endpoint )
    = . p token_endpoint ( string_from uri )
}

@ oidc_provider_set_authorization_endpoint * OidcProvider p s uri → v {
    ( string_free . p authorization_endpoint )
    = . p authorization_endpoint ( string_from uri )
}

@ oidc_provider_set_userinfo_endpoint * OidcProvider p s uri → v {
    ( string_free . p userinfo_endpoint )
    = . p userinfo_endpoint ( string_from uri )
}

// Load a key set the caller already has (a pinned JWKS, an offline
// verifier, a test). Replaces whatever was cached.
@ oidc_provider_set_jwks * OidcProvider p s jwks_json → b {
    : ( Vec JwkKey ) ks ( jwks_parse jwks_json )
    ? == 0 ( vec_len [JwkKey] ks ) { ( jwks_free ks ) ^ F } {}
    ( jwks_free . p keys )
    = . p keys ks
    = . p keys_at ( now_seconds )
    ^ T
}

@ oidc_provider_key_count * OidcProvider p → i { ^ ( vec_len [JwkKey] . p keys ) }

// ── HTTP ───────────────────────────────────────────────────────────

// GET a JSON document. Owns nothing of the caller's; the returned Json
// is owned by the caller.
@ __oidc_get_json * OidcProvider p s what s url → !Json OauthErr {
    ?? ( http_client_get . p http url ) {
        T r → {
            : i status ( http_client_status r )
            ? & >= status 200 < status 300 {} {
                ( _oidc_err_status p what status )
                ( http_response_free r )
                ^ @ !Json OauthErr { F OaHttpStatus }
            }
            : !Json JsonError pj ( json_parse_bytes . r body )
            ( http_response_free r )
            ?? pj {
                T j → { ^ @ !Json OauthErr { T j } }
                F _ → {
                    ( _oidc_err2 p what ` did not return JSON` )
                    ^ @ !Json OauthErr { F OaBadResponse }
                }
            }
        }
        F e → {
            ( _oidc_err2 p what ( http_client_err_name e ) )
            ^ @ !Json OauthErr { F OaNetwork }
        }
    }
}

// ── Discovery ──────────────────────────────────────────────────────

// <issuer>/.well-known/openid-configuration, with exactly one slash.
@ oidc_discovery_url s issuer → String {
    : ~ String out ( string_from issuer )
    : i n ( string_len out )
    ? & > n 0 == ( string_get out - n 1 ) 47 {
        : String trimmed ( string_substr out 0 - n 1 )
        ( string_free out )
        = out trimmed
    } {}
    ( string_push_str out `/.well-known/openid-configuration` )
    ^ out
}

// Fetch the metadata document and adopt its endpoints. None = success.
@ oidc_discover * OidcProvider p → ?OauthErr {
    : String url ( oidc_discovery_url ( string_data . p issuer ) )
    : !Json OauthErr dj ( __oidc_get_json p `discovery` ( string_data url ) )
    ( string_free url )
    ?? dj {
        T doc → {
            // RFC 8414 §3.3: the document must claim the issuer we asked
            // for. Anything else is a metadata substitution.
            : String iss ( claims_str doc `issuer` )
            ? ( string_eq iss . p issuer ) {} {
                ( _oidc_err2 p `discovery issuer mismatch: ` ( string_data iss ) )
                ( string_free iss )
                ( json_free doc )
                ^ @ ?OauthErr { T OaIssuerMismatch }
            }
            ( string_free iss )
            ( string_free . p authorization_endpoint )
            = . p authorization_endpoint ( claims_str doc `authorization_endpoint` )
            ( string_free . p token_endpoint )
            = . p token_endpoint ( claims_str doc `token_endpoint` )
            ( string_free . p userinfo_endpoint )
            = . p userinfo_endpoint ( claims_str doc `userinfo_endpoint` )
            ( string_free . p jwks_uri )
            = . p jwks_uri ( claims_str doc `jwks_uri` )
            ( string_free . p end_session_endpoint )
            = . p end_session_endpoint ( claims_str doc `end_session_endpoint` )
            ( string_free . p device_authorization_endpoint )
            = . p device_authorization_endpoint ( claims_str doc `device_authorization_endpoint` )
            ( string_free . p introspection_endpoint )
            = . p introspection_endpoint ( claims_str doc `introspection_endpoint` )
            ( string_free . p revocation_endpoint )
            = . p revocation_endpoint ( claims_str doc `revocation_endpoint` )
            ( json_free doc )
            = . p discovered T
            ^ @ ?OauthErr { F }
        }
        F e → { ^ @ ?OauthErr { T # OauthErr e } }
    }
}

@ oidc_provider_discover s issuer → !*OidcProvider OauthErr {
    : *OidcProvider p ( oidc_provider_new issuer )
    ?? ( oidc_discover p ) {
        T e → {
            ( oidc_provider_free p )
            ^ @ !*OidcProvider OauthErr { F # OauthErr e }
        }
        F _ → { ^ @ !*OidcProvider OauthErr { T p } }
    }
}

// ── Key set ────────────────────────────────────────────────────────

// Fetch jwks_uri and replace the cached set. None = success.
@ oidc_fetch_jwks * OidcProvider p → ?OauthErr {
    ? == 0 ( string_len . p jwks_uri ) {
        ( _oidc_err p `no jwks_uri — run discovery or set one` )
        ^ @ ?OauthErr { T OaConfig }
    } {}
    : !Json OauthErr kj ( __oidc_get_json p `jwks` ( string_data . p jwks_uri ) )
    ?? kj {
        T doc → {
            : ( Vec JwkKey ) ks ( jwks_from_json doc )
            ( json_free doc )
            // The fetch happened: record the time even for an empty set,
            // so a provider that answers with junk cannot be polled hard.
            = . p keys_at ( now_seconds )
            ? == 0 ( vec_len [JwkKey] ks ) {
                ( jwks_free ks )
                ( _oidc_err p `jwks document contains no keys` )
                ^ @ ?OauthErr { T OaNoJwks }
            } {}
            ( jwks_free . p keys )
            = . p keys ks
            ^ @ ?OauthErr { F }
        }
        F e → { ^ @ ?OauthErr { T # OauthErr e } }
    }
}

// Index of the key for (kid, alg), fetching or re-fetching the JWKS when
// that is what it takes. -1 when the provider has no such key.
@ oidc_provider_ensure_key * OidcProvider p s kid s alg → i {
    ? == 0 ( vec_len [JwkKey] . p keys ) {
        ?? ( oidc_fetch_jwks p ) { T _ → { ^ -1 } F _ → {} }
    } {}
    : i idx ( jwks_select . p keys kid alg )
    ? >= idx 0 { ^ idx } {}
    // Unknown kid → the provider may have rotated. Re-fetch, but not
    // more often than min_refetch: forged tokens with random kids must
    // not turn this verifier into a load generator.
    : i age - ( now_seconds ) . p keys_at
    ? < age . p min_refetch {
        ( _oidc_err2 p `no key for kid ` kid )
        ^ -1
    } {}
    ?? ( oidc_fetch_jwks p ) { T _ → { ^ -1 } F _ → {} }
    : i idx2 ( jwks_select . p keys kid alg )
    ? < idx2 0 { ( _oidc_err2 p `no key for kid ` kid ) } {}
    ^ idx2
}

// ── Verification ───────────────────────────────────────────────────

// The whole check, at an explicit `now` (epoch seconds).
@ oidc_verify_token_at * OidcProvider p * OidcPolicy pol s token i now → !OidcIdentity OauthErr {
    // Read the JOSE header ONCE: a token that is not a well-formed JWS
    // is malformed, which is a different answer from "the algorithm it
    // names is not one we accept".
    : ~ String alg ( string_new )
    : ~ String kid ( string_new )
    ?? ( jws_header_json token ) {
        T h → {
            ( string_free alg )
            ( string_free kid )
            = alg ( _jws_json_str h `alg` )
            = kid ( _jws_json_str h `kid` )
            ( json_free h )
        }
        F e → {
            ( string_free alg ) ( string_free kid )
            ( _oidc_err p `not a well-formed JWS` )
            ^ @ !OidcIdentity OauthErr { F # OauthErr e }
        }
    }
    : s algp ( string_data alg )
    : s kidp ( string_data kid )

    // RFC 7515 §4.1.1: `alg` is REQUIRED in the header.
    ? == 0 ( string_len alg ) {
        ( _oidc_err p `JOSE header has no alg` )
        ( string_free alg ) ( string_free kid )
        ^ @ !OidcIdentity OauthErr { F OaBadToken }
    } {}
    ? ( jws_alg_supported algp ) {} {
        ( _oidc_err2 p `unsupported alg: ` algp )
        ( string_free alg ) ( string_free kid )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    ? ( oidc_policy_alg_allowed pol algp ) {} {
        ( _oidc_err2 p `alg not in policy allowlist: ` algp )
        ( string_free alg ) ( string_free kid )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    // A published key set holds PUBLIC keys. Verifying an HS* token
    // against one turns a public key into a shared secret — the key
    // confusion attack — so symmetric algorithms need an explicit opt-in.
    ? ( jws_alg_symmetric algp ) {
        ? . pol allow_symmetric {} {
            ( _oidc_err2 p `symmetric alg refused: ` algp )
            ( string_free alg ) ( string_free kid )
            ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
        }
    } {}

    : i idx ( oidc_provider_ensure_key p kidp algp )
    ? < idx 0 {
        ( string_free alg ) ( string_free kid )
        ^ @ !OidcIdentity OauthErr { F OaNoKey }
    } {}

    // Try EVERY key the (kid, alg) pair admits, not just the first. With
    // no `kid` in the header — which is legal — a provider mid-rotation
    // publishes two keys of the same type, and only one of them signed
    // this token.
    : *JwkKey data ( vec_data [JwkKey] . p keys )
    : ~ Json claims ( json_null )
    : ~ b verified F
    : ~ i from idx
    : ~ b more T
    ~ more {
        : i k ( jwks_select_from . p keys kidp algp from )
        ? < k 0 {
            = more F
        } {
            : JwkKey jk . data k
            ?? ( jws_verify_with_key jk token ) {
                T c → {
                    ( json_free claims )
                    = claims c
                    = verified T
                    = more F
                }
                F _ → { = from + k 1 }
            }
        }
    }
    ( string_free alg )
    ( string_free kid )
    ? verified {} {
        ( json_free claims )
        ( _oidc_err p `signature did not verify under any published key` )
        ^ @ !OidcIdentity OauthErr { F OaBadSignature }
    }
    ?? ( claims_check claims pol now ) {
        T ce → {
            ( _oidc_err p ( claim_err_desc # ClaimErr ce ) )
            ( json_free claims )
            ^ @ !OidcIdentity OauthErr { F OaClaims }
        }
        F _ → {}
    }
    ^ @ !OidcIdentity OauthErr { T ( oidc_identity_from_claims claims ) }
}

@ oidc_verify_token * OidcProvider p * OidcPolicy pol s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_token_at p pol token ( now_seconds ) )
}

// Named for the caller's intent — the same check either way. An ID token
// is verified against the client id in `aud`; an access token issued as
// a JWT (RFC 9068) against the resource server's own audience.
@ oidc_verify_id_token * OidcProvider p * OidcPolicy pol s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_token_at p pol token ( now_seconds ) )
}

@ oidc_verify_access_token * OidcProvider p * OidcPolicy pol s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_token_at p pol token ( now_seconds ) )
}
