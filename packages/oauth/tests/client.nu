// tests/client.nu — drive the oauth package against tests/provider.nu.
//
// Two halves: the offline checks (PKCE vectors, JWKS parsing, callback
// handling — no network at all), then the full authorization-code flow
// against a live provider, including every way a token can be wrong.
//
//   client --port N

$ `stdlib/std/args.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/ed25519.nu`
$ `../src/oauth.nu`

: ~ i g_fail 0
: ~ i g_pass 0

@ ok b cond s label → v {
    ? cond {
        = g_pass + g_pass 1
        : String m ( string_from `  ok   ` )
        ( string_push_str m label )
        ( nurl_println ( string_data m ) )
        ( string_free m )
    } {
        = g_fail + g_fail 1
        : String m ( string_from `  FAIL ` )
        ( string_push_str m label )
        ( nurl_println ( string_data m ) )
        ( string_free m )
    }
}

@ ok_str s got s want s label → v {
    : b same == 1 ( nurl_str_eq got want )
    ? same {} {
        : String m ( string_from `       got "` )
        ( string_push_str m got )
        ( string_push_str m `" want "` )
        ( string_push_str m want )
        ( string_push_char m 34 )
        ( nurl_println ( string_data m ) )
        ( string_free m )
    }
    ( ok same label )
}

@ section s title → v {
    ( nurl_println `` )
    ( nurl_println title )
}

// ── Offline ────────────────────────────────────────────────────────

// RFC 7636 Appendix B: the S256 transform, on the RFC's own vector.
@ test_pkce_vector → v {
    : String ch ( pkce_challenge_for `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` )
    ( ok_str ( string_data ch ) `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM` `PKCE S256 matches RFC 7636 B` )
    ( string_free ch )
    : Pkce pk ( pkce_new )
    ( ok == ( string_len . pk verifier ) 43 `fresh verifier is 43 chars (256 bits)` )
    : String again ( pkce_challenge_for ( string_data . pk verifier ) )
    ( ok ( string_eq again . pk challenge ) `challenge is S256 of the verifier` )
    ( ok_str ( string_data . pk method ) `S256` `method is S256, never plain` )
    ( string_free again )
    ( pkce_free pk )
    : String s1 ( oauth_state_new )
    : String s2 ( oauth_state_new )
    ( ok ! ( string_eq s1 s2 ) `two states differ` )
    ( string_free s1 ) ( string_free s2 )
}

@ test_jwks_offline → v {
    : s doc `{"keys":[{"kty":"EC","crv":"P-256","kid":"a","alg":"ES256","use":"sig","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"},{"kty":"RSA","kid":"b","alg":"RS256","n":"AQAB","e":"AQAB"}]}`
    : ( Vec JwkKey ) ks ( jwks_parse doc )
    ( ok == ( vec_len [JwkKey] ks ) 2 `JWKS parses both keys` )
    ( ok == ( jwks_select ks `a` `ES256` ) 0 `selects the EC key by kid` )
    ( ok == ( jwks_select ks `b` `RS256` ) 1 `selects the RSA key by kid` )
    ( ok == ( jwks_select ks `a` `RS256` ) -1 `refuses an EC key for RS256` )
    ( ok == ( jwks_select ks `zz` `ES256` ) -1 `refuses an unknown kid` )
    ( ok ( jwks_has_kid ks `b` ) `has_kid finds a published kid` )
    ( ok ! ( jwks_has_kid ks `zz` ) `has_kid rejects an unknown kid` )
    // RFC 7638 §3.1's own example key thumbprint is defined for RSA; for
    // the EC key we assert only that it is stable and 43 chars of
    // base64url — the property callers rely on when using it as a kid.
    : *JwkKey data ( vec_data [JwkKey] ks )
    : JwkKey k0 . data 0
    : String tp1 ( jwk_thumbprint k0 )
    : String tp2 ( jwk_thumbprint k0 )
    ( ok & == ( string_len tp1 ) 43 ( string_eq tp1 tp2 ) `thumbprint is stable, 43 chars` )
    ( string_free tp1 ) ( string_free tp2 )
    : ( Vec u ) pt ( jwk_ec_point k0 )
    ( ok == ( vec_len [u] pt ) 65 `EC point is 0x04‖X‖Y` )
    ( vec_free [u] pt )
    ( jwks_free ks )
    : ( Vec JwkKey ) empty ( jwks_parse `not json at all` )
    ( ok == ( vec_len [JwkKey] empty ) 0 `garbage JWKS yields no keys` )
    ( jwks_free empty )
}

