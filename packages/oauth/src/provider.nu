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
// THREADING: an `OidcProvider` owns one HTTP client and one key cache in
// a Locked, so a server's workers share one provider. A verification
// copies the keys it may use out under the lock and checks the signature
// outside it: verifications run in parallel, and only a JWKS (re)fetch
// holds the state while it waits on the network. An `OidcPolicy` is
// shared the same way; a verified `OidcIdentity` is a value.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `deps/http-client/src/http_client.nu`
$ `errors.nu`
$ `jwk.nu`
$ `jws.nu`
$ `claims.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`

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
    i keys_at  // epoch seconds of the last JWKS fetch (0 = never)
    i min_refetch  // seconds that must pass before another JWKS fetch
    b discovered
    String last_error
    HttpClient http
}

// An OidcProvider is a handle on its state in a Locked (stdlib/std/thread.nu):
// every copy is the same state, and the last owner releases it. The key
// set is a snapshot in an Arc, in a Locked of its own: a verification
// takes a share of it — one count, nothing copied — and checks the
// signature with no lock held; a (re)fetch puts a new snapshot there.
: OidcProvider { ( Locked OidcProviderImpl ) st ( Locked ( Arc ( Vec JwkKey ) ) ) keys }

@ OidcProvider_share OidcProvider h → OidcProvider { ^ @ OidcProvider { ( Locked_share [OidcProviderImpl] . h st ) ( Locked_share [( Arc ( Vec JwkKey ) )] . h keys ) } }

@ OidcProvider_drop sink OidcProvider h → v {}

// ── Lifecycle ──────────────────────────────────────────────────────

@ oidc_provider_new s issuer → OidcProvider {
    : OidcProviderImpl p @ OidcProviderImpl {
        ( string_from issuer )
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        0
        300
        F
        ( string_new )
        ( http_client_new )
    }
    ^ @ OidcProvider { ( locked_new [OidcProviderImpl] p ) ( locked_new [( Arc ( Vec JwkKey ) )] ( arc_new [( Vec JwkKey )] ( vec_new [JwkKey] ) ) ) }
}

// Let go of `p` now rather than at the end of its owner's scope.
@ oidc_provider_free sink OidcProvider p → v {}

// The HTTP client every request goes through — exposed so a caller can
// set a timeout, turn off certificate verification for a test provider,
// or pin HTTP/3.
@ oidc_provider_http OidcProvider h → HttpClient {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : HttpClient c ( HttpClient_share . p http )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ c
}

// What discovery found (or a setter put there); "" when unset.
@ oidc_provider_issuer OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p issuer )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_authorization_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p authorization_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_token_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p token_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_userinfo_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p userinfo_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_jwks_uri OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p jwks_uri )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_end_session_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p end_session_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_device_authorization_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p device_authorization_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_introspection_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p introspection_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_revocation_endpoint OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p revocation_endpoint )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_last_error OidcProvider h → s {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : String r ( string_clone . p last_error )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ ( string_data r )
}

@ oidc_provider_set_min_refetch OidcProvider h i secs → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    = . p min_refetch secs
    ( locked_restore [OidcProviderImpl] . h st p )
}

// The last error, on the state checked out (`p`) or through the handle.
@ _oidc_err inout OidcProviderImpl p s msg → v {
    ( _oauth_set_str . p last_error msg )
}

@ _oidc_err2 inout OidcProviderImpl p s msg s detail → v {
    ( string_clear . p last_error )
    ( string_push_str . p last_error msg )
    ( string_push_str . p last_error detail )
}

@ _oidc_err_status inout OidcProviderImpl p s what i status → v {
    ( string_clear . p last_error )
    ( string_push_str . p last_error what )
    ( string_push_str . p last_error ` returned HTTP ` )
    ( string_push_int . p last_error status )
}

@ _oidc_err_h OidcProvider h s msg → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    ( _oidc_err p msg )
    ( locked_restore [OidcProviderImpl] . h st p )
}

@ _oidc_err_status_h OidcProvider h s what i status → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    ( _oidc_err_status p what status )
    ( locked_restore [OidcProviderImpl] . h st p )
}

@ _oidc_err2_h OidcProvider h s msg s detail → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    ( _oidc_err2 p msg detail )
    ( locked_restore [OidcProviderImpl] . h st p )
}

// ── Field setters (for a provider configured by hand) ──────────────

