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
$ `stdlib/std/async.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_server.nu`

@ h2c_handler HttpRequest req → HttpResponse {
    // Body deliberately ≥ 5 bytes — some h2spec flow-control tests
    // (§6.9.2/2 "Sends a SETTINGS frame for window size to be
    // negative") gate on `dataLen >= 5` and skip otherwise.
    ^ ( response_text 200 `hello\n` )
}

// Per-connection handler — runs as a fiber so multiple peers (e.g.
// h2spec's probe + test connections that arrive back-to-back) can be
// served concurrently without the accept loop having to block on any
// single conn's read timeout.
@ serve_one TcpConn conn → v {
    ( tcp_set_timeout conn 1000 )
    : ( @ HttpResponse HttpRequest ) h
    \ HttpRequest req → HttpResponse { ^ ( h2c_handler req ) }
    : !v H2ConnErr sr ( http2_serve conn h )
    ?? sr { T _ → {} F _ → {} }
    ( tcp_close_conn conn )
}

@ accept_loop TcpListener listener → v {
    : ~ b done F
    ~ ! done {
        : !TcpConn NetErr ar ( tcp_accept listener )
        ?? ar {
            T conn → {
                // Hand the connection to a fresh fiber so the accept
                // loop can immediately go back to accepting the next
                // one. h2spec issues probe + test connections in
                // quick succession and the probe MUST complete for
                // the test to proceed.
                ( spawn \ → v { ( serve_one conn ) } )
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
}

@ main → i {
    ( runtime_init 0 )
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 8443 )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )
            ( nurl_print `h2c server listening on 127.0.0.1:8443 (prior-knowledge, async)\n` )
            ( spawn \ → v { ( accept_loop listener ) } )
            ( runtime_run )
            ( runtime_shutdown )
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
