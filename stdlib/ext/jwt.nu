// stdlib/ext/jwt.nu — JSON Web Tokens (RFC 7519), HS256 + EdDSA.
//
// A JWT is three base64url-unpadded segments joined by '.':
//   base64url(header) . base64url(payload) . base64url(signature)
// The signature covers the ASCII string `header_b64 . payload_b64`.
// This module signs and verifies the two algorithms that matter in
// practice: HS256 (HMAC-SHA256, shared secret) and EdDSA (Ed25519,
// asymmetric). RS*/ES* are intentionally omitted — Ed25519 is the
// modern asymmetric choice and avoids RSA's footguns.
//
// HS256 (symmetric — same secret signs and verifies):
//   ( jwt_hs256_sign      s secret Json claims )          → String
//   ( jwt_hs256_verify    s secret s token )              → !Json JwtErr
//   ( jwt_hs256_verify_at s secret s token i now )        → !Json JwtErr
//
// EdDSA (asymmetric — 32-byte Ed25519 keys from ext/crypto.nu):
//   ( jwt_eddsa_sign      ( Vec u ) sk Json claims )      → !String CryptoErr
//   ( jwt_eddsa_verify    ( Vec u ) pk s token )          → !Json JwtErr
//   ( jwt_eddsa_verify_at ( Vec u ) pk s token i now )    → !Json JwtErr
//
//   ( jwt_decode_unverified s token )                     → !Json JwtErr
//       Decode the payload WITHOUT checking the signature or time
//       claims. For reading `iss`/`sub`/`kid` to pick a key before
//       verifying — never trust its contents until a verify succeeds.
//
// `claims` is a JSON object the caller owns (sign stringifies it; it is
// NOT freed here). verify returns the parsed payload as an owned Json —
// the caller frees it with json_free. The header is built internally per
// algorithm, so the caller only supplies claims.
//
// Time claims: `verify` validates `exp` (reject once now ≥ exp) and
// `nbf` (reject while now < nbf) when present, against the system clock.
// `verify_at` takes an explicit epoch-seconds `now` — deterministic for
// tests and for callers with their own time source. Both are no-ops when
// the claim is absent or non-numeric. There is no built-in leeway; a
// caller needing clock-skew tolerance passes a skewed `now` to
// verify_at.
//
// The signature comparison is constant-time (std/subtle.nu) for HS256 —
// a byte-at-a-time string compare on a MAC is a forgery oracle.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/crypto.nu`

: | JwtErr {
    JwtMalformed  // not three '.'-separated segments / bad base64url
    JwtBadSignature  // signature did not verify
    JwtExpired  // now ≥ exp
    JwtNotYetValid  // now < nbf
    JwtUnsupportedAlg  // header alg not the one this verifier expects
    JwtBadClaims  // payload is not a JSON object
}

// ── Segment helpers ────────────────────────────────────────────────