@ oidc_provider_set_jwks_uri OidcProvider h s uri → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    = . p jwks_uri ( string_from uri )
    ( locked_restore [OidcProviderImpl] . h st p )
}

@ oidc_provider_set_token_endpoint OidcProvider h s uri → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    = . p token_endpoint ( string_from uri )
    ( locked_restore [OidcProviderImpl] . h st p )
}

@ oidc_provider_set_authorization_endpoint OidcProvider h s uri → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    = . p authorization_endpoint ( string_from uri )
    ( locked_restore [OidcProviderImpl] . h st p )
}

@ oidc_provider_set_userinfo_endpoint OidcProvider h s uri → v {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    = . p userinfo_endpoint ( string_from uri )
    ( locked_restore [OidcProviderImpl] . h st p )
}

// Load a key set the caller already has (a pinned JWKS, an offline
// verifier, a test). Replaces whatever was cached.
@ oidc_provider_set_jwks OidcProvider h s jwks_json → b {
    : ( Vec JwkKey ) ks ( jwks_parse jwks_json )
    ? == 0 ( vec_len [JwkKey] ks ) { ^ F } {}
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    ( locked_set [( Arc ( Vec JwkKey ) )] . h keys ( arc_new [( Vec JwkKey )] ks ) )
    = . p keys_at ( now_seconds )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ T
}

// The key set as it is now.
@ _oidc_keys OidcProvider h → ( Arc ( Vec JwkKey ) ) { ^ ( locked_get [( Arc ( Vec JwkKey ) )] . h keys ) }

@ oidc_provider_key_count OidcProvider h → i {
    : ( Arc ( Vec JwkKey ) ) ks ( _oidc_keys h )
    ^ ( vec_len [JwkKey] ( arc_get [( Vec JwkKey )] ks ) )
}

// ── HTTP ───────────────────────────────────────────────────────────

