// httpc_url_guard.nu — regression test for Agora #166: stdlib/ext/http_cli.nu
// hands curl only http(s) URLs, as an operand after `--`, with globbing off
// and both the request and its redirects restricted to HTTP(S).
// requires: live curl

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_cli.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ show_ok s label s url → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_println ? ( httpc_url_ok url ) `T` `F` )
}

@ show_get s label s url → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ?? ( httpc_get url ) {
        T r → {
            ( nurl_print `status ` )
            ( nurl_print_int ( httpc_status r ) )
            ( nurl_print ` body ` )
            ( nurl_println ( httpc_body_str r ) )
        }
        F e → ( nurl_println ( httpc_err_name e ) )
    }
}

@ main → i {
    ( show_ok `http` `http://example.com/index/a.json` )
    ( show_ok `https_upper` `HTTPS://example.com/` )
    ( show_ok `option` `-K/etc/passwd` )
    ( show_ok `option_after_scheme_check` `--next` )
    ( show_ok `file` `file:///etc/passwd` )
    ( show_ok `gopher` `gopher://127.0.0.1/` )
    ( show_ok `empty_rest` `http://` )
    ( show_ok `crlf` `http://a/\r\nX: 1` )
    ( show_ok `space` `http://a/ b` )
    ( show_ok `empty` `` )

    // Refused before any temp file or curl process exists.
    ( show_get `get_option` `-o/tmp/nurl-httpc-url-guard` )
    ( show_get `get_file` `file:///etc/passwd` )
    : ( Vec u ) none ( vec_new [u] )
    ?? ( httpc_request_bytes `POST` `ftp://127.0.0.1/` none `` ) {
        T _ → ( nurl_println `post_ftp=accepted(bug)` )
        F e → { ( nurl_print `post_ftp=` ) ( nurl_println ( httpc_err_name e ) ) }
    }

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18946 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                : s path ( string_data . req path )
                ? != 0 ( nurl_str_eq path `/redir` ) {
                    : HttpResponse rr ( response_text 302 `` )
                    ( response_set_header rr `Location` `ftp://127.0.0.1:9/x` )
                    ^ rr
                } {}
                // Echo the path: with globbing on, curl would have expanded
                // `[1-2]` into two requests and never sent the brackets.
                ^ ( response_text 200 path )
            }
            : HttpServer srv ( server_new listener h )
            : ( @ v ) client \ → v {
                ( sleep_ms 100 )
                ( show_get `glob` `http://127.0.0.1:18946/a[1-2]{b,c}` )
                ( show_get `redirect_ftp` `http://127.0.0.1:18946/redir` )
            }
            : !Thread ThreadErr ct ( thread_spawn client )
            : ~ i served 0
            ~ < served 2 {
                : !v NetErr sr ( server_run_once srv )
                ?? sr { T _ → {} F _ → {} }
                = served + served 1
            }
            ?? ct { T t → ( thread_join t ) F _ → {} }
            ( server_stop srv )
        }
        F _ → ( nurl_println `listen_fail` )
    }
    ( nurl_println `done` )
    ^ 0
}
