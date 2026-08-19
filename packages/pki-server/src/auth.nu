// pki-server/src/auth.nu — API Key & device key authentication helpers.
//
// Every comparison here is between a client-supplied string and a
// server secret, so all of them go through std/subtle.nu's
// constant_time_eq. `string_eq` and `nurl_str_cmp` stop at the first
// differing byte, which turns each request into a measurement of how
// many leading bytes were right — enough to recover a key byte-by-byte
// over a few thousand requests.
//
// The empty key is treated as "no key configured" and DENIES rather
// than admits: main.nu never leaves one empty (it mints a random key
// when none is given), so reaching here with one means the process is
// misconfigured, and open-by-default is the wrong answer to that.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_auth.nu`

// Check if request carries a valid Management API key.
@ auth_check_api_key HttpRequest req s management_key → b {
    ? == ( nurl_str_len management_key ) 0 { ^ F } {}

    // Every candidate is checked, and the result is accumulated rather
    // than returned early, so the number of comparisons a request costs
    // does not depend on which header happened to hold the right key.
    : ~ b ok F

    // 1. Query parameter `api_key`
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [QueryPair] pairs k ) {
            T pr → {
                ? == 0 ( nurl_str_cmp ( string_data . pr key ) `api_key` ) {
                    ? ( constant_time_eq ( string_data . pr value ) management_key ) { = ok T } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( query_pairs_free pairs )

    // 2. X-API-Key header
    : ?String x_api ( header_get . req headers `x-api-key` )
    ?? x_api {
        T key_val → {
            ? ( constant_time_eq ( string_data key_val ) management_key ) { = ok T } {}
            ( string_free key_val )
        }
        F _ → {}
    }

    // 3. Authorization: Bearer <key>
    : ?String bearer ( parse_bearer_auth req )
    ?? bearer {
        T token → {
            ? ( constant_time_eq ( string_data token ) management_key ) { = ok T } {}
            ( string_free token )
        }
        F _ → {}
    }

    ^ ok
}

// Check a key supplied in a request body (form field or JSON member)
// against the management key.
@ auth_check_api_key_value s provided_key s management_key → b {
    ? == ( nurl_str_len management_key ) 0 { ^ F } {}
    ^ ( constant_time_eq provided_key management_key )
}

// Check if provided initialization key matches configured key.
@ auth_check_device_key s provided_key s expected_key → b {
    ? == ( nurl_str_len expected_key ) 0 { ^ F } {}
    ^ ( constant_time_eq provided_key expected_key )
}
