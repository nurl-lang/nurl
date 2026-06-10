// Minimal repro for the per-request HTTP server leaks found via ASan on
// the nurlapi server (critic.md A4b). One route that reads a header,
// served by server_run_pool; SIGINT stops it so LeakSanitizer reports.
$ `stdlib/ext/http_full.nu`

@ h_root HttpRequest req Params params → HttpResponse {
    : ?String h ( header_get . req headers `X-Probe` )
    ?? h {
        T s → { ( string_free s ) }
        F _ → {}
    }
    ^ ( response_text 200 `ok\n` )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 8077 )
    ?? lr {
        T listener → {
            : Router r ( router_new )
            ( router_get r `/` \ HttpRequest req Params params → HttpResponse { ^ ( h_root req params ) } )
            : ( @ HttpResponse HttpRequest ) base \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }
            ( signal_install_shutdown listener )
            : HttpServer srv ( server_new_with_timeout listener base 5000 )
            : !v NetErr rr ( server_run_pool srv 2 )
            ( signal_clear_shutdown ) ( server_stop srv ) ( router_free r )
            ( nurl_free # s # *u base 1 )
            ?? rr { T _ → { ^ 0 } F _ → { ^ 1 } }
        }
        F _ → { ^ 1 }
    }
}
