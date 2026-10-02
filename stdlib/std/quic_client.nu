// stdlib/std/quic_client.nu — a QUIC client: one UDP socket, one
// connection (`std/quic_conn.nu`, client role), and the loop that
// feeds it — the client-side twin of `std/quic_server.nu`. Synchronous
// by design: every call drives the connection until what it waits for
// has happened or its deadline has passed; on a fiber the socket parks
// on the reactor, on a thread it blocks with a timeout. HTTP/3
// (`ext/http3_client.nu`) sits on top and talks to streams.
//
//   ( quic_client_connect host port server_name alpn tp verify timeout_ms )
//                                          → QuicClient    null (`== 0 # i . cl ctl`) when the name does not resolve or the socket
//                                                          cannot be bound; otherwise the handshake has been
//                                                          driven until it completed, failed, or `timeout_ms`
//                                                          passed — `quic_client_connected` says which, and
//                                                          the connection's close code says why not.
//                                                          `alpn` = "h3" (a preference list); verify = 1
//                                                          checks the certificate against the system roots
//                                                          + `server_name`
//   ( quic_client_connected cl )           → b             the handshake completed (streams may open)
//   ( quic_client_free cl )                → v             early release (optional): the last owner of a
//                                                          QuicClient closes the socket and lets go of
//                                                          the connection
//   ( quic_client_conn cl )                → QuicConn      BORROWED — streams, ALPN, PQ evidence, close code
//   ( __qcl_step cl wait_ms )        → v             one loop turn: receive (at most `wait_ms`), timers, send
//   ( __qcl_pump cl )                → v             send whatever the connection has ready
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
$ `stdlib/core/rcbox.nu`

: QuicClientImpl {
    UdpSocket sock
    QuicConn conn
    ( Vec u ) peer
    ( Vec u ) buf
    ( Vec u ) from
    i has_sock
}

// A QuicClient is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same client, and the last owner releases it.
: QuicClient { s ctl }

// The socket is the client's own: its drop closes it (the connection,
// buffers and peer address go with the fields).
% Drop QuicClientImpl {
    @ drop QuicClientImpl cl → v {
        ? != . cl has_sock 0 { ( udp_close . cl sock ) } {}
    }
}

