// examples/fetch.nu — a tiny curl-like fetcher on the HttpClient facade.
//
// One argument, a URL; prints the negotiated protocol and whether the
// key exchange was post-quantum, then the response body. The client
// picks HTTP/2 or HTTP/1.1 by ALPN, resumes TLS sessions, follows
// redirects, carries cookies and decodes gzip — none of it configured.
//
//   nurlpkg install http-client        # then:  fetch https://example.org/
//   # or in a checkout:
//   ./nurl.sh packages/http-client/examples/fetch.nu /tmp/fetch
//   /tmp/fetch https://example.org/

$ `stdlib/std/args.nu`
$ `../src/http_client.nu`

@ proto_name i p → s {
    ? == p 2 { ^ `HTTP/2` } {}
    ? == p 1 { ^ `HTTP/1.1` } {}
    ^ `none`
}

@ main → i {
    : ArgParser ap ( args_new `fetch` `fetch a URL with the HttpClient facade` )
    ( args_flag ap `insecure` 107 `skip TLS verification` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }
    : ( Vec String ) pos ( args_positionals ap )
    ? == ( vec_len [String] pos ) 0 {
        ( nurl_eprintln `usage: fetch [--insecure] <url>` )
        ( args_free ap )
        ^ 2
    } {}
    : String url ( __fetch_at pos 0 )

    : *HttpClient c ( http_client_new )
    ? ( args_present ap `insecure` ) { ( http_client_set_verify c F ) } {}

    : ~ i rc 0
    ?? ( http_client_get c ( string_data url ) ) {
        T r → {
            ( nurl_print `# ` )
            ( nurl_print ( proto_name ( http_client_last_proto c ) ) )
            ? ( http_client_last_pq c ) { ( nurl_print ` (post-quantum)` ) } {}
            ( nurl_print ` — status ` )
            ( nurl_print_int ( http_client_status r ) )
            ( nurl_print `\n` )
            : String body ( http_client_body_str r )
            ( nurl_print ( string_data body ) )
            ( nurl_print `\n` )
            ( string_free body )
            ( http_response_free r )
        }
        F e → {
            ( nurl_eprintln ( http_client_err_name e ) )
            = rc 1
        }
    }
    ( http_client_free c )
    ( args_free ap )
    ^ rc
}

@ __fetch_at ( Vec String ) v i idx → String {
    ?? ( vec_get [String] v idx ) { T s → ^ s F _ → ^ ( string_new ) }
}
