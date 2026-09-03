// tests/server.nu — a small server built on the `http` package that the
// client test drives. Same binary serves plaintext (HTTP/1.1) and, with
// --tls, TLS (HTTP/2 or HTTP/1.1 by ALPN). Routes exercise every facade
// feature: protocol echo, User-Agent echo, a redirect chain, cookies,
// and a gzip-encoded body.
//
//   server --port N [--tls --cert P --key P]

$ `stdlib/std/args.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/compress.nu`
$ `../../http/src/http.nu`

@ h_root HttpRequest req Params p → HttpResponse {
    ^ ( response_text 200 `root` )
}

@ h_ua HttpRequest req Params p → HttpResponse {
    : String out ( string_from `ua=` )
    ?? ( header_get . req headers `User-Agent` ) {
        T v → { ( string_push_str out ( string_data v ) ) ( string_free v ) }
        F _ → { ( string_push_str out `(none)` ) }
    }
    : HttpResponse r ( response_text 200 ( string_data out ) )
    ( string_free out )
    ^ r
}

// /redir1 → 302 /redir2 → 302 /dest
@ h_redir1 HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 302 )
    ( response_set_header r `Location` `/redir2` )
    ^ r
}

@ h_redir2 HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 302 )
    ( response_set_header r `Location` `/dest` )
    ^ r
}

@ h_dest HttpRequest req Params p → HttpResponse {
    ^ ( response_text 200 `arrived` )
}

// A relative redirect from a subpath (RFC 3986 §5.2 merge).
@ h_deep_redir HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 302 )
    ( response_set_header r `Location` `sib` )
    ^ r
}

@ h_deep_sib HttpRequest req Params p → HttpResponse {
    ^ ( response_text 200 `sibling` )
}

// POST that a 303 turns into a bodyless GET.
@ h_post303 HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 303 )
    ( response_set_header r `Location` `/dest` )
    ^ r
}

@ h_setcookie HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_text 200 `set` )
    ( response_set_header r `Set-Cookie` `sid=abc123; Path=/` )
    ^ r
}

@ h_readcookie HttpRequest req Params p → HttpResponse {
    : String out ( string_from `cookie=` )
    ?? ( header_get . req headers `Cookie` ) {
        T v → { ( string_push_str out ( string_data v ) ) ( string_free v ) }
        F _ → { ( string_push_str out `(none)` ) }
    }
    : HttpResponse r ( response_text 200 ( string_data out ) )
    ( string_free out )
    ^ r
}

@ h_gzip HttpRequest req Params p → HttpResponse {
    : ( Vec u ) plain ( bytes_from_str `the quick brown fox jumps over the lazy dog` )
    : HttpResponse r ( response_new 200 )
    ?? ( gzip_compress plain ) {
        T gz → {
            ( response_set_header r `Content-Encoding` `gzip` )
            ( response_set_body_bytes r gz )
            ( vec_free [u] gz )
        }
        F _ → { ( response_set_body_bytes r plain ) }
    }
    ( vec_free [u] plain )
    ^ r
}

@ h_echo_body HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_body_bytes r . req body )
    ^ r
}

@ routes * HttpApp a → v {
    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse { ^ ( h_root req p ) } )
    ( http_app_get a `/ua` \ HttpRequest req Params p → HttpResponse { ^ ( h_ua req p ) } )
    ( http_app_get a `/redir1` \ HttpRequest req Params p → HttpResponse { ^ ( h_redir1 req p ) } )
    ( http_app_get a `/redir2` \ HttpRequest req Params p → HttpResponse { ^ ( h_redir2 req p ) } )
    ( http_app_get a `/dest` \ HttpRequest req Params p → HttpResponse { ^ ( h_dest req p ) } )
    ( http_app_get a `/a/b/deep` \ HttpRequest req Params p → HttpResponse { ^ ( h_deep_redir req p ) } )
    ( http_app_get a `/a/b/sib` \ HttpRequest req Params p → HttpResponse { ^ ( h_deep_sib req p ) } )
    ( http_app_post a `/post303` \ HttpRequest req Params p → HttpResponse { ^ ( h_post303 req p ) } )
    ( http_app_get a `/setcookie` \ HttpRequest req Params p → HttpResponse { ^ ( h_setcookie req p ) } )
    ( http_app_get a `/readcookie` \ HttpRequest req Params p → HttpResponse { ^ ( h_readcookie req p ) } )
    ( http_app_get a `/gzip` \ HttpRequest req Params p → HttpResponse { ^ ( h_gzip req p ) } )
    ( http_app_post a `/echo` \ HttpRequest req Params p → HttpResponse { ^ ( h_echo_body req p ) } )
}

@ main → i {
    : ArgParser ap ( args_new `server` `http-client test server` )
    ( args_opt ap `port` 112 `N` `bind port on 127.0.0.1` )
    ( args_flag ap `tls` 116 `serve TLS` )
    ( args_opt ap `cert` 99 `P` `cert PEM` )
    ( args_opt ap `key` 107 `P` `key PEM` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }

    : ~ i port 0
    ?? ( args_value ap `port` ) {
        T v → { ?? ( string_to_int v ) { T x → { = port x } F _ → {} } ( string_free v ) }
        F _ → {}
    }

    : *HttpApp a ( http_app_new )
    ( http_app_quiet a )
    // The TLS listener keeps its UDP/QUIC twin and its Alt-Svc: the
    // client's HTTP/3 path is driven against it.
    ( routes a )

    : ~ i rc 0
    ? ( args_present ap `tls` ) {
        : String cert ( args_value_or ap `cert` `` )
        : String key ( args_value_or ap `key` `` )
        = rc ( http_app_listen_tls a `127.0.0.1` port ( string_data cert ) ( string_data key ) )
        ( string_free cert ) ( string_free key )
    } {
        = rc ( http_app_listen a `127.0.0.1` port )
    }
    ( http_app_free a )
    ( args_free ap )
    ^ rc
}