@ QuicClient_share QuicClient h → QuicClient { ^ @ QuicClient { # s ( rcbox_share # i . h ctl ) } }

@ QuicClient_drop sink QuicClient h → v {
    ( mem_forget h )
    ( rcbox_release [QuicClientImpl] # i . h ctl )
}

@ __QuicClient_ptr QuicClient h → *QuicClientImpl { ^ ( rcbox_ptr [QuicClientImpl] # i . h ctl ) }

@ __qcl_now → i { ^ / ( monotonic_ns ) 1000000 }

// The limits this client advertises: 30 s idle, 1 MiB connection
// window, 256 KiB per stream, 100 bidirectional streams the server may
// open (an HTTP/3 server opens none), 3 unidirectional (control + 2
// QPACK).
@ quic_client_default_tp → QuicTp {
    : QuicTp tp ( quic_tp_new )
    ( quic_tp_set_max_idle_timeout tp 30000 )
    ( quic_tp_set_max_udp_payload_size tp 1350 )
    ( quic_tp_set_initial_max_data tp 1048576 )
    ( quic_tp_set_initial_max_stream_data_bidi_local tp 262144 )
    ( quic_tp_set_initial_max_stream_data_bidi_remote tp 262144 )
    ( quic_tp_set_initial_max_stream_data_uni tp 262144 )
    ( quic_tp_set_initial_max_streams_bidi tp 100 )
    ( quic_tp_set_initial_max_streams_uni tp 3 )
    ^ tp
}

@ quic_client_connect s host i port s server_name s alpn QuicTp tp i verify i timeout_ms → QuicClient {
    : !( Vec u ) NetErr ar ( udp_addr_resolve host port )
    : ( Vec u ) peer ?? ar { T a → a F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] peer ) 0 { ^ @ QuicClient { # s 0 } } {}
    // a socket of the peer's family: bind the wildcard of that family
    : !UdpSocket NetErr sr ( udp_bind ? == ( udp_addr_family peer ) 6 `::` `0.0.0.0` 0 )
    : ~ i ok 0
    : ~ UdpSocket sock @ UdpSocket { `` }
    ?? sr { T s → { = sock s = ok 1 } F _ → {} }
    ? == ok 0 { ^ @ QuicClient { # s 0 } } {}
    : i cl__box ( rcbox_zero [QuicClientImpl] )
    : ~ * QuicClientImpl cl ( rcbox_ptr [QuicClientImpl] cl__box )
    = . cl sock sock
    = . cl has_sock 1
    = . cl peer peer
    = . cl buf ( vec_with_cap [u] 65536 )
    = . cl from ( udp_addr_new )
    = . cl conn ( quic_conn_new_client peer server_name alpn tp verify ( __qcl_now ) )
    ( __qcl_pump . cl 0 )
    : i deadline + ( __qcl_now ) timeout_ms
    ~ & < ( quic_conn_state . cl conn ) 1 < ( __qcl_now ) deadline {
        ( __qcl_step . cl 0 - deadline ( __qcl_now ) )
    }
    ^ @ QuicClient { # s cl__box }
}

@ quic_client_connected QuicClient cl__h → b {
    : *QuicClientImpl cl ( __QuicClient_ptr cl__h )
    ^ == ( quic_conn_state . cl conn ) 1
}

// Let go of `cl` now rather than at the end of its owner's scope.
@ quic_client_free sink QuicClient cl → v {}

@ quic_client_conn QuicClient cl__h → QuicConn {
    : *QuicClientImpl cl ( __QuicClient_ptr cl__h )
    ^ . cl conn
}

@ __qcl_pump inout QuicClientImpl cl → v {
    : ~ i guard 0
    ~ < guard 64 {
        : ( Vec u ) d ( quic_conn_send . cl conn ( __qcl_now ) )
        ? == ( vec_len [u] d ) 0 { = guard 64 } {
            : !i NetErr w ( udp_send_addr . cl sock d . cl peer )
            ?? w { T _ → {} F _ → {} }
            = guard + guard 1
        }
    }
}

// Send everything the connection has ready.
@ quic_client_pump QuicClient cl__h → v {
    : ~ * QuicClientImpl cl ( __QuicClient_ptr cl__h )
    ( __qcl_pump . cl 0 )
}

// One turn of the loop: wait for a datagram at most `wait_ms` (or until
// the connection's next deadline, whichever is first), feed it, drain
// what else is ready, run the timers, send.
@ __qcl_step inout QuicClientImpl cl i wait_ms → v {
    : QuicConn c . cl conn
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
    ( __qcl_pump cl )
}

@ quic_client_step QuicClient cl__h i wait_ms → v {
    : ~ * QuicClientImpl cl ( __QuicClient_ptr cl__h )
    ( __qcl_step . cl 0 wait_ms )
}

// Drive until a stream is readable (T), or the connection is closing /
// closed or the time is up (F). The ids are left in the connection for
// `quic_conn_take_readable`.
@ quic_client_wait_readable QuicClient cl__h i timeout_ms → b {
    : ~ * QuicClientImpl cl ( __QuicClient_ptr cl__h )
    : QuicConn c . cl conn
    : i deadline + ( __qcl_now ) timeout_ms
    ~ T {
        ? >= ( quic_conn_state c ) 2 { ^ F } {}
        : ( Vec i ) r ( quic_conn_take_readable c )
        : i n ( vec_len [i] r )
        ( _qc_requeue_readable c r )
        ? > n 0 { ^ T } {}
        : i now ( __qcl_now )
        ? >= now deadline { ^ F } {}
        ( __qcl_step . cl 0 - deadline now )
    }
    ^ F
}

// Close (application error when `app` = 1) and keep the loop going
// until the connection has gone through closing, or `timeout_ms`.
@ quic_client_close QuicClient cl__h i app i code ( Vec u ) reason i timeout_ms → v {
    : ~ * QuicClientImpl cl ( __QuicClient_ptr cl__h )
    : QuicConn c . cl conn
    ( quic_conn_close c app code reason )
    ( __qcl_pump . cl 0 )
    : i deadline + ( __qcl_now ) timeout_ms
    ~ & < ( quic_conn_state c ) 4 < ( __qcl_now ) deadline {
        ( __qcl_step . cl 0 - deadline ( __qcl_now ) )
    }
}
