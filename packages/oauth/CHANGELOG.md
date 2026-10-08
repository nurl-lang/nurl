# Changelog

## [0.2.2] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.1 does
not compile under 0.71.0.

## [0.2.1] — 2026-10-04

### Fixed

- **An access token requested by another client was refused.**
  `oidc_verify_access_token` applied the ID-token rule of OIDC Core
  §3.1.3.7 — `azp`, when present, must be our own client — to access
  tokens, where `azp` names the client that ASKED for the token (an MCP
  client, a CLI, a single-page app) and is never the resource server. A
  resource server therefore accepted only the tokens its own app
  registration fetched: an Entra token for the API obtained with
  `az account get-access-token --scope <api>/access_as_user` failed with
  "wrong authorized party (azp)". Access tokens are now checked by
  `claims_check_access` (audience, issuer, expiry, … — everything but
  `azp`), and the new `oidc_verify_access_token_at` is the explicit-clock
  form. ID-token verification (`oidc_verify_token[_at]`,
  `oidc_verify_id_token`, `claims_check`) is unchanged.

## [0.2.0] — 2026-10-03

Nothing is released by hand any more.

### Changed (breaking)

- `OidcProvider`, `OidcPolicy` and `OauthConfig` are handles over an rcbox
  instead of `*OidcProvider` / `*OidcPolicy` / `*OauthConfig` pointers: every
  copy (a struct field, a closure capture, `*_share`) is the same object, and
  the last owner releases it — the provider's HTTP client and key cache with
  it. `oidc_provider_discover` returns `!OidcProvider OauthErr` (was
  `!*OidcProvider OauthErr`); every function that took a pointer takes the
  handle. `with_oidc_bearer` / `with_oidc_scope` closures hold a share of the
  provider and the policy.
- A provider field read through `. p issuer` no longer reaches the state; use
  the new accessors (below).
- `oidc_provider_http` returns the provider's `HttpClient` handle
  (http-client 0.3).
- `oauth_config_free`, `token_set_free`, `callback_params_free`, `pkce_free`,
  `jwk_free`, `jwks_free` and `claims_strings_free` are removed: `OidcIdentity`,
  `TokenSet`, `CallbackParams`, `Pkce` and `JwkKey` are plain values dropped
  with their binding. `oidc_provider_free`, `oidc_policy_free` and
  `oidc_identity_free` remain as optional early releases.

### Added

- Accessors for what discovery found: `oidc_provider_issuer`,
  `_authorization_endpoint`, `_token_endpoint`, `_userinfo_endpoint`,
  `_jwks_uri`, `_end_session_endpoint`, `_device_authorization_endpoint`,
  `_introspection_endpoint`, `_revocation_endpoint`.

### Changed

- The setters, discovery and the error text replace a String in place, and a
  new key set replaces the cached one's elements, instead of storing over the
  field. The package's own code, tests and examples call no release function.

### Performance

- Verifying an ES256 access token against a pinned key set: same answer, two
  allocations fewer per verify-and-refuse pair, instructions:u +0.04 %
  (link-layout noise in the P-256 code).

Requires NURL 0.69.0 and http-client 0.3.

## 0.1.1

`callback_params_free`, `claims_strings_free`, `jwk_free`, `jwks_free`, `oauth_config_free`, `oidc_identity_free` and 4 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
