// oauth/jwk.nu — JSON Web Key and JWK Set (RFC 7517 / RFC 7518 §6).
//
// A provider publishes its verification keys as a JWKS document:
//
//     { "keys": [ { "kty":"RSA", "kid":"a1", "alg":"RS256",
//                   "n":"<base64url>", "e":"AQAB" }, … ] }
//
// This module turns that into `( Vec JwkKey )` — the parameters already
// base64url-decoded into byte vectors, ready to hand to the verifier —
// and picks the key a token's `kid`/`alg` names.
//
//   ( jwks_parse text )              → ( Vec JwkKey )   (empty on garbage)
//   ( jwks_from_json doc )           → ( Vec JwkKey )
//   ( jwks_free ks )                 → v
//   ( jwks_select ks kid alg )       → i   index, or -1
//   ( jwk_ec_point jk )              → ( Vec u )  0x04‖X‖Y
//   ( jwk_thumbprint jk )            → String     RFC 7638, base64url
//
// A `JwkKey` is a plain value struct: the strings and vectors are owned
// by the vector that holds it, so `vec_data` + `. data k` hands out a
// BORROW that must not be freed — only `jwks_free` frees.
//
// Key selection follows RFC 7515 §4.1.4 and the OIDC core rules: a `kid`
// in the token header must match a `kid` in the set; a key that declares
// `alg` must agree with the header's; a key that declares `use` must say
// `sig`; and the key type must be the one the algorithm family needs
// (RS*/PS* → RSA, ES* → EC with the right curve, EdDSA → OKP/Ed25519,
// HS* → oct). A set with exactly one usable key is accepted even when
// the token carries no `kid` — the common single-key provider.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/json.nu`

: JwkKey {
    String kty  // "RSA" · "EC" · "OKP" · "oct"
    String kid
    String alg  // may be empty — a key that names no algorithm
    String crv  // "P-256" · "P-384" · "Ed25519"
    String usage  // the `use` member: "sig" · "enc" · empty
    ( Vec u ) n  // RSA modulus (big-endian)
    ( Vec u ) e  // RSA public exponent (big-endian)
    ( Vec u ) x  // EC x-coordinate · OKP public key
    ( Vec u ) y  // EC y-coordinate
    ( Vec u ) oct  // the `k` member: a symmetric secret (HS*)
}

// ── JSON field readers ─────────────────────────────────────────────

// A string member as an owned String; empty when absent or not a string.
@ __jwk_str Json j s key → String {
    : ~ s raw ``
    ?? ( json_obj_get j key ) {
        T v → { ? ( json_is_str v ) { = raw ( json_str_data v ) } {} }
        F _ → {}
    }
    ^ ( string_from raw )
}

// A base64url member decoded to bytes; empty when absent or malformed.
@ __jwk_b64u Json j s key → ( Vec u ) {
    : ~ s raw ``
    ?? ( json_obj_get j key ) {
        T v → { ? ( json_is_str v ) { = raw ( json_str_data v ) } {} }
        F _ → {}
    }
    ? == 0 ( nurl_str_len raw ) { ^ ( vec_new [u] ) } {}
    ?? ( b64_url_decode_vec raw ) {
        T bs → { ^ bs }
        F _ → { ^ ( vec_new [u] ) }
    }
}

// ── Lifecycle ──────────────────────────────────────────────────────

@ jwk_free JwkKey jk → v {
    ( string_free . jk kty )
    ( string_free . jk kid )
    ( string_free . jk alg )
    ( string_free . jk crv )
    ( string_free . jk usage )
    ( vec_free [u] . jk n )
    ( vec_free [u] . jk e )
    ( vec_free [u] . jk x )
    ( vec_free [u] . jk y )
    ( vec_free [u] . jk oct )
}

@ jwks_free ( Vec JwkKey ) ks → v {
    ( vec_free_with [JwkKey] ks \ JwkKey jk → v { ( jwk_free jk ) } )
}

// Append one JWK object to `out`. Returns F (and appends nothing) when
// the node is not an object with a `kty`.
@ jwk_push_json ( Vec JwkKey ) out Json j → b {
    ? ! ( json_is_obj j ) { ^ F } {}
    : String kty ( __jwk_str j `kty` )
    ? == 0 ( string_len kty ) { ( string_free kty ) ^ F } {}
    : JwkKey jk @ JwkKey {
        kty
        ( __jwk_str j `kid` )
        ( __jwk_str j `alg` )
        ( __jwk_str j `crv` )
        ( __jwk_str j `use` )
        ( __jwk_b64u j `n` )
        ( __jwk_b64u j `e` )
        ( __jwk_b64u j `x` )
        ( __jwk_b64u j `y` )
        ( __jwk_b64u j `k` )
    }
    ( vec_push [JwkKey] out jk )
    ^ T
}

