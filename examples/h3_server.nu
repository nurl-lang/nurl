// examples/h3_server.nu — one HttpApp, three HTTP versions on one port.
//
// `http_app_listen_tls` serves HTTP/1.1 and HTTP/2 (ALPN) over TCP and
// HTTP/3 over QUIC on the same host:port bound over UDP; the TCP
// responses carry `Alt-Svc: h3=":port"` so a browser or curl moves to
// HTTP/3 on its next request. Nothing here is HTTP/3-specific — the
// route below answers on all three.
//
//   ./nurl.sh examples/h3_server.nu build/h3_server
//   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
//       -keyout key.pem -out cert.pem -days 30 -subj "/CN=localhost"
//   build/h3_server 8443 cert.pem key.pem
//   curl -k --http3 https://127.0.0.1:8443/          # a curl built with HTTP/3
//   curl -k --http2 -D - https://127.0.0.1:8443/     # see the Alt-Svc header
//
// `http_app_set_http3 a 0` keeps a TLS listener TCP-only.

$ `stdlib/core/string.nu`
$ `packages/http/src/http.nu`

@ main → i {
    : *HttpApp a ( http_app_new )
    ( http_app_get a `/` \ HttpRequest req Params params → HttpResponse {
        : String body ( string_from `hello over ` )
        ( string_push_str body ( string_data . req version ) )
        ( string_push_str body `\n` )
        : HttpResponse r ( response_text 200 ( string_data body ) )
        ( string_free body )
        ^ r
    } )
    : i argc ( nurl_argv_count )
    : ~ i rc 0
    ? < argc 4 {
        ( nurl_eprintln `usage: h3_server <port> <cert.pem> <key.pem>` )
        = rc 2
    } {
        = rc ( http_app_listen_tls a `0.0.0.0` ( nurl_str_to_int ( nurl_argv 1 ) ) ( nurl_argv 2 ) ( nurl_argv 3 ) )
    }
    ( http_app_free a )
    ^ rc
}
