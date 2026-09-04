// oauth — OAuth 2.0 and OpenID Connect for NURL: identify the user,
// read the claims.
//
// One include gives a program both halves of an OpenID Connect relying
// party, with no C dependency anywhere in the chain — the TLS, the JSON,
// the RSA/ECDSA/Ed25519 signature checks and the SHA-2 under them are
// all pure NURL:
//
//   $ `deps/oauth/src/oauth.nu`
//
// ── Log a user in ──────────────────────────────────────────────────
//
//   ?? ( oidc_provider_discover `https://accounts.example.com` ) {
//       T p → {
//           : *OauthConfig cfg ( oauth_config_new client_id redirect scope )
//           : Pkce pk ( pkce_new )
//           : String state ( oauth_state_new )
//           : String nonce ( oauth_nonce_new )
//           : String url ( oauth_authorize_url p cfg
//                            ( string_data state ) ( string_data nonce ) pk )
//           //  … send the browser to `url`, receive the redirect …
//           ?? ( oauth_callback_code query ( string_data state ) ) {
//               T code → {
//                   ?? ( oauth_exchange_code p cfg ( string_data code )
//                            ( string_data . pk verifier ) ) {
//                       T ts → {
//                           : *OidcPolicy pol ( oidc_policy_new issuer client_id )
//                           ( oidc_policy_set_nonce pol ( string_data nonce ) )
//                           ?? ( oidc_verify_id_token p pol ( token_set_id_token ts ) ) {
//                               T id → { /* . id subject — the user */ }
//                               F e → { /* ( oauth_err_name e ) */ }
//                           }
//                       }
//                       F e → {}
//                   }
//               }
//               F e → {}
//           }
//       }
//       F e → {}
//   }
//
// ── Guard an API with the tokens it hands out ──────────────────────
//
//   ( http_app_get a `/me` ( with_oidc_bearer p pol
//       \ HttpRequest req OidcIdentity id → HttpResponse {
//           ^ ( response_json 200 ( string_data ( oidc_identity_key id ) ) ) } ) )
//
// ── What is in here ────────────────────────────────────────────────
//
//   errors.nu    OauthErr — one error type for the whole package
//   jwk.nu       JWK / JWKS: parse a key set, pick the key a token names
//   jws.nu       verify a JWT against a JWK — RS256/384/512, PS256,
//                ES256/384, EdDSA, HS256; `none` and `crit` refused
//   claims.nu    OidcPolicy, claims_check (iss/aud/azp/exp/nbf/iat/
//                nonce/sub/max_age), the claim accessors, OidcIdentity
//   pkce.nu      PKCE verifier + S256 challenge, state, nonce
//   provider.nu  discovery, the JWKS cache with rotation-driven
//                re-fetch, and oidc_verify_id_token
//   flow.nu      authorize URL, callback, code exchange, refresh,
//                client_credentials, UserInfo
//   guard.nu     with_oidc_bearer / with_oidc_scope for the HTTP server
//
// ── What it will not do ────────────────────────────────────────────
//
// There is no "just decode the token" convenience that skips
// verification, no `alg: none`, no HS256 against a published (public)
// key set unless the caller explicitly says the key is a shared secret,
// and no PKCE `plain`. Each of those is a real attack that a helpful
// default has shipped before; none of them is a feature.

$ `errors.nu`
$ `jwk.nu`
$ `jws.nu`
$ `claims.nu`
$ `pkce.nu`
$ `provider.nu`
$ `flow.nu`
$ `guard.nu`