@ test_callback_offline → v {
    ?? ( oauth_callback_code `code=abc123&state=st-1` `st-1` ) {
        T c → {
            ( ok_str ( string_data c ) `abc123` `callback yields the code` )
            ( string_free c )
        }
        F _ → { ( ok F `callback yields the code` ) }
    }
    ?? ( oauth_callback_code `code=abc123&state=WRONG` `st-1` ) {
        T c → { ( string_free c ) ( ok F `state mismatch is rejected` ) }
        F e → { ( ok_str ( oauth_err_name e ) `OaState` `state mismatch is rejected` ) }
    }
    ?? ( oauth_callback_code `error=access_denied&error_description=user+said+no&state=st-1` `st-1` ) {
        T c → { ( string_free c ) ( ok F `provider error surfaces` ) }
        F e → { ( ok_str ( oauth_err_name e ) `OaServer` `provider error surfaces` ) }
    }
    : CallbackParams cb ( oauth_callback_parse `error=access_denied&error_description=user+said+no` )
    ( ok_str ( string_data . cb error_description ) `user said no` `error_description is form-decoded` )
    ( callback_params_free cb )
}

@ test_policy_offline → v {
    : *OidcPolicy pol ( oidc_policy_new `https://iss.example` `client-1` )
    ( ok ( oidc_policy_alg_allowed pol `ES256` ) `empty allowlist allows any supported alg` )
    ( oidc_policy_set_algs pol `RS256 ES256` )
    ( ok ( oidc_policy_alg_allowed pol `ES256` ) `allowlist admits a listed alg` )
    ( ok ! ( oidc_policy_alg_allowed pol `EdDSA` ) `allowlist excludes an unlisted alg` )
    ( oidc_policy_set_algs pol `` )

    : s doc `{"iss":"https://iss.example","aud":"client-1","sub":"u1","exp":2000,"iat":1000,"nonce":"n1"}`
    ?? ( json_parse doc ) {
        T claims → {
            ?? ( claims_check claims pol 1500 ) {
                T _ → { ( ok F `a good claim set passes` ) }
                F _ → { ( ok T `a good claim set passes` ) }
            }
            ?? ( claims_check claims pol 2500 ) {
                T e → { ( ok_str ( claim_err_desc # ClaimErr e ) `token expired` `exp is enforced` ) }
                F _ → { ( ok F `exp is enforced` ) }
            }
            // 2000 + 60s leeway is still inside the window
            ?? ( claims_check claims pol 2030 ) {
                T _ → { ( ok F `leeway covers small clock skew` ) }
                F _ → { ( ok T `leeway covers small clock skew` ) }
            }
            ( oidc_policy_set_nonce pol `n1` )
            ?? ( claims_check claims pol 1500 ) {
                T _ → { ( ok F `matching nonce passes` ) }
                F _ → { ( ok T `matching nonce passes` ) }
            }
            ( oidc_policy_set_nonce pol `other` )
            ?? ( claims_check claims pol 1500 ) {
                T e → { ( ok_str ( claim_err_desc # ClaimErr e ) `nonce mismatch` `a replayed nonce is caught` ) }
                F _ → { ( ok F `a replayed nonce is caught` ) }
            }
            ( oidc_policy_set_nonce pol `` )
            ( oidc_policy_set_audience pol `someone-else` )
            ?? ( claims_check claims pol 1500 ) {
                T e → { ( ok_str ( claim_err_desc # ClaimErr e ) `wrong audience` `aud is enforced` ) }
                F _ → { ( ok F `aud is enforced` ) }
            }
            ( oidc_policy_set_audience pol `client-1` )
            ( oidc_policy_set_issuer pol `https://evil.example` )
            ?? ( claims_check claims pol 1500 ) {
                T e → { ( ok_str ( claim_err_desc # ClaimErr e ) `wrong issuer` `iss is enforced` ) }
                F _ → { ( ok F `iss is enforced` ) }
            }
            ( json_free claims )
        }
        F _ → { ( ok F `policy fixture parses` ) }
    }
    ( oidc_policy_free pol )
}

@ test_claims_shapes → v {
    : s doc `{"aud":["a","b"],"scope":"read write","groups":["dev","ops"],"email_verified":true}`
    ?? ( json_parse doc ) {
        T c → {
            ( ok ( claims_has_audience c `b` ) `aud as an array matches` )
            ( ok ! ( claims_has_audience c `c` ) `aud as an array rejects` )
            ( ok ( claims_has_scope c `write` ) `scope string splits` )
            ( ok ! ( claims_has_scope c `admin` ) `scope rejects what was not granted` )
            : ( Vec String ) gs ( claims_string_list c `groups` )
            ( ok == ( vec_len [String] gs ) 2 `string list claim reads an array` )
            ( claims_strings_free gs )
            ( ok ( claims_bool c `email_verified` ) `boolean claim reads` )
            ( json_free c )
        }
        F _ → { ( ok F `claim shapes fixture parses` ) }
    }
}

// ── Offline: the asymmetric algorithms ─────────────────────────────
//
// RS256 and PS256 against a token minted by OpenSSL with an RSA-2048
// key — the point of a fixed vector being that it proves the pure-NURL
// RSA path agrees with an independent implementation, not with itself.

@ rsa_jwks → s {
    ^ `{"keys":[{"kty":"RSA","kid":"rsa1","use":"sig","n":"yZWWkMEXKhMas316iNWRVVVbD8pZ3jzfE6BTAdBXZ3Hdi-vS588yd6H28_4qZU7G0rlCR5ge4FoqWx_kteobrsVUm_J7zRmFjx7UoATeht1p5WH4FFL42jik12GvYeyfYR1OQAN-orT9f-_Iq3sf5lqaN_V-JIa08mvXfAwE7nbNmiYy30CkGBYBAU0z46R7es6_caRHhq_jwd-2P6nUXm66COpLuLlvrBp_0S3i_ZvDp5wOVyae5_h1p4TELA7LOKIBfnokygT6Q9OEohvundxUjnyit1eXyoXkrVWnvNNRuWXDYHEBsg5JsnT4yXX_1GeSkJ9xnG7wnfBxlVF3Mw","e":"AQAB"}]}`
}

@ rs256_token → s {
    ^ `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InJzYTEifQ.eyJpc3MiOiJodHRwczovL3JzYS5leGFtcGxlIiwic3ViIjoicnNhLXVzZXIiLCJhdWQiOiJjbGllbnQtMSIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNzAwMDAwMDAwfQ.BfUZt-me63nppgOZKVNZiJsOYMNy-KT9Z2k4nTImpBa5u8EspTF9-xxMoC-52-0UtVgC8AcrcTJsj9GrghFm8E9ZQ91uwo1hPSsD95LVYa1R_jhiarDzZlCvSZbzL1cZjkuYo1iwHeX_GHEgJraNs7_nXQi2oPrlsK0Ne1AKiyU0b73lcB4HU5lHuVa7vD0HhvHwcTKsjvYTRivTvoGFMqlFTqxNJyYCXz-X782m7v9ZHKz-ipQnsRVLqrT4LjGrA7C_WNJzOJqFrAArC_9SEHXw-Pm8eQNeC5jWP9JOumFArbAIt5AVA4uW3WZLKiWI7vVNCZgSdB4nm2ZoKqbIGw`
}

@ ps256_token → s {
    ^ `eyJhbGciOiJQUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InJzYTEifQ.eyJpc3MiOiJodHRwczovL3JzYS5leGFtcGxlIiwic3ViIjoicnNhLXVzZXIiLCJhdWQiOiJjbGllbnQtMSIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNzAwMDAwMDAwfQ.LvRyx8JFTU4oCzQmD_Qg81ZXgKJznFhjlcliCUOF21C5rptfjKMJm2LSzuug22gC_hEVH9OimklsF0QgkS-cHTcI7S33qyiDpxPI86iu8SovI-SnbnFfFn6ryuzk_B8msW9SVAWOtTmp440Ak5J_vEZDc5D7j_GLLLRrG_K19i1SEYnDx41YGPhCgsfFesuqjdBbXrg4Uom06usEQxwWNh1zL7nifxOvcNR9ruvKEdatVp97HexoAzfphXDgiinBvlToHeiL5GIhwd_WKppBBYLRg7CAmj3-Wto-cjNrbrHEGc2vhue7gs0n2yeKI45cbJDrGY4B0DxrZQnJGaPTKg`
}

// The same token with its last signature character changed.
@ flip_last s token → String {
    : i n ( nurl_str_len token )
    : String whole ( string_from token )
    : String out ( string_substr whole 0 - n 1 )
    ( string_free whole )
    : i last ( nurl_str_get token - n 1 )
    ( string_push_char out ? == last 65 66 65 )  // 'A' ↔ 'B'
    ^ out
}

@ test_rsa_offline → v {
    : ( Vec JwkKey ) ks ( jwks_parse ( rsa_jwks ) )
    ( ok == ( vec_len [JwkKey] ks ) 1 `RSA JWKS parses` )
    : i idx ( jwks_select ks `rsa1` `RS256` )
    ( ok == idx 0 `a key with no alg member serves RS256` )
    ( ok == ( jwks_select ks `rsa1` `PS256` ) 0 `... and PS256` )
    ( ok == ( jwks_select ks `rsa1` `ES256` ) -1 `... but not ES256` )
    : *JwkKey data ( vec_data [JwkKey] ks )
    : JwkKey jk . data 0
    ( ok == ( vec_len [u] . jk n ) 256 `2048-bit modulus decodes to 256 bytes` )

    ?? ( jws_verify_with_key jk ( rs256_token ) ) {
        F e → { ( ok F `RS256 verifies (OpenSSL vector)` ) ( nurl_eprintln ( oauth_err_name e ) ) }
        T c → {
            ( ok T `RS256 verifies (OpenSSL vector)` )
            : String sub ( claims_str c `sub` )
            ( ok_str ( string_data sub ) `rsa-user` `RS256 claims are readable` )
            ( string_free sub )
            ( json_free c )
        }
    }
    ?? ( jws_verify_with_key jk ( ps256_token ) ) {
        F e → { ( ok F `PS256 verifies (OpenSSL vector)` ) ( nurl_eprintln ( oauth_err_name e ) ) }
        T c → { ( ok T `PS256 verifies (OpenSSL vector)` ) ( json_free c ) }
    }
    : String bad ( flip_last ( rs256_token ) )
    ?? ( jws_verify_with_key jk ( string_data bad ) ) {
        T c → { ( json_free c ) ( ok F `a one-character edit breaks RS256` ) }
        F e → { ( ok_str ( oauth_err_name e ) `OaBadSignature` `a one-character edit breaks RS256` ) }
    }
    ( string_free bad )
    ( jwks_free ks )
}

// EdDSA and HS256 as round trips: sign here with the stdlib, verify
// through the JWK path, so the whole chain is exercised without a
// vector to paste.

@ jws_make s header s payload ( Vec u ) sig → String {
    : String h64 ( b64_url_encode header )
    : String p64 ( b64_url_encode payload )
    : String s64 ( b64_url_encode_vec sig )
    : String out ( string_with_cap 512 )
    ( string_push_str out ( string_data h64 ) )
    ( string_push_char out 46 )
    ( string_push_str out ( string_data p64 ) )
    ( string_push_char out 46 )
    ( string_push_str out ( string_data s64 ) )
    ( string_free h64 ) ( string_free p64 ) ( string_free s64 )
    ^ out
}

@ jws_signing_bytes s header s payload → ( Vec u ) {
    : String h64 ( b64_url_encode header )
    : String p64 ( b64_url_encode payload )
    : String signing ( string_with_cap 256 )
    ( string_push_str signing ( string_data h64 ) )
    ( string_push_char signing 46 )
    ( string_push_str signing ( string_data p64 ) )
    ( string_free h64 ) ( string_free p64 )
    : ( Vec u ) msg ( bytes_from_str ( string_data signing ) )
    ( string_free signing )
    ^ msg
}

@ test_eddsa_offline → v {
    : ~ ( Vec u ) seed ( vec_new [u] )
    ?? ( bytes_from_hex `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` ) {
        T v → { ( vec_free [u] seed ) = seed v }
        F _ → {}
    }
    : ( Vec u ) pk ( ed25519_pubkey_pure seed )
    : String x64 ( b64_url_encode_vec pk )
    : String jwks ( string_with_cap 256 )
    ( string_push_str jwks `{"keys":[{"kty":"OKP","crv":"Ed25519","kid":"ed1","alg":"EdDSA","x":"` )
    ( string_push_str jwks ( string_data x64 ) )
    ( string_push_str jwks `"}]}` )
    ( string_free x64 )

    : ( Vec JwkKey ) ks ( jwks_parse ( string_data jwks ) )
    ( string_free jwks )
    ( ok == ( jwks_select ks `ed1` `EdDSA` ) 0 `an OKP key serves EdDSA` )
    ( ok == ( jwks_select ks `ed1` `ES256` ) -1 `... and nothing else` )

    : s hdr `{"alg":"EdDSA","typ":"JWT","kid":"ed1"}`
    : s pld `{"iss":"https://ed.example","sub":"ed-user","exp":9999999999}`
    : ( Vec u ) msg ( jws_signing_bytes hdr pld )
    : ( Vec u ) sig ( ed25519_sign_pure seed msg )
    : String token ( jws_make hdr pld sig )
    : *JwkKey data ( vec_data [JwkKey] ks )
    : JwkKey jk . data 0
    ?? ( jws_verify_with_key jk ( string_data token ) ) {
        F e → { ( ok F `EdDSA round trip verifies` ) ( nurl_eprintln ( oauth_err_name e ) ) }
        T c → {
            : String sub ( claims_str c `sub` )
            ( ok_str ( string_data sub ) `ed-user` `EdDSA round trip verifies` )
            ( string_free sub )
            ( json_free c )
        }
    }
    : String bad ( flip_last ( string_data token ) )
    ?? ( jws_verify_with_key jk ( string_data bad ) ) {
        T c → { ( json_free c ) ( ok F `a one-character edit breaks EdDSA` ) }
        F e → { ( ok_str ( oauth_err_name e ) `OaBadSignature` `a one-character edit breaks EdDSA` ) }
    }
    ( string_free bad )
    ( string_free token )
    ( vec_free [u] msg ) ( vec_free [u] sig )
    ( vec_free [u] pk ) ( vec_free [u] seed )
    ( jwks_free ks )
}

@ test_hs256_offline → v {
    : ( Vec u ) secret ( bytes_from_str `a shared secret, configured on both sides` )
    : String k64 ( b64_url_encode_vec secret )
    : String jwks ( string_with_cap 256 )
    ( string_push_str jwks `{"keys":[{"kty":"oct","kid":"h1","alg":"HS256","k":"` )
    ( string_push_str jwks ( string_data k64 ) )
    ( string_push_str jwks `"}]}` )
    ( string_free k64 )
    : ( Vec JwkKey ) ks ( jwks_parse ( string_data jwks ) )
    ( string_free jwks )
    ( ok == ( jwks_select ks `h1` `HS256` ) 0 `an oct key serves HS256` )
    ( ok == ( jwks_select ks `h1` `RS256` ) -1 `... and never an asymmetric alg` )

    : s hdr `{"alg":"HS256","typ":"JWT","kid":"h1"}`
    : s pld `{"iss":"https://hs.example","sub":"hs-user","exp":9999999999}`
    : ( Vec u ) msg ( jws_signing_bytes hdr pld )
    : ( Vec u ) mac ( hmac_sha256_pure secret msg )
    : String token ( jws_make hdr pld mac )
    : *JwkKey data ( vec_data [JwkKey] ks )
    : JwkKey jk . data 0
    ?? ( jws_verify_with_key jk ( string_data token ) ) {
        F e → { ( ok F `HS256 round trip verifies` ) ( nurl_eprintln ( oauth_err_name e ) ) }
        T c → {
            : String sub ( claims_str c `sub` )
            ( ok_str ( string_data sub ) `hs-user` `HS256 round trip verifies` )
            ( string_free sub )
            ( json_free c )
        }
    }
    ( string_free token )
    ( vec_free [u] msg ) ( vec_free [u] mac ) ( vec_free [u] secret )
    ( jwks_free ks )
}

// ── Online ─────────────────────────────────────────────────────────

@ fetch_text * HttpClient hc s url → String {
    ?? ( http_client_get hc url ) {
        T r → {
            : String body ( bytes_to_str . r body )
            ( http_response_free r )
            ^ body
        }
        F _ → { ^ ( string_new ) }
    }
}

@ expect_verify_err * OidcProvider p * OidcPolicy pol s token s want s label → v {
    ?? ( oidc_verify_token p pol token ) {
        T id → {
            ( oidc_identity_free id )
            ( ok F label )
        }
        F e → { ( ok_str ( oauth_err_name e ) want label ) }
    }
}

@ run_online s base → v {
    ( section `discovery + keys` )
    ?? ( oidc_provider_discover base ) {
        F e → { ( ok F `discovery` ) ( nurl_eprintln ( oauth_err_name e ) ) }
        T p → {
            ( ok T `discovery succeeds` )
            ( ok_str ( string_data . p issuer ) base `issuer round-trips` )
            ( ok > ( string_len . p token_endpoint ) 0 `token_endpoint discovered` )
            ( ok > ( string_len . p jwks_uri ) 0 `jwks_uri discovered` )
            ?? ( oidc_fetch_jwks p ) {
                T _ → { ( ok F `JWKS fetch` ) }
                F _ → { ( ok == ( oidc_provider_key_count p ) 2 `JWKS fetch yields both published keys` ) }
            }

            : *OauthConfig cfg ( oauth_config_new `test-client` `http://127.0.0.1:1/cb` `openid profile` )
            : Pkce pk ( pkce_new )
            : String state ( oauth_state_new )
            : String nonce ( oauth_nonce_new )

            ( section `authorization request` )
            : String url ( oauth_authorize_url p cfg ( string_data state ) ( string_data nonce ) pk )
            ( ok ( string_contains url `response_type=code` ) `authorize URL asks for a code` )
            ( ok ( string_contains url `code_challenge_method=S256` ) `authorize URL commits to S256` )
            ( ok ( string_contains url ( string_data . pk challenge ) ) `authorize URL carries the challenge` )
            ( ok ( string_contains url `redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fcb` ) `redirect_uri is percent-encoded` )
            ( ok ( string_contains url `scope=openid%20profile` ) `scope is percent-encoded` )
            ( string_free url )

            ( section `token exchange` )
            // The provider's stateless code carries the challenge and
            // the nonce the authorization request committed to.
            : String code ( string_from `c.` )
            ( string_push_str code ( string_data . pk challenge ) )
            ( string_push_char code 46 )
            ( string_push_str code ( string_data nonce ) )

            : *OidcPolicy pol ( oidc_policy_new base `test-client` )
            ( oidc_policy_set_nonce pol ( string_data nonce ) )

            ?? ( oauth_exchange_code p cfg ( string_data code ) ( string_data . pk verifier ) ) {
                F e → {
                    ( ok F `code exchange` )
                    ( nurl_eprintln ( oidc_provider_last_error p ) )
                }
                T ts → {
                    ( ok T `code exchange succeeds` )
                    ( ok > ( string_len . ts id_token ) 0 `an ID token came back` )
                    ( ok_str ( token_set_token_type ts ) `Bearer` `token_type is Bearer` )
                    ( ok == . ts expires_in 300 `expires_in is carried` )
                    ( ok ! ( token_set_stale ts ( now_seconds ) ) `a fresh token is not stale` )
                    ( ok ( token_set_stale ts + ( now_seconds ) 300 ) `a token past its life is stale` )

                    ( section `who is this` )
                    ?? ( oidc_verify_id_token p pol ( token_set_id_token ts ) ) {
                        F e → {
                            ( ok F `ID token verifies` )
                            ( nurl_eprintln ( oidc_provider_last_error p ) )
                        }
                        T id → {
                            ( ok T `ID token verifies` )
                            ( ok_str ( string_data . id subject ) `user-42` `subject is read` )
                            ( ok_str ( string_data . id email ) `user42@example.com` `email is read` )
                            ( ok_str ( string_data . id name ) `Test User` `name is read` )
                            ( ok_str ( string_data . id username ) `tuser` `preferred_username is read` )
                            ( ok . id email_verified `email_verified is read` )
                            : String key ( oidc_identity_key id )
                            : String want ( string_from `user-42@` )
                            ( string_push_str want base )
                            ( ok ( string_eq key want ) `identity key is sub@issuer` )
                            ( string_free key ) ( string_free want )
                            : String desc ( oidc_identity_describe id )
                            ( ok ( string_contains desc `Test User` ) `describe renders the profile` )
                            ( string_free desc )
                            ( oidc_identity_free id )
                        }
                    }

                    ( section `the access token as a credential` )
                    : *OidcPolicy apol ( oidc_policy_new base `test-api` )
                    ?? ( oidc_verify_access_token p apol ( token_set_access_token ts ) ) {
                        F e → {
                            ( ok F `access token verifies for the API audience` )
                            ( nurl_eprintln ( oidc_provider_last_error p ) )
                        }
                        T id → {
                            ( ok T `access token verifies for the API audience` )
                            ( ok ( oidc_identity_has_scope id `read:things` ) `granted scope is visible` )
                            ( ok ! ( oidc_identity_has_scope id `write:things` ) `ungranted scope is not` )
                            ( oidc_identity_free id )
                        }
                    }
                    // The same token must NOT pass for a different audience.
                    : *OidcPolicy wrong ( oidc_policy_new base `some-other-api` )
                    ( expect_verify_err p wrong ( token_set_access_token ts ) `OaClaims` `a token for another audience is refused` )
                    ( oidc_policy_free wrong )
                    ( oidc_policy_free apol )

                    ( section `userinfo` )
                    ?? ( oauth_userinfo_identity p ( token_set_access_token ts ) `user-42` ) {
                        F _ → { ( ok F `userinfo identity` ) }
                        T id → {
                            ( ok_str ( string_data . id subject ) `user-42` `userinfo identity` )
                            ( oidc_identity_free id )
                        }
                    }
                    ?? ( oauth_userinfo_identity p ( token_set_access_token ts ) `somebody-else` ) {
                        T id → { ( oidc_identity_free id ) ( ok F `userinfo sub is cross-checked` ) }
                        F e → { ( ok_str ( oauth_err_name e ) `OaClaims` `userinfo sub is cross-checked` ) }
                    }

                    ( section `refresh` )
                    ?? ( oauth_refresh p cfg ( token_set_refresh_token ts ) ) {
                        F _ → { ( ok F `refresh grant` ) }
                        T ts2 → {
                            ( ok > ( string_len . ts2 access_token ) 0 `refresh grant returns a new token` )
                            ( token_set_free ts2 )
                        }
                    }
                    ?? ( oauth_refresh p cfg `rt-nope` ) {
                        T ts2 → { ( token_set_free ts2 ) ( ok F `a bad refresh token is refused` ) }
                        F e → { ( ok_str ( oauth_err_name e ) `OaServer` `a bad refresh token is refused` ) }
                    }

                    ( token_set_free ts )
                }
            }

            ( section `client credentials` )
            ?? ( oauth_client_credentials p cfg ) {
                F _ → { ( ok F `client_credentials grant` ) }
                T ts → {
                    ( ok > ( string_len . ts access_token ) 0 `client_credentials returns a token` )
                    ( ok == ( string_len . ts id_token ) 0 `machine grant carries no ID token` )
                    ( token_set_free ts )
                }
            }

            ( section `PKCE is actually checked` )
            : String code2 ( string_from `c.` )
            ( string_push_str code2 ( string_data . pk challenge ) )
            ( string_push_str code2 `.n` )
            ?? ( oauth_exchange_code p cfg ( string_data code2 ) `a-different-verifier` ) {
                T ts → { ( token_set_free ts ) ( ok F `the wrong verifier is rejected` ) }
                F e → { ( ok_str ( oauth_err_name e ) `OaServer` `the wrong verifier is rejected` ) }
            }
            ( string_free code2 )

            ( section `every way a token can be wrong` )
            : *HttpClient hc ( oidc_provider_http p )
            : String mintbase ( string_from base )
            ( string_push_str mintbase `/mint/` )

            : String u_exp ( string_from ( string_data mintbase ) )
            ( string_push_str u_exp `expired` )
            : String t_exp ( fetch_text hc ( string_data u_exp ) )
            ( expect_verify_err p pol ( string_data t_exp ) `OaClaims` `an expired token is refused` )

            : String u_bad ( string_from ( string_data mintbase ) )
            ( string_push_str u_bad `badsig` )
            : String t_bad ( fetch_text hc ( string_data u_bad ) )
            ( expect_verify_err p pol ( string_data t_bad ) `OaBadSignature` `a tampered signature is refused` )

            : String u_aud ( string_from ( string_data mintbase ) )
            ( string_push_str u_aud `wrongaud` )
            : String t_aud ( fetch_text hc ( string_data u_aud ) )
            ( expect_verify_err p pol ( string_data t_aud ) `OaClaims` `a token minted for someone else is refused` )

            : String u_kid ( string_from ( string_data mintbase ) )
            ( string_push_str u_kid `unknownkid` )
            : String t_kid ( fetch_text hc ( string_data u_kid ) )
            ( expect_verify_err p pol ( string_data t_kid ) `OaNoKey` `an unpublished kid is refused` )

            : String u_none ( string_from ( string_data mintbase ) )
            ( string_push_str u_none `none` )
            : String t_none ( fetch_text hc ( string_data u_none ) )
            ( expect_verify_err p pol ( string_data t_none ) `OaAlgNotAllowed` `alg:none is refused` )

            : String u_hs ( string_from ( string_data mintbase ) )
            ( string_push_str u_hs `hs256` )
            : String t_hs ( fetch_text hc ( string_data u_hs ) )
            ( expect_verify_err p pol ( string_data t_hs ) `OaAlgNotAllowed` `HS256 against a public key set is refused` )

            // A token with no `kid`, against a key set whose FIRST key is
            // a decoy: the verifier must walk to the second one.
            : String u_nk ( string_from ( string_data mintbase ) )
            ( string_push_str u_nk `nokid` )
            : String t_nk ( fetch_text hc ( string_data u_nk ) )
            // (minted outside an authorization request, so no nonce)
            : *OidcPolicy nopol ( oidc_policy_new base `test-client` )
            ?? ( oidc_verify_token p nopol ( string_data t_nk ) ) {
                F e → {
                    ( ok F `a token with no kid verifies against the right key` )
                    ( nurl_eprintln ( oidc_provider_last_error p ) )
                }
                T id → {
                    ( ok_str ( string_data . id subject ) `user-42` `a token with no kid verifies against the right key` )
                    ( oidc_identity_free id )
                }
            }
            ( oidc_policy_free nopol )
            ( string_free u_nk ) ( string_free t_nk )

            ( expect_verify_err p pol `not.a.token` `OaBadToken` `garbage is refused` )
            ( expect_verify_err p pol `` `OaBadToken` `an empty token is refused` )

            ( string_free u_exp ) ( string_free t_exp )
            ( string_free u_bad ) ( string_free t_bad )
            ( string_free u_aud ) ( string_free t_aud )
            ( string_free u_kid ) ( string_free t_kid )
            ( string_free u_none ) ( string_free t_none )
            ( string_free u_hs ) ( string_free t_hs )
            ( string_free mintbase )

            ( oidc_policy_free pol )
            ( string_free code )
            ( string_free state )
            ( string_free nonce )
            ( pkce_free pk )
            ( oauth_config_free cfg )
            ( oidc_provider_free p )
        }
    }
}

@ main → i {
    : ArgParser ap ( args_new `client` `oauth package test` )
    ( args_opt ap `port` 112 `N` `provider port on 127.0.0.1` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }
    : ~ i port 0
    ?? ( args_value ap `port` ) {
        T v → {
            ?? ( string_to_int v ) { T x → { = port x } F _ → {} }
            ( string_free v )
        }
        F _ → {}
    }
    ( args_free ap )

    ( section `offline: PKCE` )
    ( test_pkce_vector )
    ( section `offline: JWKS` )
    ( test_jwks_offline )
    ( section `offline: callback` )
    ( test_callback_offline )
    ( section `offline: policy` )
    ( test_policy_offline )
    ( section `offline: claim shapes` )
    ( test_claims_shapes )
    ( section `offline: RSA (RS256 + PS256 vectors)` )
    ( test_rsa_offline )
    ( section `offline: EdDSA` )
    ( test_eddsa_offline )
    ( section `offline: HS256` )
    ( test_hs256_offline )

    ? > port 0 {
        : String base ( string_from `http://127.0.0.1:` )
        ( string_push_int base port )
        ( run_online ( string_data base ) )
        ( string_free base )
    } {}

    ( nurl_println `` )
    : String sum ( string_from `` )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( nurl_println ( string_data sum ) )
    ( string_free sum )
    ^ ? > g_fail 0 1 0
}
