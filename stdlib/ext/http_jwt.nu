// stdlib/ext/http_jwt.nu — JWT bearer-auth middleware for the HTTP stack.
//
// Bridges ext/jwt.nu (HS256 / EdDSA verify) and the HTTP server's
// middleware convention. A wrapped route only runs when the request
// carries a valid `Authorization: Bearer <token>`; the verified payload
// claims are handed straight to the handler, so it never re-parses or
// re-verifies. Invalid / missing / expired / not-yet-valid tokens get a
// 401 with a `WWW-Authenticate: Bearer` challenge (RFC 6750 §3) whose
// `error=` code names the failure.
//
// Lives in its own module so the base ext/http_auth.nu (and anything
// that only wants Basic/Bearer parsing) stays free of the libcrypto /
// OpenSSL dependency that ext/jwt.nu → ext/crypto.nu pulls in. Import
// this only when you actually verify JWTs.
//
//   ( with_jwt_hs256 secret inner )  → ( @ HttpResponse HttpRequest )
//       inner : ( @ HttpResponse HttpRequest Json )
//       Verify with the shared HS256 secret; on success call
//       `( inner req claims )`. `claims` is BORROWED — the middleware
//       owns and frees it after the handler returns.
//
//   ( with_jwt_eddsa pubkey inner ) → ( @ HttpResponse HttpRequest )
//       inner : ( @ HttpResponse HttpRequest Json )
//       Same, verifying an Ed25519 signature with the 32-byte public
//       key (asymmetric: the signer holds the secret key).
//
// Both use the system clock for exp/nbf (jwt_*_verify). The returned
// wrapper is an ordinary `( @ HttpResponse HttpRequest )`, so it
// composes with with_access_log / with_cors_default / router_handle
// like any other middleware — put auth outermost.

$ `stdlib/core/string.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_auth.nu`
$ `stdlib/ext/jwt.nu`

// 401 with a Bearer challenge. `err_code` is the RFC 6750 `error=`
// token ("invalid_token") or empty for a missing credential.
@ __jwt_unauthorized s err_code s desc → HttpResponse {
    : HttpResponse r ( response_text 401 `Unauthorized\n` )
    : String chal ( string_with_cap 64 )
    ( string_push_str chal `Bearer` )
    ? > ( nurl_str_len err_code ) 0 {
        ( string_push_str chal ` error="` )
        ( string_push_str chal err_code )
        ( string_push_char chal 34 )  // '"'
        ? > ( nurl_str_len desc ) 0 {
            ( string_push_str chal `, error_description="` )
            ( string_push_str chal desc )
            ( string_push_char chal 34 )
        } {}
    } {}
    ( response_set_header r `WWW-Authenticate` ( string_data chal ) )
    ( string_free chal )
    ^ r
}

// Map a JwtErr to its RFC 6750 error_description text.
@ __jwt_err_desc JwtErr e → s {
    ^ ?? e {
        JwtMalformed → `malformed token`
        JwtBadSignature → `bad signature`
        JwtExpired → `token expired`
        JwtNotYetValid → `token not yet valid`
        JwtUnsupportedAlg → `unsupported alg`
        JwtBadClaims → `bad claims`
    }
}

// Shared dispatch: given an already-computed verify result, either run
// the claims-aware handler (freeing the claims afterward) or render the
// 401. `tok_present` distinguishes a missing credential (no
// `error=`, per RFC 6750 §3.1) from an invalid one.
@ __jwt_gate ! Json JwtErr vr HttpRequest req ( @ HttpResponse HttpRequest Json ) inner → HttpResponse {
    ^ ?? vr {
        T claims → {
            : HttpResponse resp ( inner req claims )
            ( json_free claims )
            ^ resp
        }
        F e → ( __jwt_unauthorized `invalid_token` ( __jwt_err_desc # JwtErr e ) )
    }
}

@ with_jwt_hs256 s secret ( @ HttpResponse HttpRequest Json ) inner → ( @ HttpResponse HttpRequest ) {
    : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
        : ?String tok ( parse_bearer_auth req )
        ^ ?? tok {
            T t → {
                : !Json JwtErr vr ( jwt_hs256_verify secret ( string_data t ) )
                ( string_free t )
                ^ ( __jwt_gate vr req inner )
            }
            F _ → ( __jwt_unauthorized `` `` )
        }
    }
    ^ wrapped
}

@ with_jwt_eddsa ( Vec u ) pubkey ( @ HttpResponse HttpRequest Json ) inner → ( @ HttpResponse HttpRequest ) {
    : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
        : ?String tok ( parse_bearer_auth req )
        ^ ?? tok {
            T t → {
                : !Json JwtErr vr ( jwt_eddsa_verify pubkey ( string_data t ) )
                ( string_free t )
                ^ ( __jwt_gate vr req inner )
            }
            F _ → ( __jwt_unauthorized `` `` )
        }
    }
    ^ wrapped
}
