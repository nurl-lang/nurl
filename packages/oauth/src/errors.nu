// oauth/errors.nu — one error type for the whole package.
//
// Discovery, JWKS fetching, token-endpoint calls, signature checking and
// claim validation all fold into `OauthErr`, so a caller writes one
// `?? … { T id → … F e → ( oauth_err_name e ) }` and is done. The
// human-readable detail that does not fit an enum — the OAuth server's
// own `error_description`, the claim that failed — is carried on the
// provider (`oidc_provider_last_error`), set by whichever call failed.

: | OauthErr {
    OaNetwork  // could not connect / the transport failed
    OaHttpStatus  // an endpoint answered non-2xx (detail in last_error)
    OaBadResponse  // the body was not the JSON this endpoint must return
    OaIssuerMismatch  // discovery doc's `issuer` ≠ the issuer we asked for
    OaNoJwks  // the provider publishes no usable key set
    OaNoKey  // no JWK matched the token's kid / alg
    OaBadToken  // not a well-formed JWS / claims are not an object
    OaBadSignature  // the signature did not verify under the chosen key
    OaAlgNotAllowed  // header `alg` is unsupported or outside the policy
    OaClaims  // a claim check failed (detail in last_error)
    OaServer  // the endpoint returned an OAuth error response
    OaState  // the redirect's `state` is not the one we sent
    OaConfig  // caller misconfiguration — a required endpoint/field is unset
}

@ oauth_err_name OauthErr e → s {
    ^ ?? e {
        OaNetwork → `OaNetwork`
        OaHttpStatus → `OaHttpStatus`
        OaBadResponse → `OaBadResponse`
        OaIssuerMismatch → `OaIssuerMismatch`
        OaNoJwks → `OaNoJwks`
        OaNoKey → `OaNoKey`
        OaBadToken → `OaBadToken`
        OaBadSignature → `OaBadSignature`
        OaAlgNotAllowed → `OaAlgNotAllowed`
        OaClaims → `OaClaims`
        OaServer → `OaServer`
        OaState → `OaState`
        OaConfig → `OaConfig`
    }
}

// The RFC 6750 §3.1 `error=` token a resource server puts in its
// WWW-Authenticate challenge for this failure.
@ oauth_err_bearer_code OauthErr e → s {
    ^ ?? e {
        OaNetwork → `temporarily_unavailable`
        OaHttpStatus → `temporarily_unavailable`
        OaBadResponse → `temporarily_unavailable`
        OaIssuerMismatch → `invalid_token`
        OaNoJwks → `temporarily_unavailable`
        OaNoKey → `invalid_token`
        OaBadToken → `invalid_token`
        OaBadSignature → `invalid_token`
        OaAlgNotAllowed → `invalid_token`
        OaClaims → `invalid_token`
        OaServer → `invalid_token`
        OaState → `invalid_request`
        OaConfig → `temporarily_unavailable`
    }
}