// Byte index of the n-th (0-based) '.' in `s`, or -1.
@ __jwt_dot_at s str i n → i {
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

// Owned String slice [a, b) of `str`.
@ __jwt_slice s str i a i b → String {
    : String out ( string_with_cap ? > - b a 0 - b a 1 )
    : ~ i k a
    ~ < k b { ( string_push_char out ( nurl_str_get str k ) ) = k + k 1 }
    ^ out
}

// The two '.' positions of a well-formed token, written into a 2-slot
// scratch. Returns T iff exactly two dots exist and neither segment is
// empty (header, payload, signature all non-zero length).
@ __jwt_split s token s d0p s d1p → b {
    : i len ( nurl_str_len token )
    : i d0 ( __jwt_dot_at token 0 )
    : i d1 ( __jwt_dot_at token 1 )
    : i d2 ( __jwt_dot_at token 2 )
    ? < d0 0 { ^ F } {}
    ? < d1 0 { ^ F } {}
    ? >= d2 0 { ^ F } {}  // a third dot ⇒ malformed
    ? <= d0 0 { ^ F } {}  // empty header
    ? <= - d1 d0 1 { ^ F } {}  // empty payload
    ? >= + d1 1 len { ^ F } {}  // empty signature
    ( nurl_poke # s d0p 0 d0 )
    ( nurl_poke # s d1p 0 d1 )
    ^ T
}

// String → owned Vec[u] (caller's text is NUL-free ASCII here).
@ __jwt_bytes s str → ( Vec u ) {
    ^ ( bytes_from_str str )
}

// Build `header_b64 . payload_b64` (the JWS signing input) for a given
// compact header JSON + claims object. Returns an owned String.
@ __jwt_signing_input s header_json Json claims → String {
    : String payload_json ( json_stringify claims )
    : String h64 ( b64_url_encode header_json )
    : String p64 ( b64_url_encode ( string_data payload_json ) )
    : String out ( string_with_cap + + ( string_len h64 ) ( string_len p64 ) 2 )
    ( string_push_str out ( string_data h64 ) )
    ( string_push_char out 46 )
    ( string_push_str out ( string_data p64 ) )
    ( string_free h64 )
    ( string_free p64 )
    ( string_free payload_json )
    ^ out
}

// ── HS256 ──────────────────────────────────────────────────────────

@ jwt_hs256_sign s secret Json claims → String {
    : String signing ( __jwt_signing_input `{"alg":"HS256","typ":"JWT"}` claims )
    : ( Vec u ) key ( __jwt_bytes secret )
    : ( Vec u ) msg ( __jwt_bytes ( string_data signing ) )
    : ( Vec u ) mac ( hmac_sha256_pure key msg )
    : String sig64 ( b64_url_encode_vec mac )
    : String token ( string_with_cap + ( string_len signing ) + ( string_len sig64 ) 1 )
    ( string_push_str token ( string_data signing ) )
    ( string_push_char token 46 )
    ( string_push_str token ( string_data sig64 ) )
    ( vec_free [u] key )
    ( vec_free [u] msg )
    ( vec_free [u] mac )
    ( string_free sig64 )
    ( string_free signing )
    ^ token
}

// Decode the payload segment of `token` (segment 1) to its JSON object.
// Shared by every verify path AFTER the signature has been accepted (or,
// for jwt_decode_unverified, deliberately without one).
@ __jwt_payload_json s token i d0 i d1 → !Json JwtErr {
    : String p64 ( __jwt_slice token + d0 1 d1 )
    : !String ParseErr pd ( b64_url_decode ( string_data p64 ) )
    ( string_free p64 )
    ?? pd {
        T pjson → {
            : !Json JsonError pj ( json_parse ( string_data pjson ) )
            ( string_free pjson )
            ?? pj {
                T j → {
                    ? ( __jwt_is_obj j ) { ^ @ !Json JwtErr { T j } }
                    { ( json_free j ) ^ @ !Json JwtErr { F JwtBadClaims } }
                }
                F _ → { ^ @ !Json JwtErr { F JwtMalformed } }
            }
        }
        F _ → { ^ @ !Json JwtErr { F JwtMalformed } }
    }
}

// True iff `j` is a JSON object (probing for an unlikely-but-harmless
// key returns Some only for objects; the cheap structural check is
// json_obj_get on any key — but that always yields ?, so instead we
// stringify-probe: an object renders starting with '{').
@ __jwt_is_obj Json j → b {
    : String s ( json_stringify j )
    : b ok & > ( string_len s ) 0 == ( nurl_str_get ( string_data s ) 0 ) 123
    ( string_free s )
    ^ ok
}

// Validate exp / nbf against `now`. Some(err) when a time claim fails,
// None when the claims pass (or are absent / non-numeric).
@ __jwt_check_time Json payload i now → ?JwtErr {
    : ?Json exp_o ( json_obj_get payload `exp` )
    ?? exp_o {
        T expj → {
            : ?i exp_i ( json_num_as_i expj )
            ?? exp_i {
                T exp → { ? >= now exp { ^ @ ?JwtErr { T JwtExpired } } {} }
                F _ → {}
            }
        }
        F _ → {}
    }
    : ?Json nbf_o ( json_obj_get payload `nbf` )
    ?? nbf_o {
        T nbfj → {
            : ?i nbf_i ( json_num_as_i nbfj )
            ?? nbf_i {
                T nbf → { ? < now nbf { ^ @ ?JwtErr { T JwtNotYetValid } } {} }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ @ ?JwtErr { F }
}

@ jwt_hs256_verify_at s secret s token i now → !Json JwtErr {
    : s d0buf ( nurl_zalloc 8 )
    : s d1buf ( nurl_zalloc 8 )
    ? ( __jwt_split token d0buf d1buf ) {} {
        ( nurl_free d0buf ) ( nurl_free d1buf )
        ^ @ !Json JwtErr { F JwtMalformed }
    }
    : i d0 ( nurl_peek d0buf 0 )
    : i d1 ( nurl_peek d1buf 0 )
    ( nurl_free d0buf ) ( nurl_free d1buf )
    // Recompute the MAC over segments [0..d1) and base64url-encode it,
    // then constant-time compare to the presented signature segment.
    : String signing ( __jwt_slice token 0 d1 )
    : ( Vec u ) key ( __jwt_bytes secret )
    : ( Vec u ) msg ( __jwt_bytes ( string_data signing ) )
    : ( Vec u ) mac ( hmac_sha256_pure key msg )
    : String want ( b64_url_encode_vec mac )
    : i siglen - ( nurl_str_len token ) + d1 1
    : String got ( __jwt_slice token + d1 1 ( nurl_str_len token ) )
    : b sig_ok ( constant_time_eq ( string_data want ) ( string_data got ) )
    ( vec_free [u] key ) ( vec_free [u] msg ) ( vec_free [u] mac )
    ( string_free want ) ( string_free got ) ( string_free signing )
    ? sig_ok {} { ^ @ !Json JwtErr { F JwtBadSignature } }
    : !Json JwtErr pj ( __jwt_payload_json token d0 d1 )
    ?? pj {
        T payload → {
            : ?JwtErr terr ( __jwt_check_time payload now )
            ?? terr {
                T e → { ( json_free payload ) ^ @ !Json JwtErr { F e } }
                F _ → { ^ @ !Json JwtErr { T payload } }
            }
        }
        F e → { ^ @ !Json JwtErr { F e } }
    }
}

@ jwt_hs256_verify s secret s token → !Json JwtErr {
    ^ ( jwt_hs256_verify_at secret token ( now_seconds ) )
}

// ── EdDSA (Ed25519) ────────────────────────────────────────────────

@ jwt_eddsa_sign ( Vec u ) sk Json claims → !String CryptoErr {
    : String signing ( __jwt_signing_input `{"alg":"EdDSA","typ":"JWT"}` claims )
    : ( Vec u ) msg ( __jwt_bytes ( string_data signing ) )
    : !( Vec u ) CryptoErr so ( ed25519_sign sk msg )
    ( vec_free [u] msg )
    ?? so {
        T sig → {
            : String sig64 ( b64_url_encode_vec sig )
            : String token ( string_with_cap + ( string_len signing ) + ( string_len sig64 ) 1 )
            ( string_push_str token ( string_data signing ) )
            ( string_push_char token 46 )
            ( string_push_str token ( string_data sig64 ) )
            ( vec_free [u] sig )
            ( string_free sig64 )
            ( string_free signing )
            ^ @ !String CryptoErr { T token }
        }
        F e → {
            ( string_free signing )
            ^ @ !String CryptoErr { F e }
        }
    }
}

@ jwt_eddsa_verify_at ( Vec u ) pk s token i now → !Json JwtErr {
    : s d0buf ( nurl_zalloc 8 )
    : s d1buf ( nurl_zalloc 8 )
    ? ( __jwt_split token d0buf d1buf ) {} {
        ( nurl_free d0buf ) ( nurl_free d1buf )
        ^ @ !Json JwtErr { F JwtMalformed }
    }
    : i d0 ( nurl_peek d0buf 0 )
    : i d1 ( nurl_peek d1buf 0 )
    ( nurl_free d0buf ) ( nurl_free d1buf )
    : String signing ( __jwt_slice token 0 d1 )
    : String sig64 ( __jwt_slice token + d1 1 ( nurl_str_len token ) )
    : !( Vec u ) ParseErr sd ( b64_url_decode_vec ( string_data sig64 ) )
    ( string_free sig64 )
    : ~ b sig_ok F
    ?? sd {
        T sig → {
            : ( Vec u ) msg ( __jwt_bytes ( string_data signing ) )
            = sig_ok ( ed25519_verify pk msg sig )
            ( vec_free [u] msg )
            ( vec_free [u] sig )
        }
        F _ → {}
    }
    ( string_free signing )
    ? sig_ok {} { ^ @ !Json JwtErr { F JwtBadSignature } }
    : !Json JwtErr pj ( __jwt_payload_json token d0 d1 )
    ?? pj {
        T payload → {
            : ?JwtErr terr ( __jwt_check_time payload now )
            ?? terr {
                T e → { ( json_free payload ) ^ @ !Json JwtErr { F e } }
                F _ → { ^ @ !Json JwtErr { T payload } }
            }
        }
        F e → { ^ @ !Json JwtErr { F e } }
    }
}

@ jwt_eddsa_verify ( Vec u ) pk s token → !Json JwtErr {
    ^ ( jwt_eddsa_verify_at pk token ( now_seconds ) )
}

// ── Unverified decode ──────────────────────────────────────────────

@ jwt_decode_unverified s token → !Json JwtErr {
    : s d0buf ( nurl_zalloc 8 )
    : s d1buf ( nurl_zalloc 8 )
    ? ( __jwt_split token d0buf d1buf ) {} {
        ( nurl_free d0buf ) ( nurl_free d1buf )
        ^ @ !Json JwtErr { F JwtMalformed }
    }
    : i d0 ( nurl_peek d0buf 0 )
    : i d1 ( nurl_peek d1buf 0 )
    ( nurl_free d0buf ) ( nurl_free d1buf )
    ^ ( __jwt_payload_json token d0 d1 )
}
