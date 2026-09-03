// stdlib/std/quic_client.nu — a QUIC client: one UDP socket, one
// connection (`std/quic_conn.nu`, client role), and the loop that
// feeds it — the client-side twin of `std/quic_server.nu`. Synchronous
// by design: every call drives the connection until what it waits for
// has happened or its deadline has passed; on a fiber the socket parks
// on the reactor, on a thread it blocks with a timeout. HTTP/3
// (`ext/http3_client.nu`) sits on top and talks to streams.
//
//   ( quic_client_connect host port server_name alpn tp verify timeout_ms )
//                                          → *QuicClient   0 when the name does not resolve or the socket
//                                                          cannot be bound; otherwise the handshake has been
//                                                          driven until it completed, failed, or `timeout_ms`
//                                                          passed — `quic_client_connected` says which, and
//                                                          the connection's close code says why not.
//                                                          `alpn` = "h3" (a preference list); verify = 1
//                                                          checks the certificate against the system roots
//                                                          + `server_name`
//   ( quic_client_connected cl )           → b             the handshake completed (streams may open)
//   ( quic_client_free cl )                → v             closes the socket; the connection with it
//   ( quic_client_conn cl )                → *QuicConn     BORROWED — streams, ALPN, PQ evidence, close code
//   ( quic_client_step cl wait_ms )        → v             one loop turn: receive (at most `wait_ms`), timers, send
//   ( quic_client_pump cl )                → v             send whatever the connection has ready
//   ( quic_client_wait_readable cl timeout_ms ) → b        drive until a stream has data / FIN / RESET, or the
//                                                          connection is gone (F) or the time is up (F)
//   ( quic_client_close cl app code reason timeout_ms ) → v  close and drive until the peer has seen it
//
// Retry, Version Negotiation, NEW_TOKEN and HANDSHAKE_DONE are the
// connection's business; the socket layer here has nothing to know.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`

: QuicClient {
    UdpSocket sock
    * QuicConn conn
    ( Vec u ) peer
    ( Vec u ) buf
    ( Vec u ) from
    i has_sock
}

@ __qcl_now → i { ^ / ( monotonic_ns ) 1000000 }

// The limits this client advertises: 30 s idle, 1 MiB connection
// window, 256 KiB per stream, 100 bidirectional streams the server may
// open (an HTTP/3 server opens none), 3 unidirectional (control + 2
// QPACK).
@ quic_client_default_tp → *QuicTp {
    : *QuicTp tp ( quic_tp_new )
    = . tp max_idle_timeout 30000
    = . tp max_udp_payload_size 1350
    = . tp initial_max_data 1048576
    = . tp initial_max_stream_data_bidi_local 262144
    = . tp initial_max_stream_data_bidi_remote 262144
    = . tp initial_max_stream_data_uni 262144
    = . tp initial_max_streams_bidi 100
    = . tp initial_max_streams_uni 3
    ^ tp
}

