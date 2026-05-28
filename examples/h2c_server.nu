// examples/h2c_server.nu — minimal cleartext HTTP/2 ("h2c", prior-
// knowledge mode) server. Listens on 127.0.0.1:8443 and replies 200
// "ok" to every request.
//
// Intended target for the `h2spec` conformance suite:
//
//   ./nurl.sh examples/h2c_server.nu &
//   h2spec -h 127.0.0.1 -p 8443 -t=false
//
// Shutdown: Ctrl+C (SIGINT) — the listener closes and the accept
// loop exits.

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_server.nu`

@ h2c_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `ok\n` )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 8443 )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )
            ( nurl_print `h2c server listening on 127.0.0.1:8443 (prior-knowledge)\n` )
            : ~ b done F
            ~ ! done {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        : ( @ HttpResponse HttpRequest ) h
                            \ HttpRequest req → HttpResponse { ^ ( h2c_handler req ) }
                        : ! v H2ConnErr sr ( http2_serve conn h )
                        ?? sr { T _ → {} F _ → {} }
                        ( tcp_close_conn conn )
                    }
                    F e → {
                        : s nm ( net_err_name e )
                        ? | != 0 ( nurl_str_eq nm `NetClosed` )
                          != 0 ( nurl_str_eq nm `NetAccept` ) {
                            = done T
                        } {
                            ( nurl_print `accept err: ` )
                            ( nurl_print nm )
                            ( nurl_print `\n` )
                            = done T
                        }
                    }
                }
            }
            ( tcp_close_listener listener )
        }
        F e → {
            ( nurl_print `bind failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
    }
    ^ 0
}
