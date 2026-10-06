// oauth/provider.nu — the identity provider: discovery, keys, verdict.
//
// Everything a relying party needs to know about a provider is published
// by the provider itself. `OidcProvider` is that knowledge, fetched once
// and kept:
//
//   ( oidc_provider_discover issuer )   → ! OidcProvider OauthErr
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
// THREADING: an `OidcProvider` owns one HTTP client and one mutable key
// cache, and takes no lock. One provider per thread, or one thread that
// owns it — sharing it across a server's worker pool is a data race, not
// a slow path. (An `OidcPolicy` is read-only once built and IS safe to
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
$ `stdlib/core/rcbox.nu`

: OidcProviderImpl {
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
    HttpClient http
}

// An OidcProvider is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: OidcProvider { s ctl }

unsafe @ OidcProvider_share OidcProvider h → OidcProvider { ^ @ OidcProvider { # s ( rcbox_share # i . h ctl ) } }

@ OidcProvider_drop sink OidcProvider h → v {
    ( mem_forget h )
    ( rcbox_release [OidcProviderImpl] # i . h ctl )
}

unsafe @ _OidcProvider_ptr OidcProvider h → *OidcProviderImpl { ^ ( rcbox_ptr [OidcProviderImpl] # i . h ctl ) }

// ── Lifecycle ──────────────────────────────────────────────────────

unsafe @ oidc_provider_new s issuer → OidcProvider {
    : i p__box ( rcbox_zero [OidcProviderImpl] )
    : *OidcProviderImpl p ( rcbox_ptr [OidcProviderImpl] p__box )
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
    ^ @ OidcProvider { # s p__box }
}

// Let go of `p` now rather than at the end of its owner's scope.
@ oidc_provider_free sink OidcProvider p → v {}

// The HTTP client every request goes through — exposed so a caller can
// set a timeout, turn off certificate verification for a test provider,
// or pin HTTP/3.
unsafe @ oidc_provider_http OidcProvider p__h → HttpClient {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ^ . p http
}

// What discovery found (or a setter put there); "" when unset.
unsafe @ oidc_provider_issuer OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) issuer ) }

unsafe @ oidc_provider_authorization_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) authorization_endpoint ) }

unsafe @ oidc_provider_token_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) token_endpoint ) }

unsafe @ oidc_provider_userinfo_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) userinfo_endpoint ) }

unsafe @ oidc_provider_jwks_uri OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) jwks_uri ) }

unsafe @ oidc_provider_end_session_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) end_session_endpoint ) }

unsafe @ oidc_provider_device_authorization_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) device_authorization_endpoint ) }

unsafe @ oidc_provider_introspection_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) introspection_endpoint ) }

unsafe @ oidc_provider_revocation_endpoint OidcProvider p → s { ^ ( string_data . ( _OidcProvider_ptr p ) revocation_endpoint ) }

unsafe @ oidc_provider_last_error OidcProvider p__h → s {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ^ ( string_data . p last_error )
}

unsafe @ oidc_provider_set_min_refetch OidcProvider p__h i secs → v {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    = . p min_refetch secs
}

unsafe @ _oidc_err * OidcProviderImpl p s msg → v {
    ( _oauth_set_str . p last_error msg )
}

unsafe @ _oidc_err2 * OidcProviderImpl p s msg s detail → v {
    ( string_clear . p last_error )
    ( string_push_str . p last_error msg )
    ( string_push_str . p last_error detail )
}

unsafe @ _oidc_err_status * OidcProviderImpl p s what i status → v {
    ( string_clear . p last_error )
    ( string_push_str . p last_error what )
    ( string_push_str . p last_error ` returned HTTP ` )
    ( string_push_int . p last_error status )
}

// ── Field setters (for a provider configured by hand) ──────────────

unsafe @ oidc_provider_set_jwks_uri OidcProvider p__h s uri → v {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ( _oauth_set_str . p jwks_uri uri )
}

unsafe @ oidc_provider_set_token_endpoint OidcProvider p__h s uri → v {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ( _oauth_set_str . p token_endpoint uri )
}

unsafe @ oidc_provider_set_authorization_endpoint OidcProvider p__h s uri → v {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ( _oauth_set_str . p authorization_endpoint uri )
}

unsafe @ oidc_provider_set_userinfo_endpoint OidcProvider p__h s uri → v {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ( _oauth_set_str . p userinfo_endpoint uri )
}

// The cached key set becomes `ks`: the old keys are dropped from the
// Vec, the new ones moved onto it (the field itself is not stored over —
// a store through the pointer would not release what it overwrites).
unsafe @ __oidc_keys_replace * OidcProviderImpl p sink ( Vec JwkKey ) ks → v {
    ( vec_clear [JwkKey] . p keys )
    ( vec_append [JwkKey] . p keys ks )
}