// The `keys` array of a JWKS document. A document that is itself a bare
// JWK (some providers hand one out) is accepted as a one-key set.
@ jwks_from_json Json doc → ( Vec JwkKey ) {
    : ( Vec JwkKey ) out ( vec_new [JwkKey] )
    ?? ( json_obj_get doc `keys` ) {
        T arr → {
            ? ( json_is_arr arr ) {
                : i n ( json_arr_len arr )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get arr k ) {
                        T item → { : b _ok ( jwk_push_json out item ) }
                        F _ → {}
                    }
                    = k + k 1
                }
            } {}
        }
        F _ → { : b _ok ( jwk_push_json out doc ) }
    }
    ^ out
}

@ jwks_parse s text → ( Vec JwkKey ) {
    ?? ( json_parse text ) {
        T doc → {
            : ( Vec JwkKey ) ks ( jwks_from_json doc )
            ( json_free doc )
            ^ ks
        }
        F _ → { ^ ( vec_new [JwkKey] ) }
    }
}

// ── Selection ──────────────────────────────────────────────────────

// The key type an algorithm needs, or "" for an unknown algorithm.
@ jwk_kty_for_alg s alg → s {
    ? == 1 ( nurl_str_starts alg `RS` ) { ^ `RSA` } {}
    ? == 1 ( nurl_str_starts alg `PS` ) { ^ `RSA` } {}
    ? == 1 ( nurl_str_starts alg `ES` ) { ^ `EC` } {}
    ? == 1 ( nurl_str_eq alg `EdDSA` ) { ^ `OKP` } {}
    ? == 1 ( nurl_str_starts alg `HS` ) { ^ `oct` } {}
    ^ ``
}

// The EC curve an ES* algorithm is defined over ("" when not ES*).
@ jwk_crv_for_alg s alg → s {
    ? == 1 ( nurl_str_eq alg `ES256` ) { ^ `P-256` } {}
    ? == 1 ( nurl_str_eq alg `ES384` ) { ^ `P-384` } {}
    ^ ``
}

// Does this key answer to (kid, alg)? `kid` may be empty (the token
// header carried none) — then only the algebraic constraints apply.
@ jwk_matches JwkKey jk s kid s alg → b {
    ? > ( nurl_str_len kid ) 0 {
        ? == 0 ( nurl_str_eq ( string_data . jk kid ) kid ) { ^ F } {}
    } {}
    // A key that declares its own algorithm must agree with the header.
    ? & > ( string_len . jk alg ) 0 > ( nurl_str_len alg ) 0 {
        ? == 0 ( nurl_str_eq ( string_data . jk alg ) alg ) { ^ F } {}
    } {}
    // `use` is optional; when present it must be for signatures.
    ? > ( string_len . jk usage ) 0 {
        ? == 0 ( nurl_str_eq ( string_data . jk usage ) `sig` ) { ^ F } {}
    } {}
    : s want_kty ( jwk_kty_for_alg alg )
    ? > ( nurl_str_len want_kty ) 0 {
        ? == 0 ( nurl_str_eq ( string_data . jk kty ) want_kty ) { ^ F } {}
    } {}
    : s want_crv ( jwk_crv_for_alg alg )
    ? > ( nurl_str_len want_crv ) 0 {
        ? == 0 ( nurl_str_eq ( string_data . jk crv ) want_crv ) { ^ F } {}
    } {}
    ? == 1 ( nurl_str_eq alg `EdDSA` ) {
        ? == 0 ( nurl_str_eq ( string_data . jk crv ) `Ed25519` ) { ^ F } {}
    } {}
    ^ T
}

// Index of the first key matching (kid, alg), or -1.
@ jwks_select ( Vec JwkKey ) ks s kid s alg → i {
    ^ ( jwks_select_from ks kid alg 0 )
}

