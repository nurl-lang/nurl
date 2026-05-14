// http_basic.nu — live HTTP smoke test (network-gated).
//
// Skipped by run_tests.{bat,sh} unless NURL_HTTP_TESTS=1, because it
// reaches httpbin.org. When the gate is on, this exercises:
//   * http_get          — anonymous GET, status + non-empty body
//   * http_get_with_headers — extra header round-trips back via /headers
//   * http_post         — POST with content-type
//   * http_post_with_headers — POST with content-type + extra header
//   * http_put / http_patch / http_delete — non-default verbs
//   * http_post_json    — JSON convenience wrapper
//
// Manual run:
//   NURL_HTTP_TESTS=1 ./build.sh         (Linux/macOS)
//   set NURL_HTTP_TESTS=1 & build.bat    (Windows cmd)

$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_json.nu`
$ `stdlib/ext/json.nu`

@ show s tag ! Response HttpErr res → v {
    ?? res {
        T r → {
            ( nurl_print tag )
            ( nurl_print ` status=` )
            ( nurl_print_int ( http_status r ) )
            ( nurl_print ` bytes>0=` )
            ( nurl_print ?
            > ( nurl_str_len ( http_body_str r ) ) 0 `T` `F` )
            ( nurl_print `\n` )
            ( response_free r )
        }
        F e → {
            ( nurl_print tag )
            ( nurl_print ` ERR=` )
            ( nurl_print_str ( http_err_name # HttpErr e ) )
        }
    }
}

@ main → i {
    ( show `GET     ` ( http_get `https://httpbin.org/get` ) )

    ( show `GET+H   `
    ( http_get_with_headers `https://httpbin.org/headers`
    `X-Nurl-Probe: hi\r\n` ) )

    ( show `POST    `
    ( http_post `https://httpbin.org/post` `hello` `text/plain` ) )

    ( show `POST+H  `
    ( http_post_with_headers `https://httpbin.org/post` `payload`
    `text/plain` `X-Nurl-Probe: hi\r\n` ) )

    ( show `PUT     `
    ( http_put `https://httpbin.org/put` `data` `text/plain` ) )

    ( show `PATCH   `
    ( http_patch `https://httpbin.org/patch` `data` `text/plain` ) )

    ( show `DELETE  `
    ( http_delete `https://httpbin.org/delete` ) )

    // http_post_json — build a small JSON object and post it.
    : Json arr ( json_arr_new )
    ( json_arr_push arr ( json_int 1 ) )
    ( json_arr_push arr ( json_int 2 ) )
    : Json obj ( json_obj_new )
    ( json_obj_set obj `name` ( json_str_lit `nurl` ) )
    ( json_obj_set obj `nums` arr )
    ( show `POST_JSN`
    ( http_post_json `https://httpbin.org/post` obj ) )
    ( json_free obj )

    ^ 0
}