// GET a JSON document. Owns nothing of the caller's; the returned Json
// is owned by the caller.
@ __oidc_get_json inout OidcProviderImpl p s what s url → !Json OauthErr {
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
@ oidc_discover OidcProvider h → ?OauthErr {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : ?OauthErr r ( __oidc_discover p )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ r
}

@ __oidc_discover inout OidcProviderImpl p → ?OauthErr {
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
@ oidc_fetch_jwks OidcProvider h → ?OauthErr {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : ?OauthErr r ( __oidc_fetch_jwks p h )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ r
}

// (`p` is `h`'s state, checked out.)
@ __oidc_fetch_jwks inout OidcProviderImpl p OidcProvider h → ?OauthErr {
    ? == 0 ( string_len . p jwks_uri ) {
        ( _oidc_err p `no jwks_uri — run discovery or set one` )
        ^ @ ?OauthErr { T OaConfig }
    } {}
    // (A copy: the fetch may record an error into `p` while it reads the URI.)
    : String uri ( string_from ( string_data . p jwks_uri ) )
    : !Json OauthErr kj ( __oidc_get_json p `jwks` ( string_data uri ) )
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
            ( locked_set [( Arc ( Vec JwkKey ) )] . h keys ( arc_new [( Vec JwkKey )] ks ) )
            ^ @ ?OauthErr { F }
        }
        F e → { ^ @ ?OauthErr { T # OauthErr e } }
    }
}

// Index of the key for (kid, alg), fetching or re-fetching the JWKS when
// that is what it takes. -1 when the provider has no such key.
@ oidc_provider_ensure_key OidcProvider h s kid s alg → i {
    : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
    : i r ( __oidc_ensure_key p h kid alg )
    ( locked_restore [OidcProviderImpl] . h st p )
    ^ r
}

// (`p` is `h`'s state, checked out.)
@ __oidc_ensure_key inout OidcProviderImpl p OidcProvider h s kid s alg → i {
    ? == 0 ( oidc_provider_key_count h ) {
        ?? ( __oidc_fetch_jwks p h ) { T _ → { ^ -1 } F _ → {} }
    } {}
    : i idx ( jwks_select ( arc_get [( Vec JwkKey )] ( _oidc_keys h ) ) kid alg )
    ? >= idx 0 { ^ idx } {}
    // Unknown kid → the provider may have rotated. Re-fetch, but not
    // more often than min_refetch: forged tokens with random kids must
    // not turn this verifier into a load generator.
    : i age - ( now_seconds ) . p keys_at
    ? < age . p min_refetch {
        ( _oidc_err2 p `no key for kid ` kid )
        ^ -1
    } {}
    ?? ( __oidc_fetch_jwks p h ) { T _ → { ^ -1 } F _ → {} }
    : i idx2 ( jwks_select ( arc_get [( Vec JwkKey )] ( _oidc_keys h ) ) kid alg )
    ? < idx2 0 { ( _oidc_err2 p `no key for kid ` kid ) } {}
    ^ idx2
}

// The key set as it is now, and the index of the first key in it the
// (kid, alg) pair admits — fetching or re-fetching the JWKS when that is
// what it takes; -1 when the provider has no such key. The signature is
// checked against the snapshot outside the lock.
: OidcCands { ( Arc ( Vec JwkKey ) ) keys i first }

@ __oidc_candidates OidcProvider h s kid s alg → OidcCands {
    // The common case: the key is in the set already, and nothing waits on
    // the provider's state.
    : ~ ( Arc ( Vec JwkKey ) ) keys ( _oidc_keys h )
    : ~ i first ( jwks_select ( arc_get [( Vec JwkKey )] keys ) kid alg )
    ? < first 0 {
        : ~ OidcProviderImpl p ( locked_take [OidcProviderImpl] . h st )
        = first ( __oidc_ensure_key p h kid alg )
        ( locked_restore [OidcProviderImpl] . h st p )
        = keys ( _oidc_keys h )
    } {}
    ^ @ OidcCands { keys first }
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

@ _oidc_verify_at OidcProvider p__h OidcPolicy pol__h s token i now b access → !OidcIdentity OauthErr {
    // One copy of the policy for every rule this verification applies.
    : ( Arc OidcPolicyImpl ) pol_now ( _oidc_policy_now pol__h )
    : OidcPolicyImpl pol ( arc_get [OidcPolicyImpl] pol_now )
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
            ( _oidc_err_h p__h `not a well-formed JWS` )
            ^ @ !OidcIdentity OauthErr { F # OauthErr e }
        }
    }
    : s algp ( string_data alg )
    : s kidp ( string_data kid )

    // RFC 7515 §4.1.1: `alg` is REQUIRED in the header.
    ? == 0 ( string_len alg ) {
        ( _oidc_err_h p__h `JOSE header has no alg` )
        ^ @ !OidcIdentity OauthErr { F OaBadToken }
    } {}
    ? ( jws_alg_supported algp ) {} {
        ( _oidc_err2_h p__h `unsupported alg: ` algp )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    ? ( _oidc_policy_alg_allowed pol algp ) {} {
        ( _oidc_err2_h p__h `alg not in policy allowlist: ` algp )
        ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
    }
    // A published key set holds PUBLIC keys. Verifying an HS* token
    // against one turns a public key into a shared secret — the key
    // confusion attack — so symmetric algorithms need an explicit opt-in.
    ? ( jws_alg_symmetric algp ) {
        ? . pol allow_symmetric {} {
            ( _oidc_err2_h p__h `symmetric alg refused: ` algp )
            ^ @ !OidcIdentity OauthErr { F OaAlgNotAllowed }
        }
    } {}

    // Try EVERY key the (kid, alg) pair admits, not just the first. With
    // no `kid` in the header — which is legal — a provider mid-rotation
    // publishes two keys of the same type, and only one of them signed
    // this token.
    : OidcCands cands ( __oidc_candidates p__h kidp algp )
    ? < . cands first 0 {
        ^ @ !OidcIdentity OauthErr { F OaNoKey }
    } {}
    : ( Vec JwkKey ) keys ( arc_get [( Vec JwkKey )] . cands keys )
    : ~ Json claims ( json_null )
    : ~ b verified F
    : ~ i from . cands first
    ~ >= from 0 {
        : i k ( jwks_select_from keys kidp algp from )
        ? < k 0 { = from -1 } {
            ?? ( jws_verify_with_key ( vec_at [JwkKey] keys k ) token ) {
                T c → {
                    = claims c
                    = verified T
                    = from -1
                }
                F _ → { = from + k 1 }
            }
        }
    }
    ? verified {} {
        ( _oidc_err_h p__h `signature did not verify under any published key` )
        ^ @ !OidcIdentity OauthErr { F OaBadSignature }
    }
    ?? ( _claims_check_with claims pol now access ) {
        T ce → {
            ( _oidc_err_h p__h ( claim_err_desc # ClaimErr ce ) )
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
