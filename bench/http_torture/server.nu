// bench/http_torture/server.nu — variable-body HTTP server for the
// torture harness. The peer of bench/http_torture/rust (hyper/rustls).
//
// Routes (plaintext OR TLS, same handlers):
//   GET /     → 14-byte  "Hello, World!\n"   (parity with the peer bench)
//   GET /1k   → exactly   1024 bytes
//   GET /16k  → exactly  16384 bytes
//   GET /1m   → exactly 1048576 bytes
//
// Each sized body is built ONCE at startup and the response BORROWS it
// per request (`response_set_body_borrowed_bytes` — no copy) — the same
// shape the Rust peer uses (a precomputed Bytes cloned per response, a
// refcount bump), so the measurement compares the servers, not two
// body-construction strategies. The bodies are main's locals and outlive
// every request, which is exactly the borrowed-body contract.
//
// Args mirror bench/http_server.nu:
//   (no args)                     → plaintext on 127.0.0.1:18080
//   <port> <cert.pem> <key.pem>   → TLS on that port
//
// Worker count: NURL_WORKERS env (0 = one per core, the deploy default).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `packages/http/src/http.nu`

@ __mkbody i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] v # u 120 )   // 'x'
        = i + i 1
    }
    ^ v
}

@ __sized i status ( Vec u ) body → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `application/octet-stream` )
    ( response_set_body_borrowed_bytes r body )
    ^ r
}

@ main → i {
    : ( Vec u ) b1k ( __mkbody 1024 )
    : ( Vec u ) b16k ( __mkbody 16384 )
    : ( Vec u ) b1m ( __mkbody 1048576 )

    : *HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_get a `/` \ HttpRequest req Params params → HttpResponse {
        ^ ( response_text 200 `Hello, World!\n` )
    } )
    ( http_app_get a `/1k` \ HttpRequest req Params params → HttpResponse {
        ^ ( __sized 200 b1k )
    } )
    ( http_app_get a `/16k` \ HttpRequest req Params params → HttpResponse {
        ^ ( __sized 200 b16k )
    } )
    ( http_app_get a `/1m` \ HttpRequest req Params params → HttpResponse {
        ^ ( __sized 200 b1m )
    } )
    ( http_app_async a 0 )

    : i argc ( nurl_argv_count )
    : ~ i rc 0
    ? >= argc 4 {
        : i port ( nurl_str_to_int ( nurl_argv_get 1 ) )
        : s cert ( nurl_argv_get 2 )
        : s key ( nurl_argv_get 3 )
        = rc ( http_app_listen_tls a `127.0.0.1` port cert key )
    } {
        = rc ( http_app_listen a `127.0.0.1` 18080 )
    }
    ( http_app_free a )
    ( vec_free [u] b1k )
    ( vec_free [u] b16k )
    ( vec_free [u] b1m )
    ^ rc
}
