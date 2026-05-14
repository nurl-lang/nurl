// headers_blob.nu — offline tests for stdlib/ext/http.nu.
//
// No network access. Exercises:
//   * header_blob_one — single-line "Name: Value\r\n" builder
//   * http_request    — empty URL must surface as HttpInvalidUrl
//                       without contacting the network
//   * http_post       — content-type-aware wrapper, same offline path
//   * http_err_name   — diagnostic helper

$ `stdlib/ext/http.nu`

@ check_invalid_url ! Response HttpErr res s tag → v {
    ?? res {
        T r → {
            ( nurl_print_str `unexpected: live response on empty URL` )
            ( response_free r )
        }
        F e → {
            : HttpErr he # HttpErr e
            : s name ( http_err_name he )
            ( nurl_print tag )
            ( nurl_print `: ` )
            ( nurl_print_str name )
        }
    }
}

@ main → i {
    // ── 1. header_blob_one ───────────────────────────────────────
    : String h ( header_blob_one `Authorization` `Bearer xyz` )
    ( nurl_print `blob: ` )
    ( nurl_print ( string_data h ) )
    // header_blob_one already terminates with \r\n. Print a trailing
    // marker so the baseline captures stable bytes regardless of
    // terminal CR handling.
    ( nurl_print_str `END` )
    ( nurl_print `len=` )
    ( nurl_print_int ( string_len h ) )
    ( nurl_print `\n` )
    ( string_free h )

    // ── 2. http_request with empty URL → HttpInvalidUrl ──────────
    : !Response HttpErr r1 ( http_request `GET` `` `` `` )
    ( check_invalid_url r1 `http_request` )

    // ── 3. http_get with empty URL → HttpInvalidUrl ──────────────
    : !Response HttpErr r2 ( http_get `` )
    ( check_invalid_url r2 `http_get` )

    // ── 4. http_post with content-type, empty URL → HttpInvalidUrl
    //      (also exercises __with_ct path).
    : !Response HttpErr r3 ( http_post `` `payload` `application/json` )
    ( check_invalid_url r3 `http_post+ct` )

    // ── 5. http_post_with_headers (content-type + extra headers) ─
    : !Response HttpErr r4
    ( http_post_with_headers `` `body` `application/json`
    `X-Trace: abc\r\nX-Span: 1\r\n` )
    ( check_invalid_url r4 `http_post_with_headers` )

    // ── 6. http_put / http_patch / http_delete ───────────────────
    : !Response HttpErr r5 ( http_put `` `b` `text/plain` )
    ( check_invalid_url r5 `http_put` )
    : !Response HttpErr r6 ( http_patch `` `b` `text/plain` )
    ( check_invalid_url r6 `http_patch` )
    : !Response HttpErr r7 ( http_delete `` )
    ( check_invalid_url r7 `http_delete` )

    // ── 7. http_err_name renders all variants ────────────────────
    ( nurl_print_str ( http_err_name # HttpErr HttpConnect ) )
    ( nurl_print_str ( http_err_name # HttpErr HttpTimeout ) )
    ( nurl_print_str ( http_err_name # HttpErr HttpTls ) )
    ( nurl_print_str ( http_err_name # HttpErr HttpDns ) )
    ( nurl_print_str ( http_err_name # HttpErr HttpInvalidUrl ) )
    ( nurl_print_str ( http_err_name # HttpErr HttpOther ) )

    ^ 0
}
