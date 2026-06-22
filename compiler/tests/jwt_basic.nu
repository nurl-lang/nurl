// jwt_basic.nu — ext/jwt.nu acceptance.
//
// HS256 is checked against the canonical jwt.io reference token
// (secret "your-256-bit-secret"). EdDSA uses the RFC 8032 §7.1 TEST 1
// secret key — Ed25519 signatures are deterministic, so the whole
// token is reproducible and goldened. Both algorithms also exercise
// verify success, wrong-key / tamper rejection, and exp/nbf time
// claims (via verify_at with explicit timestamps).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/jwt.nu`

@ hx s h → ( Vec u ) {
    : i n ( nurl_str_len h )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 1 / n 2 1 )
    : ~ i k 0
    ~ < + k 1 n {
        : i hi ( nurl_str_get h k )
        : i lo ( nurl_str_get h + k 1 )
        : i hv ? <= hi 57 - hi 48 - hi 87
        : i lv ? <= lo 57 - lo 48 - lo 87
        ( vec_push [u] out # u + * hv 16 lv )
        = k + k 2
    }
    ^ out
}

// Print "ok"/"BAD" for a verify result, plus the `sub` claim on success.
@ show_verify s label ! Json JwtErr r → v {
    ( nurl_print label )
    ?? r {
        T payload → {
            ( nurl_print `ok sub=` )
            : ?Json subo ( json_obj_get payload `sub` )
            ?? subo { T sj → ( nurl_print ( json_str_data sj ) ) F _ → ( nurl_print `<none>` ) }
            ( nurl_print `\n` )
            ( json_free payload )
        }
        F e → {
            ( nurl_print `err=` )
            ( nurl_print ?? e {
                JwtMalformed → `Malformed`
                JwtBadSignature → `BadSignature`
                JwtExpired → `Expired`
                JwtNotYetValid → `NotYetValid`
                JwtUnsupportedAlg → `UnsupportedAlg`
                JwtBadClaims → `BadClaims`
            } )
            ( nurl_print `\n` )
        }
    }
}

@ mk_claims → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `sub` ( json_str_lit `1234567890` ) )
    ( json_obj_set p `name` ( json_str_lit `John Doe` ) )
    ( json_obj_set p `iat` ( json_num_lit `1516239022` ) )
    ^ p
}

@ main → i {
    : s secret `your-256-bit-secret`

    // ── HS256 sign → canonical jwt.io token ────────────────────────
    : Json claims ( mk_claims )
    : String tok ( jwt_hs256_sign secret claims )
    ( nurl_print `hs256_token=` ) ( nurl_print ( string_data tok ) ) ( nurl_print `\n` )

    // verify with the right secret (no exp/nbf → always valid)
    ( show_verify `hs256_verify_ok: ` ( jwt_hs256_verify_at secret ( string_data tok ) 1516239022 ) )
    // verify with the wrong secret → BadSignature
    ( show_verify `hs256_verify_wrongkey: ` ( jwt_hs256_verify_at `wrong-secret` ( string_data tok ) 1516239022 ) )

    // tamper: flip the last char of the signature segment
    : i tlen ( string_len tok )
    : String bad ( string_with_cap + tlen 1 )
    : ~ i k 0
    ~ < k tlen {
        : i c ( nurl_str_get ( string_data tok ) k )
        ( string_push_char bad ? == k - tlen 1 ? == c 99 100 99 c )
        = k + k 1
    }
    ( show_verify `hs256_verify_tampered: ` ( jwt_hs256_verify_at secret ( string_data bad ) 1516239022 ) )
    ( string_free bad )

    // malformed (no dots)
    ( show_verify `hs256_verify_malformed: ` ( jwt_hs256_verify_at secret `not-a-token` 0 ) )

    ( string_free tok )
    ( json_free claims )

    // ── exp / nbf time claims (HS256) ──────────────────────────────
    : Json ec ( json_obj_new )
    ( json_obj_set ec `sub` ( json_str_lit `exp-test` ) )
    ( json_obj_set ec `exp` ( json_num_lit `1000` ) )
    : String etok ( jwt_hs256_sign secret ec )
    ( show_verify `hs256_exp_valid(now=500): ` ( jwt_hs256_verify_at secret ( string_data etok ) 500 ) )
    ( show_verify `hs256_exp_expired(now=2000): ` ( jwt_hs256_verify_at secret ( string_data etok ) 2000 ) )
    ( string_free etok )
    ( json_free ec )

    : Json nc ( json_obj_new )
    ( json_obj_set nc `sub` ( json_str_lit `nbf-test` ) )
    ( json_obj_set nc `nbf` ( json_num_lit `1000` ) )
    : String ntok ( jwt_hs256_sign secret nc )
    ( show_verify `hs256_nbf_early(now=500): ` ( jwt_hs256_verify_at secret ( string_data ntok ) 500 ) )
    ( show_verify `hs256_nbf_ok(now=1500): ` ( jwt_hs256_verify_at secret ( string_data ntok ) 1500 ) )
    ( string_free ntok )
    ( json_free nc )

    // ── EdDSA (Ed25519, RFC 8032 §7.1 TEST 1 secret) ───────────────
    : ( Vec u ) sk ( hx `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` )
    : Json eclaims ( mk_claims )
    : !String CryptoErr eso ( jwt_eddsa_sign sk eclaims )
    ?? eso {
        T etoken → {
            ( nurl_print `eddsa_token=` ) ( nurl_print ( string_data etoken ) ) ( nurl_print `\n` )
            : !( Vec u ) CryptoErr pko ( ed25519_pubkey sk )
            ?? pko {
                T pk → {
                    ( show_verify `eddsa_verify_ok: ` ( jwt_eddsa_verify_at pk ( string_data etoken ) 1516239022 ) )
                    // tamper the payload's last pre-dot char
                    : i el ( string_len etoken )
                    : String ebad ( string_with_cap + el 1 )
                    : ~ i j 0
                    ~ < j el {
                        : i c ( nurl_str_get ( string_data etoken ) j )
                        ( string_push_char ebad ? == j - el 1 ? == c 65 66 65 c )
                        = j + j 1
                    }
                    ( show_verify `eddsa_verify_tampered: ` ( jwt_eddsa_verify_at pk ( string_data ebad ) 1516239022 ) )
                    ( string_free ebad )
                    ( vec_free [u] pk )
                }
                F _ → ( nurl_print `eddsa pubkey FAILED\n` )
            }
            ( string_free etoken )
        }
        F _ → ( nurl_print `eddsa sign FAILED\n` )
    }
    ( vec_free [u] sk )
    ( json_free eclaims )

    // ── decode_unverified ──────────────────────────────────────────
    : Json dc ( mk_claims )
    : String dtok ( jwt_hs256_sign secret dc )
    : !Json JwtErr du ( jwt_decode_unverified ( string_data dtok ) )
    ?? du {
        T payload → {
            : ?Json no ( json_obj_get payload `name` )
            ( nurl_print `decode_unverified_name=` )
            ?? no { T nj → ( nurl_print ( json_str_data nj ) ) F _ → ( nurl_print `<none>` ) }
            ( nurl_print `\n` )
            ( json_free payload )
        }
        F _ → ( nurl_print `decode_unverified FAILED\n` )
    }
    ( string_free dtok )
    ( json_free dc )

    ^ 0
}
