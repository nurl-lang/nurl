// oauth/jws.nu — verify a compact JWS (a JWT) against a JWK.
//
// The stdlib's ext/jwt.nu signs and verifies with a key you already
// hold, for the three algorithms it chose to support. An OpenID Connect
// relying party has the opposite problem: the token arrives first and
// names its own key (`kid`) and algorithm (`alg`) in the header, and the
// key comes from the provider's JWKS. This module is that direction —
// header-driven verification over the whole algorithm set providers
// actually publish:
//
//   RS256 · RS384 · RS512   RSASSA-PKCS1-v1_5 (std/rsa.nu)
//   PS256                   RSASSA-PSS
//   ES256 · ES384           ECDSA over P-256 / P-384 (std/ecdsa_p256.nu)
//   EdDSA                   Ed25519 (std/ed25519.nu)
//   HS256                   HMAC-SHA-256, for a shared-secret `oct` key
//
//   ( jws_verify_with_key jk token )   → !Json OauthErr   owned claims
//   ( jws_header_json token )          → !Json OauthErr   owned header
//   ( jws_header_str token key )       → String           "" when absent
//   ( jws_payload_unverified token )   → !Json OauthErr
//
// `alg: none` is refused — it is not an algorithm, it is the absence of
// one, and every historical JWT break starts there. So is an `alg` the
// key cannot possibly carry: the key type is checked against the family
// before the signature is touched (jwk_matches), which is what stops the
// classic "verify an RSA-signed token with the HMAC path" confusion.
//
// The claims come back as an owned `Json` object; time and issuer/
// audience checks are NOT done here (claims.nu owns that), so a caller
// can inspect an expired token deliberately.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/ext/json.nu`
$ `errors.nu`
$ `jwk.nu`

// ── Segments ───────────────────────────────────────────────────────

// Byte index of the n-th (0-based) '.' in `s`, or -1.
@ __jws_dot_at s str i n → i {
    : i len ( nurl_str_len str )
    : ~ i seen 0
    : ~ i k 0
    ~ < k len {
        ? == ( nurl_str_get str k ) 46 {
            ? == seen n { ^ k } {}
            = seen + seen 1
        } {}
        = k + k 1
    }
    ^ -1
}

@ __jws_slice s str i a i b → String {
    : String out ( string_with_cap + 1 - b a )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( nurl_str_get str k ) )
        = k + k 1
    }
    ^ out
}

// A compact JWS is exactly three base64url segments. Reports the two dot
// positions through `slots` (index 0 and 1); F when the shape is wrong.
@ __jws_dots s token ( Vec i ) slots → b {
    : i d0 ( __jws_dot_at token 0 )
    : i d1 ( __jws_dot_at token 1 )
    : i d2 ( __jws_dot_at token 2 )
    : i tlen ( nurl_str_len token )
    ? < d0 1 { ^ F } {}
    ? <= d1 + d0 1 { ^ F } {}
    ? >= d2 0 { ^ F } {}
    // The signature segment MAY be empty: that is the "unsecured JWS"
    // of RFC 7515 §6, structurally valid and refused on its `alg`, which
    // is a more useful answer than calling it malformed.
    ? > + d1 1 tlen { ^ F } {}
    ( vec_push [i] slots d0 )
    ( vec_push [i] slots d1 )
    ^ T
}

// base64url segment [a,b) → an owned JSON object.
@ __jws_json_seg s token i a i b → !Json OauthErr {
    : String seg ( __jws_slice token a b )
    : !( Vec u ) ParseErr dec ( b64_url_decode_vec ( string_data seg ) )
    ( string_free seg )
    ?? dec {
        T raw → {
            : !Json JsonError pj ( json_parse_bytes raw )
            ( vec_free [u] raw )
            ?? pj {
                T j → {
                    ? ( json_is_obj j ) {} {
                        ( json_free j )
                        ^ @ !Json OauthErr { F OaBadToken }
                    }
                    ^ @ !Json OauthErr { T j }
                }
                F _ → { ^ @ !Json OauthErr { F OaBadToken } }
            }
        }
        F _ → { ^ @ !Json OauthErr { F OaBadToken } }
    }
}

