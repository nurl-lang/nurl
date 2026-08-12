// bench/http_server.nu — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3), built on the packages/http
// facade (the unified HTTP server interface — what a real NURL service
// would use), so the bench measures the surface users actually deploy.
//
// Two modes, one binary — the bench harness runs both:
//   * No arguments  → plaintext HTTP on 127.0.0.1:18080 (the default;
//                     unchanged from the original single-mode server).
//   * `<port> <cert.pem> <key.pem>` → HTTPS/TLS on that port, via the
//                     same HttpApp facade's `http_app_listen_tls`. cert
//                     and key are PEM paths (EC or RSA leaf).
//
// Serves "Hello, World!\n" (14 bytes, text/plain) on `/`. No metrics,
// no access log — apples-to-apples with the Rust/Node sibling files in
// this directory. Ctrl+C (or SIGTERM) shuts down cleanly.
//
// Run: ./bench/run_http.sh  (compiles + starts both modes; see that
//                            script for the bench driver glue).

$ `stdlib/core/string.nu`
$ `packages/http/src/http.nu`

@ main → i {
    : *HttpApp a ( http_app_new )
    ( http_app_get a `/` \ HttpRequest req Params params → HttpResponse {
        ^ ( response_text 200 `Hello, World!\n` )
    } )
    // Worker pool so the bench measures the full server surface rather
    // than a single accept loop. 10 workers is a reasonable default for
    // ~12-core hosts (tokio's default multi-thread runtime in the Rust
    // peer uses every core).
    ( http_app_workers a 10 )

    // TLS mode when three arguments are supplied (port, cert, key);
    // otherwise the original plaintext default. argv[0] is the program
    // name, so a TLS invocation has argc == 4.
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
    ^ rc
}
