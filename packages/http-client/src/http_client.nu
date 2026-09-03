// http-client — the unified HTTP client interface library for NURL.
//
// One include gives a consumer:
//
//   * the stdlib client surface — pure-NURL TLS 1.3 (X25519MLKEM768
//     hybrid key exchange, ML-DSA and classical certificate chains),
//     the HTTP/1.1 client, the HTTP/2 client, the RFC 6265 cookie jar,
//     gzip / deflate — and
//   * the `HttpClient` facade (client.nu) that wires them into one
//     object which speaks whatever the server offers.
//
// Usage from a dependent package:
//
//     $ `deps/http-client/src/http_client.nu`
//
//     @ main → i {
//         : *HttpClient c ( http_client_new )
//         ?? ( http_client_get c `https://example.org/` ) {
//             T r → {
//                 ( nurl_print_int . r status )
//                 ( http_response_free r )
//             }
//             F e → { ( nurl_eprintln ( http_client_err_name e ) ) }
//         }
//         ( http_client_free c )
//         ^ 0
//     }
//
// The intent mirrors the `http` package on the server side: this is THE
// dependency anything needing an HTTP client reaches for.

$ `client.nu`
