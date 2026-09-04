# oauth — OAuth 2.0 and OpenID Connect for NURL

Identify the user, and read the claims.

This package is an OpenID Connect relying party and a resource-server
guard, in pure NURL. Nothing in the chain is C: the TLS is
`std/tls.nu`, the JSON is `ext/json.nu`, and the RSA, ECDSA, Ed25519 and
SHA-2 that decide whether a token is real are `std/rsa.nu`,
`std/ecdsa_p256.nu`, `std/ed25519.nu` and `std/hash_sha*.nu`.

```nurl
$ `deps/oauth/src/oauth.nu`
```

## The two halves

**Get a token** — the authorization-code flow with PKCE:

```nurl
?? ( oidc_provider_discover `https://accounts.example.com` ) {
    T p → {
        : *OauthConfig cfg ( oauth_config_new `my-client` `http://127.0.0.1:8765/callback` `openid profile email` )
        : Pkce pk ( pkce_new )
        : String state ( oauth_state_new )
        : String nonce ( oauth_nonce_new )

        : String url ( oauth_authorize_url p cfg ( string_data state ) ( string_data nonce ) pk )
        //  … open `url` in a browser, catch the redirect …

        ?? ( oauth_callback_code query ( string_data state ) ) {
            T code → {
                ?? ( oauth_exchange_code p cfg ( string_data code ) ( string_data . pk verifier ) ) {
                    T ts → { /* ( token_set_id_token ts ) */ }
                    F e → { /* ( oauth_err_name e ), ( oidc_provider_last_error p ) */ }
                }
            }
            F e → {}
        }
    }
    F e → {}
}
```

**Believe a token** — and turn it into a person:

```nurl
: *OidcPolicy pol ( oidc_policy_new `https://accounts.example.com` `my-client` )
( oidc_policy_set_nonce pol ( string_data nonce ) )

?? ( oidc_verify_id_token p pol ( token_set_id_token ts ) ) {
    T id → {
        ( nurl_println ( string_data . id subject ) )   // "248289761001"
        ( nurl_println ( string_data . id email ) )     // "jane@example.com"
        : String groups ( oidc_identity_claim id `tenant` )   // anything else
        ( oidc_identity_free id )
    }
    F e → { /* ( oauth_err_name e ) + ( oidc_provider_last_error p ) says why */ }
}
```

**Guard an API** with the tokens it hands out:

```nurl
: HttpServer srv ( server_new listener
    ( with_oidc_scope p pol `read:things`
        \ HttpRequest req OidcIdentity id → HttpResponse {
            ^ ( response_text 200 ( string_data ( oidc_identity_key id ) ) )
        } ) )