// Load a key set the caller already has (a pinned JWKS, an offline
// verifier, a test). Replaces whatever was cached.
unsafe @ oidc_provider_set_jwks OidcProvider p__h s jwks_json → b {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    : ( Vec JwkKey ) ks ( jwks_parse jwks_json )
    ? == 0 ( vec_len [JwkKey] ks ) { ^ F } {}
    ( __oidc_keys_replace p ks )
    = . p keys_at ( now_seconds )
    ^ T
}

unsafe @ oidc_provider_key_count OidcProvider p__h → i {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ^ ( vec_len [JwkKey] . p keys )
}

// ── HTTP ───────────────────────────────────────────────────────────

// GET a JSON document. Owns nothing of the caller's; the returned Json
// is owned by the caller.
unsafe @ __oidc_get_json * OidcProviderImpl p s what s url → !Json OauthErr {
    ?? ( http_client_get . p http url ) {
        T r → {
            : i status ( http_client_status r )
            ? & >= status 200 < status 300 {} {
                ( _oidc_err_status p what status )
                ^ @ !Json OauthErr { F OaHttpStatus }
            }
            : !Json JsonError pj ( json_parse_bytes . r body )
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

// A string member of the discovery document, into a String field of the
// provider (in place; empty when absent).
@ __oidc_adopt String dst Json doc s key → v {
    ( string_clear dst )
    ?? ( json_obj_get doc key ) {
        T v → { ? ( json_is_str v ) { ( string_push_str dst ( json_str_data v ) ) } {} }
        F _ → {}
    }
}

// <issuer>/.well-known/openid-configuration, with exactly one slash.
@ oidc_discovery_url s issuer → String {
    : ~ String out ( string_from issuer )
    : i n ( string_len out )
    ? & > n 0 == ( string_get out - n 1 ) 47 {
        : String trimmed ( string_substr out 0 - n 1 )
        = out trimmed
    } {}
    ( string_push_str out `/.well-known/openid-configuration` )
    ^ out
}

// Fetch the metadata document and adopt its endpoints. None = success.
unsafe @ oidc_discover OidcProvider p__h → ?OauthErr {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    : String url ( oidc_discovery_url ( string_data . p issuer ) )
    : !Json OauthErr dj ( __oidc_get_json p `discovery` ( string_data url ) )
    ?? dj {
        T doc → {
            // RFC 8414 §3.3: the document must claim the issuer we asked
            // for. Anything else is a metadata substitution.
            : String iss ( claims_str doc `issuer` )
            ? ( string_eq iss . p issuer ) {} {
                ( _oidc_err2 p `discovery issuer mismatch: ` ( string_data iss ) )
                ^ @ ?OauthErr { T OaIssuerMismatch }
            }
            ( __oidc_adopt . p authorization_endpoint doc `authorization_endpoint` )
            ( __oidc_adopt . p token_endpoint doc `token_endpoint` )
            ( __oidc_adopt . p userinfo_endpoint doc `userinfo_endpoint` )
            ( __oidc_adopt . p jwks_uri doc `jwks_uri` )
            ( __oidc_adopt . p end_session_endpoint doc `end_session_endpoint` )
            ( __oidc_adopt . p device_authorization_endpoint doc `device_authorization_endpoint` )
            ( __oidc_adopt . p introspection_endpoint doc `introspection_endpoint` )
            ( __oidc_adopt . p revocation_endpoint doc `revocation_endpoint` )
            = . p discovered T
            ^ @ ?OauthErr { F }
        }
        F e → { ^ @ ?OauthErr { T # OauthErr e } }
    }
}

@ oidc_provider_discover s issuer → !OidcProvider OauthErr {
    : OidcProvider p ( oidc_provider_new issuer )
    ?? ( oidc_discover p ) {
        T e → { ^ @ !OidcProvider OauthErr { F # OauthErr e } }
        F _ → { ^ @ !OidcProvider OauthErr { T p } }
    }
}

// ── Key set ────────────────────────────────────────────────────────

// Fetch jwks_uri and replace the cached set. None = success.
unsafe @ oidc_fetch_jwks OidcProvider p__h → ?OauthErr {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ? == 0 ( string_len . p jwks_uri ) {
        ( _oidc_err p `no jwks_uri — run discovery or set one` )
        ^ @ ?OauthErr { T OaConfig }
    } {}
    : !Json OauthErr kj ( __oidc_get_json p `jwks` ( string_data . p jwks_uri ) )
    ?? kj {
        T doc → {
            : ( Vec JwkKey ) ks ( jwks_from_json doc )
            // The fetch happened: record the time even for an empty set,
            // so a provider that answers with junk cannot be polled hard.
            = . p keys_at ( now_seconds )
            ? == 0 ( vec_len [JwkKey] ks ) {
                ( _oidc_err p `jwks document contains no keys` )
                ^ @ ?OauthErr { T OaNoJwks }
            } {}
            ( __oidc_keys_replace p ks )
            ^ @ ?OauthErr { F }
        }
        F e → { ^ @ ?OauthErr { T # OauthErr e } }
    }
}

// Index of the key for (kid, alg), fetching or re-fetching the JWKS when
// that is what it takes. -1 when the provider has no such key.
unsafe @ oidc_provider_ensure_key OidcProvider p__h s kid s alg → i {
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    ? == 0 ( vec_len [JwkKey] . p keys ) {
        ?? ( oidc_fetch_jwks p__h ) { T _ → { ^ -1 } F _ → {} }
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
    ?? ( oidc_fetch_jwks p__h ) { T _ → { ^ -1 } F _ → {} }
    : i idx2 ( jwks_select . p keys kid alg )
    ? < idx2 0 { ( _oidc_err2 p `no key for kid ` kid ) } {}
    ^ idx2
}

// ── Verification ───────────────────────────────────────────────────

// The whole check, at an explicit `now` (epoch seconds), of an ID token.
@ oidc_verify_token_at OidcProvider p__h OidcPolicy pol__h s token i now → !OidcIdentity OauthErr {
    ^ ( _oidc_verify_at p__h pol__h token now F )
}

// The same for an access token presented to a resource server: its `azp`
// is the client that asked for it, not us (claims_check_access).
@ oidc_verify_access_token_at OidcProvider p__h OidcPolicy pol__h s token i now → !OidcIdentity OauthErr {
    ^ ( _oidc_verify_at p__h pol__h token now T )
}

unsafe @ _oidc_verify_at OidcProvider p__h OidcPolicy pol__h s token i now b access → !OidcIdentity OauthErr {
    : *OidcPolicyImpl pol ( _OidcPolicy_ptr pol__h )
    : *OidcProviderImpl p ( _OidcProvider_ptr p__h )
    // Read the JOSE header ONCE: a token that is not a well-formed JWS
    // is malformed, which is a different answer from "the algorithm it
    // names is not one we accept".
    : ~ String alg ( string_new )
    : ~ String kid ( string_new )
    ?? ( jws_header_json token ) {
        T h → {
            = alg ( _jws_json_str h `alg` )
            = kid ( _jws_json_str h `kid` )
        }
        F e → {
            ( _oidc_err p `not a well-formed JWS` )
            ^ @ !OidcIdentity OauthErr { F # OauthErr e }
        }
    }
    : s algp ( string_data alg )
    : s kidp ( string_data kid )

    // RFC 7515 §4.1.1: `alg` is REQUIRED in the header.
    ? == 0 ( string_len alg ) {
        ( _oidc_err p `JOSE header has no alg` )
        ^ @ !OidcIdentity OauthErr { F OaBadToken }
    } {}
    ? ( jws_alg_supported algp ) {} {
        ( _oidc_err2 p `unsupported alg: ` algp )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    ? ( oidc_policy_alg_allowed pol__h algp ) {} {
        ( _oidc_err2 p `alg not in policy allowlist: ` algp )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    // A published key set holds PUBLIC keys. Verifying an HS* token
    // against one turns a public key into a shared secret — the key
    // confusion attack — so symmetric algorithms need an explicit opt-in.
    ? ( jws_alg_symmetric algp ) {
        ? . pol allow_symmetric {} {
            ( _oidc_err2 p `symmetric alg refused: ` algp )
            ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
        }
    } {}

    : i idx ( oidc_provider_ensure_key p__h kidp algp )
    ? < idx 0 {
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
                    = claims c
                    = verified T
                    = more F
                }
                F _ → { = from + k 1 }
            }
        }
    }
    ? verified {} {
        ( _oidc_err p `signature did not verify under any published key` )
        ^ @ !OidcIdentity OauthErr { F OaBadSignature }
    }
    ?? ( _claims_check claims pol__h now access ) {
        T ce → {
            ( _oidc_err p ( claim_err_desc # ClaimErr ce ) )
            ^ @ !OidcIdentity OauthErr { F OaClaims }
        }
        F _ → {}
    }
    ^ @ !OidcIdentity OauthErr { T ( oidc_identity_from_claims claims ) }
}

@ oidc_verify_token OidcProvider p__h OidcPolicy pol__h s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_token_at p__h pol__h token ( now_seconds ) )
}

// Named for what is verified. An ID token is checked against the client
// id in `aud` and must have been issued to us (`azp`); an access token
// issued as a JWT (RFC 9068) is checked against the resource server's
// own audience, whichever client requested it.
@ oidc_verify_id_token OidcProvider p__h OidcPolicy pol__h s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_token_at p__h pol__h token ( now_seconds ) )
}

@ oidc_verify_access_token OidcProvider p__h OidcPolicy pol__h s token → !OidcIdentity OauthErr {
    ^ ( oidc_verify_access_token_at p__h pol__h token ( now_seconds ) )
}