@ jws_header_json s token → !Json OauthErr {
    : ( Vec i ) slots ( vec_new [i] )
    ? ( __jws_dots token slots ) {} {
        ( vec_free [i] slots )
        ^ @ !Json OauthErr { F OaBadToken }
    }
    : i d0 ?? ( vec_get [i] slots 0 ) { T v → v F _ → 0 }
    ( vec_free [i] slots )
    ^ ( __jws_json_seg token 0 d0 )
}

@ jws_payload_unverified s token → !Json OauthErr {
    : ( Vec i ) slots ( vec_new [i] )
    ? ( __jws_dots token slots ) {} {
        ( vec_free [i] slots )
        ^ @ !Json OauthErr { F OaBadToken }
    }
    : i d0 ?? ( vec_get [i] slots 0 ) { T v → v F _ → 0 }
    : i d1 ?? ( vec_get [i] slots 1 ) { T v → v F _ → 0 }
    ( vec_free [i] slots )
    ^ ( __jws_json_seg token + d0 1 d1 )
}

// A string member of an already-parsed JOSE header / claims object.
@ _jws_json_str Json j s key → String {
    : ~ s raw ``
    ?? ( json_obj_get j key ) {
        T v → { ? ( json_is_str v ) { = raw ( json_str_data v ) } {} }
        F _ → {}
    }
    ^ ( string_from raw )
}

// A string member of the JOSE header — `alg`, `kid`, `typ`. Empty when
// the token is malformed or the member is absent. Reading the header is
// how a verifier learns which key to fetch; it is never trusted beyond
// that, because the signature has not been checked yet.
@ jws_header_str s token s key → String {
    ?? ( jws_header_json token ) {
        T h → {
            : String out ( _jws_json_str h key )
            ( json_free h )
            ^ out
        }
        F _ → { ^ ( string_new ) }
    }
}

// ── Algorithms ─────────────────────────────────────────────────────

@ jws_alg_supported s alg → b {
    ? == 1 ( nurl_str_eq alg `RS256` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `RS384` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `RS512` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `PS256` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `ES256` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `ES384` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `EdDSA` ) { ^ T } {}
    ? == 1 ( nurl_str_eq alg `HS256` ) { ^ T } {}
    ^ F
}

// Is `alg` a symmetric (shared-secret) algorithm? A relying party that
// verifies with a PUBLISHED key set must refuse these unless it really
// did configure a shared secret — accepting HS* against a JWKS is the
// key-confusion attack.
@ jws_alg_symmetric s alg → b {
    ^ == 1 ( nurl_str_starts alg `HS` )
}

// The digest the algorithm signs over.
@ __jws_digest s alg ( Vec u ) msg → ( Vec u ) {
    ? == 1 ( nurl_str_ends alg `384` ) { ^ ( sha384_pure msg ) } {}
    ? == 1 ( nurl_str_ends alg `512` ) { ^ ( sha512_pure msg ) } {}
    ^ ( sha256_pure msg )
}

@ __jws_rsa_di s alg → ( Vec u ) {
    ? == 1 ( nurl_str_ends alg `384` ) { ^ ( rsa_di_sha384 ) } {}
    ? == 1 ( nurl_str_ends alg `512` ) { ^ ( rsa_di_sha512 ) } {}
    ^ ( rsa_di_sha256 )
}

// ── Signature check ────────────────────────────────────────────────

@ __jws_check_rsa JwkKey jk s alg ( Vec u ) sig ( Vec u ) digest → b {
    ? == 0 ( vec_len [u] . jk n ) { ^ F } {}
    ? == 0 ( vec_len [u] . jk e ) { ^ F } {}
    ? == 1 ( nurl_str_starts alg `PS` ) {
        ^ ( rsa_pss_verify_sha256 . jk n . jk e sig digest )
    } {}
    : ( Vec u ) di ( __jws_rsa_di alg )
    : b ok ( rsa_pkcs1_verify . jk n . jk e sig di digest )
    ( vec_free [u] di )
    ^ ok
}

