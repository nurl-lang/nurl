// http — the unified HTTP server interface library for NURL.
//
// One include gives a consumer both:
//
//   * the complete stdlib HTTP surface (sockets + TLS, request parser,
//     response builder, keep-alive server with pools & DoS limits, router,
//     static files, auth / jwt / multipart / middleware / websocket), via
//     the `http_full` aggregator; and
//   * the ergonomic `HttpApp` facade (app.nu) that wires those pieces into
//     a running server in a few calls.
//
// Usage from a dependent package:
//
//     $ `deps/http/src/http.nu`
//
//     @ main → i {
//         : *HttpApp a ( http_app_new )
//         ( http_get a `/` \ HttpRequest req Params p → HttpResponse {
//             ^ ( response_text 200 `hello` )
//         } )
//         ^ ( http_listen a `127.0.0.1` 8080 )
//     }
//
// The intent is that this package is THE dependency anything needing an
// HTTP server reaches for — complete enough to stand in for hand-wired
// servers such as the anomaly service or the nurlapi playground server.

$ `stdlib/ext/http_full.nu`
$ `app.nu`
