// stdlib/ext/http2_server.nu — drive one HTTP/2 connection.
//
//   ( http2_serve TcpConn conn ( @ HttpResponse HttpRequest ) handler )
//     → ! v H2ConnErr
//
//     Serve a connection that is known to be HTTP/2 — a prior-knowledge
//     h2c client, or a TLS client that negotiated "h2" — from its first
//     byte: reads the client preface, runs the frame loop until the peer
//     goes away, frees the connection state. The caller still owns the
//     TcpConn and closes it afterwards.
//
// The regular HTTP server (`stdlib/ext/http_server.nu`, and the
// packages/http HttpApp on top of it) does not need this entry point:
// every accept path there — server_run, server_run_pool, server_run_async
// — recognises the HTTP/2 connection preface on the first bytes of a
// connection and serves HTTP/2 itself, under the same DoS gate, idle
// timeout and body limits as HTTP/1.1. http2_serve is for a program that
// owns its own accept loop (examples/h2c_server.nu, the h2spec target) or
// wants an HTTP/2-only socket.
//
// The handler contract is identical for both protocols — same
// `( @ HttpResponse HttpRequest )` signature — so application code
// doesn't fork on the protocol. HTTP/2-specific details (pseudo-
// headers, multiplexing, flow control) live entirely inside
// `h2_conn_serve`.

$ `stdlib/core/string.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
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