@ __jws_check_ec JwkKey jk s alg ( Vec u ) sig ( Vec u ) digest → b {
    : i width ? == 1 ( nurl_str_eq alg `ES384` ) 48 32
    ? != ( vec_len [u] sig ) * 2 width { ^ F } {}
    : ( Vec u ) point ( jwk_ec_point jk )
    ? == 0 ( vec_len [u] point ) { ( vec_free [u] point ) ^ F } {}
    : ( Vec u ) r ( bytes_slice sig 0 width )
    : ( Vec u ) s ( bytes_slice sig width * 2 width )
    : ~ b ok F
    ? == width 48 {
        = ok ( ecdsa_p384_verify point r s digest )
    } {
        = ok ( ecdsa_p256_verify point r s digest )
    }
    ( vec_free [u] point )
    ( vec_free [u] r )
    ( vec_free [u] s )
    ^ ok
}

// Verify `token` under `jk`. The key must already have been chosen for
// this token's kid/alg (jwks_select) — this re-checks the type/curve
// agreement anyway, because a verifier that trusts its caller's key
// choice is one refactor away from key confusion.
@ jws_verify_with_key JwkKey jk s token → !Json OauthErr {
    : ( Vec i ) slots ( vec_new [i] )
    ? ( __jws_dots token slots ) {} {
        ( vec_free [i] slots )
        ^ @ !Json OauthErr { F OaBadToken }
    }
    : i d0 ?? ( vec_get [i] slots 0 ) { T v → v F _ → 0 }
    : i d1 ?? ( vec_get [i] slots 1 ) { T v → v F _ → 0 }
    ( vec_free [i] slots )

    // 1. header → alg
    : !Json OauthErr hj ( __jws_json_seg token 0 d0 )
    : ~ String alg ( string_new )
    : ~ b crit F
    ?? hj {
        T h → {
            ( string_free alg )
            = alg ( _jws_json_str h `alg` )
            // RFC 7515 §4.1.11: a `crit` member names extensions the
            // verifier MUST understand. We implement none, so any `crit`
            // at all is a refusal — never a silent ignore.
            ? ( json_obj_has h `crit` ) { = crit T } {}
            ( json_free h )
        }
        F e → { ( string_free alg ) ^ @ !Json OauthErr { F # OauthErr e } }
    }
    ? crit {
        ( string_free alg )
        ^ @ !Json OauthErr { F OaAlgNotAllowed }
    } {}
    : s algp ( string_data alg )
    ? ( jws_alg_supported algp ) {} {
        ( string_free alg )
        ^ @ !Json OauthErr { F OaAlgNotAllowed }
    }
    ? ( jwk_matches jk `` algp ) {} {
        ( string_free alg )
        ^ @ !Json OauthErr { F OaNoKey }
    }

    // 2. signature over ASCII( header '.' payload )
    : String signing ( __jws_slice token 0 d1 )
    : String sig64 ( __jws_slice token + d1 1 ( nurl_str_len token ) )
    : !( Vec u ) ParseErr sd ( b64_url_decode_vec ( string_data sig64 ) )
    ( string_free sig64 )
    : ~ b ok F
    ?? sd {
        T sig → {
            : ( Vec u ) msg ( bytes_from_str ( string_data signing ) )
            ? ( jws_alg_symmetric algp ) {
                ? > ( vec_len [u] . jk oct ) 0 {
                    : ( Vec u ) mac ( hmac_sha256_pure . jk oct msg )
                    = ok ( constant_time_eq_vec mac sig )
                    ( vec_free [u] mac )
                } {}
            } {
                : ( Vec u ) digest ( __jws_digest algp msg )
                ? == 1 ( nurl_str_eq algp `EdDSA` ) {
                    ? & == ( vec_len [u] . jk x ) 32 == ( vec_len [u] sig ) 64 {
                        = ok ( ed25519_verify_pure . jk x msg sig )
                    } {}
                } {
                    ? == 1 ( nurl_str_starts algp `ES` ) {
                        = ok ( __jws_check_ec jk algp sig digest )
                    } {
                        = ok ( __jws_check_rsa jk algp sig digest )
                    }
                }
                ( vec_free [u] digest )
            }
            ( vec_free [u] msg )
            ( vec_free [u] sig )
        }
        F _ → {}
    }
    ( string_free signing )
    ( string_free alg )
    ? ok {} { ^ @ !Json OauthErr { F OaBadSignature } }

    // 3. claims
    ^ ( __jws_json_seg token + d0 1 d1 )
}
