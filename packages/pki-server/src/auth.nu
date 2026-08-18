// pki-server/src/auth.nu — API Key & Device Key authentication helpers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_auth.nu`

// Check if request carries a valid Management API key
@ auth_check_api_key HttpRequest req s management_key → b {
    ? == ( nurl_str_len management_key ) 0 { ^ T } {}

    // 1. Check query parameter `api_key`
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    : ~ b q_found F
    ~ < k n {
        : ?QueryPair po ( vec_get [QueryPair] pairs k )
        ?? po {
            T pr → {
                ? ( string_eq . pr key ( string_from `api_key` ) ) {
                    ? ( string_eq . pr value ( string_from management_key ) ) {
                        = q_found T
                    } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( query_pairs_free pairs )
    ? q_found { ^ T } {}

    // 2. Check X-API-Key header
    : ?String x_api ( header_get . req headers `x-api-key` )
    ?? x_api {
        T key_val → {
            : b eq ( string_eq key_val ( string_from management_key ) )
            ( string_free key_val )
            ? eq { ^ T } {}
        }
        F _ → {}
    }

    // 3. Check Authorization: Bearer <key>
    : ?String bearer ( parse_bearer_auth req )
    ?? bearer {
        T token → {
            : b eq ( string_eq token ( string_from management_key ) )
            ( string_free token )
            ? eq { ^ T } {}
        }
        F _ → {}
    }

    ^ F
}

// Check if provided initialization key matches configured key
@ auth_check_device_key s provided_key s expected_key → b {
    ? == ( nurl_str_len expected_key ) 0 { ^ T } {}
    ^ == 0 ( nurl_str_cmp provided_key expected_key )
}
