// stdlib/ext/http2_server.nu — HTTP/2 + HTTP/1.1 ALPN-dispatching server.
//
// Glues the HTTP/2 connection machinery (`http2_conn.nu`) to the
// existing HTTP/1.1 server surface via post-handshake ALPN inspection.
// User-facing entry-points:
//
//   ( http2_serve TcpConn conn ( @ HttpResponse HttpRequest ) handler )
//     → ! v H2ConnErr
//
//     Plain h2 dispatch on a TcpConn that's already been determined to
//     be HTTP/2 (either via ALPN selecting "h2" or via direct h2c).
//     Reads the client preface, runs the serve loop, frees state.
//
//   ( server_run_h2_capable HttpServer s ) → ! v NetErr
//
//     Same shape as `server_run` but per-conn checks the ALPN selection.
//     "h2" → http2_serve. Anything else → existing HTTP/1.1 keep-alive
//     loop. Use this for a TLS listener configured with
//     `tcp_listen_tls_with_alpn` advertising both protocols.
//
// The handler contract is identical for both protocols — same
// `( @ HttpResponse HttpRequest )` signature — so application code
// doesn't fork on the protocol. HTTP/2-specific details (pseudo-
// headers, multiplexing, flow control) live entirely inside
// `h2_conn_serve`.

$ `stdlib/core/string.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http2_conn.nu`

// Drive a single HTTP/2 session. Returns Ok on clean shutdown, Err on
// protocol or I/O failure. Caller still owns the TcpConn — close it
// after this returns.
@ http2_serve TcpConn conn ( @ HttpResponse HttpRequest ) handler → !v H2ConnErr {
    : !H2Connection H2ConnErr cr ( h2_conn_new conn )
    ?? cr {
        T h2c → {
            : !v H2ConnErr sr ( h2_conn_serve h2c handler )
            ( h2_conn_free h2c )
            ^ sr
        }
        F e → { ^ @ !v H2ConnErr { F e } }
    }
}

// Accept one connection, check ALPN, dispatch h2 OR h1 keep-alive.
// Mirrors `server_run_once`'s shape so it slots into the same loop.
@ server_run_once_h2_capable HttpServer s → !v NetErr {
    : !TcpConn NetErr ar ( tcp_accept . s listener )
    ?? ar {
        T conn → {
            : i ito . s idle_timeout_ms
            ? > ito 0 { ( tcp_set_timeout conn ito ) } {}
            : String proto ( tcp_alpn_protocol conn )
            : b is_h2 != 0 ( nurl_str_eq ( string_data proto ) `h2` )
            ( string_free proto )
            ? is_h2 {
                : !v H2ConnErr hr ( http2_serve conn . s handler )
                // Map H2ConnErr → NetErr for the listener-loop's sake.
                // h2 errors at the per-connection level shouldn't bring
                // the whole listener down; log and move on.
                ?? hr {
                    T _ → {}
                    F _ → {}  // already GOAWAY'd from inside h2_conn_serve
                }
            } {
                ( __serve_keepalive_loop s conn )
            }
            ( tcp_close_conn conn )
            ^ @ !v NetErr { T 0 }
        }
        F e → { ^ @ !v NetErr { F e } }
    }
}

// Accept loop using the ALPN-dispatching per-conn handler. Same exit
// semantics as `server_run` (NetClosed / NetAccept → clean shutdown,
// anything else → propagate).
@ server_run_h2_capable HttpServer s → !v NetErr {
    : ~ b done F
    : ~ b had_err F
    : ~ NetErr last_err NetClosed
    ~ ! done {
        : !v NetErr r ( server_run_once_h2_capable s )
        ?? r {
            T _ → {}
            F e → {
                : s nm ( net_err_name e )
                ? | != 0 ( nurl_str_eq nm `NetClosed` )
                != 0 ( nurl_str_eq nm `NetAccept` ) {
                    = done T
                } {
                    = last_err e
                    = had_err T
                    = done T
                }
            }
        }
    }
    ? had_err { ^ @ !v NetErr { F last_err } } {}
    ^ @ !v NetErr { T 0 }
}