```

A handler wrapped this way is entered only for a caller the package could
name. Everything else — no token, an expired one, one from another
issuer, one minted for another audience, one signed with a key the
provider never published, one that says `alg: none` — is a 401 with an
RFC 6750 challenge that names the reason. A caller who is who they say
but lacks the scope gets 403 `insufficient_scope`, because that is a
different answer. What the challenge quotes back is sanitized before it
becomes a header value — part of that text is copied from the token, and
a `kid` carrying a CR LF is response splitting, not a diagnostic.

## What it checks, and why

| Check | What it stops |
| --- | --- |
| `iss` matches the discovery document's own `issuer` | metadata substitution — a redirect that repoints the token endpoint |
| `aud` contains our client id | the confused deputy: a token minted for another relying party |
| `azp` is us when it is present | the same, when the token has several audiences |
| `exp` / `nbf` / `iat`, with leeway | replay of a dead token; a token from the future |
| `nonce` equals the one we sent | replay of a valid ID token into a session we started |
| `sub` is present | a "user" with no identity |
| `max_age` against `auth_time` | a session older than this relying party accepts |
| header `kid` → a published key | a token signed by anything but the provider |
| `alg` against the key type | key confusion (verifying an RSA token on the HMAC path) |
| `alg: none` refused | the oldest JWT break there is |
| unknown `crit` refused | an extension we do not implement, silently ignored |
| HS\* refused against a JWKS unless opted in | a public key used as a shared secret |
| PKCE `S256`, never `plain` | a stolen authorization code |
| `state` on the callback | login CSRF |

Key **rotation** is handled: a `kid` the cache has never seen triggers a
JWKS re-fetch, rate-limited (`oidc_provider_set_min_refetch`, 300 s by
default) so a flood of forged `kid`s cannot be turned into a load
generator aimed at the provider.

## Modules

| File | What is in it |
| --- | --- |
| `src/errors.nu` | `OauthErr`, `oauth_err_name`, the RFC 6750 error code for each |
| `src/jwk.nu` | `JwkKey`, `jwks_parse` / `jwks_from_json`, `jwks_select`, `jwk_ec_point`, `jwk_thumbprint` (RFC 7638) |
| `src/jws.nu` | `jws_verify_with_key`, `jws_header_json` / `jws_header_str`, `jws_payload_unverified`, `jws_alg_supported` |
| `src/claims.nu` | `OidcPolicy` + setters, `claims_check`, `claim_err_desc`, the claim accessors, `OidcIdentity` |
| `src/pkce.nu` | `pkce_new`, `pkce_challenge_for`, `oauth_state_new`, `oauth_nonce_new`, `oauth_random_token` |
| `src/provider.nu` | `oidc_provider_discover` / `oidc_discover`, `oidc_fetch_jwks`, `oidc_verify_id_token` / `_access_token` / `_token_at` |
| `src/flow.nu` | `OauthConfig`, `oauth_authorize_url`, `oauth_callback_code`, `oauth_exchange_code`, `oauth_refresh`, `oauth_client_credentials`, `oauth_userinfo`, `TokenSet` |
| `src/guard.nu` | `with_oidc_bearer`, `with_oidc_scope`, `oidc_request_identity` |
| `src/oauth.nu` | the facade — include this one |

### Algorithms

`RS256` `RS384` `RS512` (PKCS#1 v1.5) · `PS256` (PSS) · `ES256` `ES384`
(ECDSA over P-256 / P-384) · `EdDSA` (Ed25519) · `HS256` (only against a
key the caller configured as a shared secret, with
`oidc_policy_allow_symmetric`).

`oidc_policy_set_algs` narrows that to an explicit allowlist — worth
doing when you know your provider only ever signs one way.

## Examples

```sh
# Log in with a browser and print who logged in.
./login --issuer https://accounts.example.com --client-id <id>

# Is this token real, and who does it name? (exit 0 = valid)
./verify --issuer https://accounts.example.com --audience <id> --token "$JWT"

# An HTTP API that only answers callers it can name.
./protected-api --issuer https://accounts.example.com \
                --audience my-api --scope read:things --port 8080
```

## Tests

```sh
./tests/oauth_test.sh
```

`tests/provider.nu` is a small but real OpenID Connect provider: it
publishes discovery metadata and a JWKS, mints ES256-signed ID and
access tokens with a `kid`, and genuinely verifies PKCE on the token
request (its authorization code carries the challenge and nonce the
authorization request committed to, which is what a real provider keeps
in a session store). `tests/client.nu` drives the whole package against
it, and `/mint/<kind>` hands out the deliberately broken tokens — expired,
tampered, wrong audience, unpublished `kid`, `alg: none`, HS256 signed
with the public key — that the verifier must refuse, each asserted to
fail for the *right* reason.

Offline, RS256 and PS256 are checked against tokens minted by OpenSSL
with an RSA-2048 key, so the pure-NURL RSA path is proven to agree with
an independent implementation rather than with itself; EdDSA and HS256
are round-tripped through the stdlib; and PKCE is checked against RFC
7636's own S256 vector. The last step of the script runs
`examples/protected_api.nu` as a live API and drives it with curl: 401
without a token, 200 with a good one, 403 for a valid token without the
scope, and the challenge naming `invalid_token` on a bad one — and a token whose
`kid` carries a CR LF, to prove the challenge cannot be turned into a
header of the attacker's choosing.

The suite (95 in-process assertions + 10 over curl) is clean under
AddressSanitizer + UndefinedBehaviorSanitizer with LeakSanitizer on.

## Threading

An `*OidcProvider` owns an HTTP client and a mutable key cache and takes
no lock: one per thread, or one thread that owns it. An `*OidcPolicy` is
read-only once built and is safe to share, as is a verified
`OidcIdentity` — it is a value with no back-reference to the provider.

## Not in this version

Device authorization grant (RFC 8628), dynamic client registration
(RFC 7591), token introspection and revocation calls (the endpoints are
discovered and exposed, but not driven), JWE-encrypted tokens, ES512 /
P-521 (the stdlib has no P-521), and back-channel logout. The
`end_session_endpoint` is discovered so a caller can build an RP-initiated
logout URL itself.
