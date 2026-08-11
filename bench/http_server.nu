// bench/http_server.nu — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3), built on the packages/http
// facade (the unified HTTP server interface — what a real NURL service
// would use), so the bench measures the surface users actually deploy.
//
// Listens on 127.0.0.1:18080. Serves "Hello, World!\n" (14 bytes,
// text/plain) on `/`. No metrics, no access log — apples-to-apples
// with the Go/Rust/Node sibling files in this directory. Ctrl+C (or
// SIGTERM) shuts down cleanly.
//
// Run: ./bench/run_http.sh  (compiles + starts; see that script
//                            for the bench driver glue).

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
    : i rc ( http_app_listen a `127.0.0.1` 18080 )
    ( http_app_free a )
    ^ rc
}
