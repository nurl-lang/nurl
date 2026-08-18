// http_jwt.nu — ext/http_jwt.nu acceptance: JWT bearer-auth middleware.
//
// Wraps a claims-aware handler with with_jwt_hs256 / with_jwt_eddsa and
// drives it through synthetic requests: valid token (handler runs, sees
// claims), missing header (401, no error= code), bad signature (401
// invalid_token), expired token (401, token expired). Tokens use a
// far-past `exp` for the expired case and no `exp` for the always-valid
// case, so results are clock-independent and deterministic.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/ext/jwt.nu`
$ `stdlib/ext/http_jwt.nu`

// Build a request carrying `Authorization: Bearer <token>` (or no auth
// header when `token` is empty).
@ mk_req s token → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method `GET` )
    ( string_push_str . req path `/secure` )
    ? > ( nurl_str_len token ) 0 {
        : String hv ( string_with_cap + ( nurl_str_len token ) 8 )
        ( string_push_str hv `Bearer ` )
        ( string_push_str hv token )
        ( vec_push [Header] . req headers ( header_new `Authorization` ( string_data hv ) ) )
        ( string_free hv )
    } {}
    ^ req
}

// Claims-aware handler: 200 with the `sub` claim echoed back.
@ secure_handler HttpRequest req Json claims → HttpResponse {
    : ?Json subo ( json_obj_get claims `sub` )
    : s sub ?? subo { T sj → ( json_str_data sj ) F _ → `<none>` }
    : String body ( string_with_cap 32 )
    ( string_push_str body `hello ` )
    ( string_push_str body sub )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( string_free body )
    ^ r
}

@ run s label ( @ HttpResponse HttpRequest ) h s token → v {
    : HttpRequest req ( mk_req token )
    : HttpResponse resp ( h req )
    ( nurl_print label ) ( nurl_print `: status=` )
    ( nurl_print ( nurl_str_int . resp status ) )
    ( nurl_print ` body=` )
    : String bs ( bytes_to_str . resp body )  // length-bounded; body Vec[u] isn't NUL-terminated
    ( nurl_print ( string_data bs ) )
    ( string_free bs )
    : ?String wa ( header_get . resp headers `WWW-Authenticate` )
    ?? wa { T w → { ( nurl_print ` www-auth=` ) ( nurl_print ( string_data w ) ) ( string_free w ) } F _ → {} }
    ( nurl_print `\n` )
    ( http_response_free resp )
    ( request_free req )
}

@ sign_claims s secret b with_exp s exp → String {
    : Json p ( json_obj_new )
    ( json_obj_set p `sub` ( json_str_lit `alice` ) )
    ? with_exp { ( json_obj_set p `exp` ( json_num_lit exp ) ) } {}
    : String tok ( jwt_hs256_sign secret p )
    ( json_free p )
    ^ tok
}

@ main → i {
    : s secret `test-secret-key`

    // The claims-aware handler is the same; only the type annotation
    // differs at the wrap site.
    : ( @ HttpResponse HttpRequest Json ) leaf \ HttpRequest req Json claims → HttpResponse { ^ ( secure_handler req claims ) }
    : ( @ HttpResponse HttpRequest ) guarded ( with_jwt_hs256 secret leaf )

    // valid (no exp → always valid)
    : String good ( sign_claims secret F `` )
    ( run `hs256_valid` guarded ( string_data good ) )
    ( string_free good )

    // expired (exp far in the past)
    : String old ( sign_claims secret T `1000` )
    ( run `hs256_expired` guarded ( string_data old ) )
    ( string_free old )

    // missing header
    ( run `hs256_missing` guarded `` )

    // tampered signature
    : String good2 ( sign_claims secret F `` )
    : String bad ( string_with_cap + ( nurl_str_len ( string_data good2 ) ) 1 )
    : i gl ( nurl_str_len ( string_data good2 ) )
    : ~ i k 0
    ~ < k gl {
        : i c ( nurl_str_get ( string_data good2 ) k )
        ( string_push_char bad ? == k - gl 1 ? == c 65 66 65 c )
        = k + k 1
    }
    ( run `hs256_tampered` guarded ( string_data bad ) )
    ( string_free bad ) ( string_free good2 )

    // wrong secret
    : String good3 ( sign_claims `other-secret` F `` )
    ( run `hs256_wrongkey` guarded ( string_data good3 ) )
    ( string_free good3 )

    // Release the wrapped + leaf closure envs (heap-captured {fn,env};
    // with_jwt_* borrows the inner closure, never frees it).
    : *u guarded_env # *u guarded 1
    ( nurl_free # s guarded_env )
    : *u leaf_env # *u leaf 1
    ( nurl_free # s leaf_env )

    // ── EdDSA ──
    : !CryptoKeypair CryptoErr kp ( ed25519_keygen )
    ?? kp {
        T k → {
            : ( @ HttpResponse HttpRequest Json ) eleaf \ HttpRequest req Json claims → HttpResponse { ^ ( secure_handler req claims ) }
            : ( @ HttpResponse HttpRequest ) eguarded ( with_jwt_eddsa . k pk eleaf )
            : Json ep ( json_obj_new )
            ( json_obj_set ep `sub` ( json_str_lit `bob` ) )
            : !String CryptoErr eso ( jwt_eddsa_sign . k sk ep )
            ( json_free ep )
            ?? eso {
                T etok → {
                    ( run `eddsa_valid` eguarded ( string_data etok ) )
                    ( string_free etok )
                }
                F _ → ( nurl_print `eddsa sign FAILED\n` )
            }
            ( run `eddsa_missing` eguarded `` )
            : *u eguarded_env # *u eguarded 1
            ( nurl_free # s eguarded_env )
            : *u eleaf_env # *u eleaf 1
            ( nurl_free # s eleaf_env )
            ( vec_free [u] . k sk ) ( vec_free [u] . k pk )
        }
        F _ → ( nurl_print `keygen FAILED\n` )
    }

    // ── ES256 ──
    : !( Vec u ) ParseErr es_sr ( bytes_from_hex `c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721` )
    : ( Vec u ) es_scalar ?? es_sr { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) es_pub ( p256_ecdh_keygen es_scalar )
    : ( @ HttpResponse HttpRequest Json ) esleaf \ HttpRequest req Json claims → HttpResponse { ^ ( secure_handler req claims ) }
    : ( @ HttpResponse HttpRequest ) esguarded ( with_jwt_es256 es_pub esleaf )
    : Json esp ( json_obj_new )
    ( json_obj_set esp `sub` ( json_str_lit `carol` ) )
    : !String CryptoErr esso ( jwt_es256_sign es_scalar esp )
    ( json_free esp )
    ?? esso {
        T estok → {
            ( run `es256_valid` esguarded ( string_data estok ) )
            ( string_free estok )
        }
        F _ → ( nurl_print `es256 sign FAILED\n` )
    }
    ( run `es256_missing` esguarded `` )
    : *u esguarded_env # *u esguarded 1
    ( nurl_free # s esguarded_env )
    : *u esleaf_env # *u esleaf 1
    ( nurl_free # s esleaf_env )
    ( vec_free [u] es_scalar ) ( vec_free [u] es_pub )

    ^ 0
}