@ quic_client_connect s host i port s server_name s alpn * QuicTp tp i verify i timeout_ms → *QuicClient {
    : !( Vec u ) NetErr ar ( udp_addr_resolve host port )
    : ( Vec u ) peer ?? ar { T a → a F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] peer ) 0 { ( vec_free [u] peer ) ^ # *QuicClient 0 } {}
    // a socket of the peer's family: bind the wildcard of that family
    : !UdpSocket NetErr sr ( udp_bind ? == ( udp_addr_family peer ) 6 `::` `0.0.0.0` 0 )
    : ~ i ok 0
    : ~ UdpSocket sock @ UdpSocket { `` }
    ?? sr { T s → { = sock s = ok 1 } F _ → {} }
    ? == ok 0 { ( vec_free [u] peer ) ^ # *QuicClient 0 } {}
    : *QuicClient cl # *QuicClient ( nurl_alloc Z QuicClient )
    = . cl sock sock
    = . cl has_sock 1
    = . cl peer peer
    = . cl buf ( vec_with_cap [u] 65536 )
    = . cl from ( udp_addr_new )
    = . cl conn ( quic_conn_new_client peer server_name alpn tp verify ( __qcl_now ) )
    ( quic_client_pump cl )
    : i deadline + ( __qcl_now ) timeout_ms
    ~ & < ( quic_conn_state . cl conn ) 1 < ( __qcl_now ) deadline {
        ( quic_client_step cl - deadline ( __qcl_now ) )
    }
    ^ cl
}

@ quic_client_connected * QuicClient cl → b { ^ == ( quic_conn_state . cl conn ) 1 }

@ quic_client_free * QuicClient cl → v {
    ? == # i cl 0 { ^ } {}
    ( quic_conn_free . cl conn )
    ? != . cl has_sock 0 { ( udp_close . cl sock ) } {}
    ( vec_free [u] . cl peer )
    ( vec_free [u] . cl buf )
    ( vec_free [u] . cl from )
    ( nurl_free # s cl )
}

@ quic_client_conn * QuicClient cl → *QuicConn { ^ . cl conn }

// Send everything the connection has ready.
@ quic_client_pump * QuicClient cl → v {
    : ~ i guard 0
    ~ < guard 64 {
        : ( Vec u ) d ( quic_conn_send . cl conn ( __qcl_now ) )
        ? == ( vec_len [u] d ) 0 { ( vec_free [u] d ) = guard 64 } {
            : !i NetErr w ( udp_send_addr . cl sock d . cl peer )
            ?? w { T _ → {} F _ → {} }
            ( vec_free [u] d )
            = guard + guard 1
        }
    }
}

// One turn of the loop: wait for a datagram at most `wait_ms` (or until
// the connection's next deadline, whichever is first), feed it, drain
// what else is ready, run the timers, send.
@ quic_client_step * QuicClient cl i wait_ms → v {
    : *QuicConn c . cl conn
    : i now0 ( __qcl_now )
    : ~ i wait ? < wait_ms 0 0 wait_ms
    : i t ( quic_conn_next_timeout c )
    ? > t 0 {
        : i d - t now0
        ? < d wait { = wait ? < d 0 0 d } {}
    } {}
    : !i NetErr r ( udp_recv_into_deadline . cl sock . cl buf . cl from wait )
    ?? r {
        T n → { ( quic_conn_recv c . cl buf . cl from ( __qcl_now ) ) }
        F e → {}
    }
    : ~ i more 1
    ~ != more 0 {
        : !i NetErr r2 ( udp_recv_into_deadline . cl sock . cl buf . cl from 0 )
        ?? r2 {
            T n → { ( quic_conn_recv c . cl buf . cl from ( __qcl_now ) ) }
            F e → { = more 0 }
        }
    }
    : i now2 ( __qcl_now )
    : i t2 ( quic_conn_next_timeout c )
    ? & > t2 0 <= t2 now2 { ( quic_conn_on_timeout c now2 ) } {}
    ( quic_client_pump cl )
}

// Drive until a stream is readable (T), or the connection is closing /
// closed or the time is up (F). The ids are left in the connection for
// `quic_conn_take_readable`.
@ quic_client_wait_readable * QuicClient cl i timeout_ms → b {
    : *QuicConn c . cl conn
    : i deadline + ( __qcl_now ) timeout_ms
    ~ T {
        ? >= ( quic_conn_state c ) 2 { ^ F } {}
        : ( Vec i ) r ( quic_conn_take_readable c )
        : i n ( vec_len [i] r )
        ( _qc_requeue_readable c r )
        ( vec_free [i] r )
        ? > n 0 { ^ T } {}
        : i now ( __qcl_now )
        ? >= now deadline { ^ F } {}
        ( quic_client_step cl - deadline now )
    }
    ^ F
}

// Close (application error when `app` = 1) and keep the loop going
// until the connection has gone through closing, or `timeout_ms`.
@ quic_client_close * QuicClient cl i app i code ( Vec u ) reason i timeout_ms → v {
    : *QuicConn c . cl conn
    ( quic_conn_close c app code reason )
    ( quic_client_pump cl )
    : i deadline + ( __qcl_now ) timeout_ms
    ~ & < ( quic_conn_state c ) 4 < ( __qcl_now ) deadline {
        ( quic_client_step cl - deadline ( __qcl_now ) )
    }
}