// The same, starting at `from` — so a verifier can walk EVERY candidate
// key rather than betting on the first. That is the case during a key
// rotation, when the provider publishes the old and the new key and the
// tokens in flight carry no `kid` to tell them apart.
@ jwks_select_from ( Vec JwkKey ) ks s kid s alg i from → i {
    : i n ( vec_len [JwkKey] ks )
    : *JwkKey data ( vec_data [JwkKey] ks )
    : ~ i k ? > from 0 from 0
    ~ < k n {
        : JwkKey jk . data k
        ? ( jwk_matches jk kid alg ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Does the set hold a key with this `kid` at all? Used to decide whether
// an unknown `kid` justifies re-fetching the JWKS.
@ jwks_has_kid ( Vec JwkKey ) ks s kid → b {
    : i n ( vec_len [JwkKey] ks )
    : *JwkKey data ( vec_data [JwkKey] ks )
    : ~ i k 0
    ~ < k n {
        : JwkKey jk . data k
        ? == 1 ( nurl_str_eq ( string_data . jk kid ) kid ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// ── Derived material ───────────────────────────────────────────────

// SEC1 uncompressed point 0x04‖X‖Y, left-padded to the curve width.
// Empty when the key is not an EC key of a curve we know.
@ jwk_ec_point JwkKey jk → ( Vec u ) {
    : ~ i width 0
    ? == 1 ( nurl_str_eq ( string_data . jk crv ) `P-256` ) { = width 32 } {}
    ? == 1 ( nurl_str_eq ( string_data . jk crv ) `P-384` ) { = width 48 } {}
    ? == width 0 { ^ ( vec_new [u] ) } {}
    : i xlen ( vec_len [u] . jk x )
    : i ylen ( vec_len [u] . jk y )
    ? | > xlen width > ylen width { ^ ( vec_new [u] ) } {}
    ? | == xlen 0 == ylen 0 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) pt ( vec_with_cap [u] + 1 * 2 width )
    ( vec_push [u] pt # u 4 )
    : ~ i pad - width xlen
    ~ > pad 0 { ( vec_push [u] pt # u 0 ) = pad - pad 1 }
    ( vec_extend [u] pt . jk x )
    = pad - width ylen
    ~ > pad 0 { ( vec_push [u] pt # u 0 ) = pad - pad 1 }
    ( vec_extend [u] pt . jk y )
    ^ pt
}

// ── RFC 7638 thumbprint ────────────────────────────────────────────
//
// SHA-256 over the key's REQUIRED members, in lexicographic order, as
// the most compact JSON possible. That is the key's stable identity —
// two providers publishing the same key agree on it — so it doubles as
// a `kid` for a key that ships without one.

@ __jwk_tp_member String out s name ( Vec u ) raw b first → v {
    ? first {} { ( string_push_char out 44 ) }  // ','
    ( string_push_char out 34 )
    ( string_push_str out name )
    ( string_push_str out `":` )
    ( string_push_char out 34 )
    : String enc ( b64_url_encode_vec raw )
    ( string_push_str out ( string_data enc ) )
    ( string_free enc )
    ( string_push_char out 34 )
}

@ __jwk_tp_lit String out s name s value b first → v {
    ? first {} { ( string_push_char out 44 ) }
    ( string_push_char out 34 )
    ( string_push_str out name )
    ( string_push_str out `":"` )
    ( string_push_str out value )
    ( string_push_char out 34 )
}

@ jwk_thumbprint JwkKey jk → String {
    : String canon ( string_with_cap 256 )
    ( string_push_char canon 123 )  // '{'
    : s kty ( string_data . jk kty )
    ? == 1 ( nurl_str_eq kty `RSA` ) {
        ( __jwk_tp_member canon `e` . jk e T )
        ( __jwk_tp_lit canon `kty` `RSA` F )
        ( __jwk_tp_member canon `n` . jk n F )
    } {
        ? == 1 ( nurl_str_eq kty `EC` ) {
            ( __jwk_tp_lit canon `crv` ( string_data . jk crv ) T )
            ( __jwk_tp_lit canon `kty` `EC` F )
            ( __jwk_tp_member canon `x` . jk x F )
            ( __jwk_tp_member canon `y` . jk y F )
        } {
            ? == 1 ( nurl_str_eq kty `OKP` ) {
                ( __jwk_tp_lit canon `crv` ( string_data . jk crv ) T )
                ( __jwk_tp_lit canon `kty` `OKP` F )
                ( __jwk_tp_member canon `x` . jk x F )
            } {
                ( __jwk_tp_member canon `k` . jk oct T )
                ( __jwk_tp_lit canon `kty` `oct` F )
            }
        }
    }
    ( string_push_char canon 125 )  // '}'
    : ( Vec u ) msg ( bytes_from_str ( string_data canon ) )
    ( string_free canon )
    : ( Vec u ) h ( sha256_pure msg )
    ( vec_free [u] msg )
    : String out ( b64_url_encode_vec h )
    ( vec_free [u] h )
    ^ out
}
