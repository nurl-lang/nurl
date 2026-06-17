// bench/http_server.nu — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3).
//
// Listens on 127.0.0.1:18080. Serves "Hello, World!\n" (14 bytes,
// text/plain) on `/`. No router middleware, no metrics, no access log
// — apples-to-apples with the Go/Rust/Node sibling files in this
// directory. Ctrl+C (or SIGTERM) shuts down cleanly.
//
// Run: ./bench/http_server.sh  (compiles + starts; see that script
//                               for the bench driver glue).

$ `stdlib/ext/http_full.nu`

@ hello HttpRequest req Params params → HttpResponse {
    ^ ( response_text 200 `Hello, World!\n` )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18080 )
    ?? lr {
        T listener → {
            : Router r ( router_new )
            ( router_get r `/` \ HttpRequest req Params params → HttpResponse { ^ ( hello req params ) } )
            : ( @ HttpResponse HttpRequest ) base
            \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }

            ( signal_install_shutdown listener )

            ( nurl_print `nurl http_server listening on http://127.0.0.1:18080/\n` )
            ( nurl_flush_stdout )

            : HttpServer srv ( server_new listener base )
            // Drive a thread pool so the bench measures the full server
            // surface rather than a single accept loop. 10 workers is a
            // reasonable default for ~12-core hosts (tokio's default
            // multi-thread runtime in the Rust peer uses every core).
            : !v NetErr rr ( server_run_pool srv 10 )

            ( signal_clear_shutdown )
            ( server_stop srv )
            ( router_free r )

            ?? rr {
                T _ → ^ 0
                F e → {
                    ( nurl_eprint `nurl http_server: ` )
                    ( nurl_eprint ( net_err_name e ) )
                    ( nurl_eprint `\n` )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `nurl http_server: bind failed: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
