// tests/client.nu — drive the HttpClient facade against the test server
// (tests/server.nu) and print one PASS/FAIL line per behaviour. The shell
// harness (client_test.sh) starts the server on a plaintext and a TLS
// port and passes both here; this program does every assertion itself.
//
//   client --http-port N --https-port N

$ `stdlib/std/args.nu`
$ `stdlib/std/bytes.nu`
$ `../src/http_client.nu`

: ~ i pass 0
: ~ i fail 0

@ ok s name → v { ( nurl_print `  PASS ` ) ( nurl_println name ) = pass + pass 1 }

@ bad s name s detail → v {
    ( nurl_print `  FAIL ` ) ( nurl_print name ) ( nurl_print ` — ` ) ( nurl_println detail )
    = fail + fail 1
}

@ base s scheme i port s path → String {
    : String u ( string_from scheme )
    ( string_push_str u `://127.0.0.1:` )
    ( string_push_int u port )
    ( string_push_str u path )
    ^ u
}

// GET `path`, assert status and that the body contains `want` (or "" to
// skip the body check). `proto_want` 0 = any, else 1 h1 / 2 h2.
@ check_get * HttpClient c s name s scheme i port s path i status_want s want i proto_want → v {
    : String url ( base scheme port path )
    ?? ( http_client_get c ( string_data url ) ) {
        T r → {
            : String body ( http_client_body_str r )
            : b st == . r status status_want
            : b bm | == ( nurl_str_len want ) 0 >= ( nurl_str_find ( string_data body ) want ) 0
            : b pm | == proto_want 0 == ( http_client_last_proto c ) proto_want
            ? & & st bm pm { ( ok name ) } {
                : String d ( string_new )
                ( string_push_str d `status=` ) ( string_push_int d . r status )
                ( string_push_str d ` proto=` ) ( string_push_int d ( http_client_last_proto c ) )
                ( string_push_str d ` body=[` ) ( string_push_str d ( string_data body ) ) ( string_push_str d `]` )
                ( bad name ( string_data d ) )
                ( string_free d )
            }
            ( string_free body )
            ( http_response_free r )
        }
        F e → { ( bad name ( http_client_err_name e ) ) }
    }
    ( string_free url )
}

@ run i http_port i https_port → v {
    : *HttpClient c ( http_client_new )
    ( http_client_set_verify c F )  // self-signed test cert

    // ── plaintext HTTP/1.1 ──
    ( check_get c `h1_root` `http` http_port `/` 200 `root` 1 )
    ( check_get c `h1_reuse` `http` http_port `/dest` 200 `arrived` 1 )  // second req, pooled conn

    // ── User-Agent default ──
    : String uurl ( base `http` http_port `/ua` )
    ?? ( http_client_get c ( string_data uurl ) ) {
        T r → {
            : String b ( http_client_body_str r )
            ? >= ( nurl_str_find ( string_data b ) `nurl-http-client` ) 0 { ( ok `default_user_agent` ) } { ( bad `default_user_agent` ( string_data b ) ) }
            ( string_free b ) ( http_response_free r )
        }
        F e → { ( bad `default_user_agent` ( http_client_err_name e ) ) }
    }
    ( string_free uurl )

    // ── redirect chain (302 → 302 → 200) ──
    ( check_get c `redirect_chain` `http` http_port `/redir1` 200 `arrived` 0 )
    // relative redirect from a subpath merges against the base directory
    ( check_get c `relative_redirect` `http` http_port `/a/b/deep` 200 `sibling` 0 )

    // ── redirect cap ──
    ( http_client_set_max_redirects c 0 )
    : String rurl ( base `http` http_port `/redir1` )
    ?? ( http_client_get c ( string_data rurl ) ) {
        T r → { ( bad `redirect_cap` `expected error` ) ( http_response_free r ) }
        F e → { ?? e { HcTooManyRedirects → { ( ok `redirect_cap` ) } _ → { ( bad `redirect_cap` ( http_client_err_name e ) ) } } }
    }
    ( string_free rurl )
    ( http_client_set_max_redirects c 10 )

    // ── cookies: set on one request, sent on the next ──
    : String surl ( base `http` http_port `/setcookie` )
    ?? ( http_client_get c ( string_data surl ) ) { T r → ( http_response_free r ) F _ → {} }
    ( string_free surl )
    ( check_get c `cookie_roundtrip` `http` http_port `/readcookie` 200 `sid=abc123` 0 )

    // ── gzip body decoded transparently ──
    ( check_get c `gzip_decode` `http` http_port `/gzip` 200 `lazy dog` 0 )

    // ── POST body echo (h1) ──
    : String eurl ( base `http` http_port `/echo` )
    : ( Vec u ) body ( bytes_from_str `hello-post` )
    ?? ( http_client_post c ( string_data eurl ) body `text/plain` ) {
        T r → {
            : String b ( http_client_body_str r )
            ? ( nurl_str_eq ( string_data b ) `hello-post` ) { ( ok `post_echo` ) } { ( bad `post_echo` ( string_data b ) ) }
            ( string_free b ) ( http_response_free r )
        }
        F e → { ( bad `post_echo` ( http_client_err_name e ) ) }
    }
    ( vec_free [u] body )
    ( string_free eurl )

    // ── TLS: ALPN picks HTTP/2, PQ key exchange, then h2 features ──
    ? > https_port 0 {
        ( check_get c `h2_root` `https` https_port `/` 200 `root` 2 )
        ? ( http_client_last_pq c ) { ( ok `h2_post_quantum` ) } { ( bad `h2_post_quantum` `classical kx` ) }
        ( check_get c `h2_reuse` `https` https_port `/dest` 200 `arrived` 2 )  // multiplexed reuse
        ( check_get c `h2_gzip` `https` https_port `/gzip` 200 `lazy dog` 2 )
        // cookies over h2
        : String s2 ( base `https` https_port `/setcookie` )
        ?? ( http_client_get c ( string_data s2 ) ) { T r → ( http_response_free r ) F _ → {} }
        ( string_free s2 )
        ( check_get c `h2_cookie` `https` https_port `/readcookie` 200 `sid=abc123` 2 )
    } {}

    ( http_client_free c )
}

@ main → i {
    : ArgParser ap ( args_new `client` `http-client facade test` )
    ( args_opt ap `http-port` 104 `N` `plaintext port` )
    ( args_opt ap `https-port` 115 `N` `TLS port` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }
    : ~ i hp 0
    : ~ i sp 0
    ?? ( args_value ap `http-port` ) { T v → { ?? ( string_to_int v ) { T x → = hp x F _ → {} } ( string_free v ) } F _ → {} }
    ?? ( args_value ap `https-port` ) { T v → { ?? ( string_to_int v ) { T x → = sp x F _ → {} } ( string_free v ) } F _ → {} }
    ( args_free ap )
    ( run hp sp )
    ( nurl_print `== client tests: PASS=` ) ( nurl_print_int pass )
    ( nurl_print ` FAIL=` ) ( nurl_print_int fail ) ( nurl_print `\n` )
    ^ ? == fail 0 0 1
}
