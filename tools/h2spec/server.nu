// tools/h2spec/server.nu — the HTTP/2 conformance-gate server.
//
// The plain `packages/http` HttpApp facade — the surface a NURL service
// deploys — with one route, so what tools/h2spec_gate.sh measures is the
// HTTP/2 that every HttpApp gets, not a purpose-built endpoint.
//
//   server <port>                     plaintext on 127.0.0.1:<port>
//                                     (HTTP/1.1 + HTTP/2 prior knowledge)
//   server <port> <cert.pem> <key.pem>  TLS on 127.0.0.1:<port>, ALPN
//                                     "h2 http/1.1"
//
// The body is deliberately ≥ 5 bytes: h2spec §6.9.2/2 ("SETTINGS frame
// for window size to be negative") runs only when `dataLen >= 5`, and a
// skipped case would count as passed. Ctrl+C / SIGTERM shuts down.

$ `stdlib/core/string.nu`
$ `packages/http/src/http.nu`

@ main → i {
    : *HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_get a `/` \ HttpRequest req Params params → HttpResponse {
        ^ ( response_text 200 `hello from the gate\n` )
    } )
    ( http_app_async a 0 )
    : i argc ( nurl_argv_count )
    : ~ i rc 0
    ? < argc 2 {
        ( nurl_eprintln `usage: server <port> [cert.pem key.pem]` )
        = rc 2
    } {
        : i port ( nurl_str_to_int ( nurl_argv 1 ) )
        ? >= argc 4 {
            = rc ( http_app_listen_tls a `127.0.0.1` port ( nurl_argv 2 ) ( nurl_argv 3 ) )
        } {
            = rc ( http_app_listen a `127.0.0.1` port )
        }
    }
    ( http_app_free a )
    ^ rc
}
