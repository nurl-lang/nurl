// stdlib/std/quic_server.nu — the QUIC listener: one UDP socket, one
// loop, a table of connections keyed by connection ID, and an event
// callback for the application protocol on top (HTTP/3 in
// `ext/http3_server.nu`).
//
//   ( quic_server_new sock creds alpn_prefs tp on_event ) → *QuicServer
//   ( quic_server_free s )                                → v
//   ( quic_server_run s )                                 → v   the loop; returns when `quic_server_stop`
//   ( quic_server_stop s )                                → v   from another fiber / thread
//   ( quic_server_pump s conn now )                       → v   send whatever `conn` has ready (the
//                                                               application calls this after writing streams)
//
// `on_event conn event` is called with the connection pointer (as i)
// and: 1 = new connection (handshake confirmed, ALPN known) ·
// 2 = streams readable (`quic_conn_take_readable`) · 3 = connection
// gone (the pointer is freed right after the callback returns).
//
// The loop is one fiber (or thread) per socket: park on the socket
// with the earliest connection deadline as the timeout, drain every
// datagram that is ready, run timers, send what became ready, reap
// closed connections. Datagrams that name no connection open one when
// they are a well-formed, 1200-byte Initial for version 1; an unknown
// version gets a Version Negotiation packet; everything else is
// dropped.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/quic_packet.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`

: QuicServer {
    UdpSocket sock
    * QuicCreds creds
    ( Vec u ) alpn_prefs
    * QuicTp tp
    ( @ v i i ) on_event
    ( HashMap i i ) by_cid
    ( Vec i ) conns
    i running
    i accepted
    i rejected
}

@ quic_server_new UdpSocket sock * QuicCreds creds ( Vec u ) alpn_prefs * QuicTp tp ( @ v i i ) on_event → *QuicServer {
    : *QuicServer s # *QuicServer ( nurl_alloc Z QuicServer )
    = . s sock sock
    = . s creds creds
    = . s alpn_prefs ( bytes_slice alpn_prefs 0 ( vec_len [u] alpn_prefs ) )
    = . s tp tp
    = . s on_event on_event
    = . s by_cid ( map_new [i i] )
    = . s conns ( vec_new [i] )
    = . s running 0
    = . s accepted 0
    = . s rejected 0
    ^ s
}

@ quic_server_free * QuicServer s → v {
    ? == # i s 0 { ^ } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . s conns ) {
        ( quic_conn_free # *QuicConn ?? ( vec_get [i] . s conns k ) { T x → x F → 0 } )
        = k + k 1
    }
    ( vec_free [i] . s conns )
    ( map_free [i i] . s by_cid )
    ( vec_free [u] . s alpn_prefs )
    ( nurl_free # s s )
}

@ quic_server_stop * QuicServer s → v { = . s running 0 }

@ quic_server_accepted * QuicServer s → i { ^ . s accepted }

// The first 8 bytes of a connection id as the map key.
@ __qs_key ( Vec u ) cid i off → i {
    : ~ i k 0
    : ~ i v 0
    ~ < k 8 {
        : i b ?? ( vec_get [u] cid + off k ) { T x → # i x F → 0 }
        = v | << v 8 b
        = k + k 1
    }
    ^ v
}

@ __qs_map_get ( HashMap i i ) m i key → i {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    ^ ?? ( map_get [i i] m key hf ef ) { T v → v F → 0 }
}

@ __qs_map_set ( HashMap i i ) m i key i val → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?i _old ( map_set [i i] m key val hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __qs_map_del ( HashMap i i ) m i key → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?i _old ( map_remove [i i] m key hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __qs_now → i { ^ / ( monotonic_ns ) 1000000 }

// Register every id the connection answers to (issued ids may grow).
@ __qs_register * QuicServer s * QuicConn c → v {
    : ( Vec u ) cids ( quic_conn_cids c )
    : ~ i off 0
    ~ < + off 8 + ( vec_len [u] cids ) 1 {
        ( __qs_map_set . s by_cid ( __qs_key cids off ) # i c )
        = off + off 8
    }
}

@ __qs_unregister * QuicServer s * QuicConn c → v {
    : ( Vec u ) cids ( quic_conn_cids c )
    : ~ i off 0
    ~ < + off 8 + ( vec_len [u] cids ) 1 {
        ( __qs_map_del . s by_cid ( __qs_key cids off ) )
        = off + off 8
    }
}

// Send everything `conn` has ready.
@ quic_server_pump * QuicServer s * QuicConn c i now → v {
    : ~ i guard 0
    ~ < guard 64 {
        : ( Vec u ) d ( quic_conn_send c now )
        ? == ( vec_len [u] d ) 0 { ( vec_free [u] d ) = guard 64 } {
            : !i NetErr w ( udp_send_addr . s sock d ( quic_conn_peer c ) )
            ?? w { T _ → {} F _ → {} }
            ( vec_free [u] d )
            = guard + guard 1
        }
    }
    // issued connection ids may have grown
    ( __qs_register s c )
}

@ __qs_dispatch * QuicServer s ( Vec u ) dgram ( Vec u ) from i now → v {
    : i n ( vec_len [u] dgram )
    ? < n 1 { ^ } {}
    : *QuicHdr h ( quic_hdr_parse dgram 0 ( quic_conn_scid_len ) )
    ? == # i h 0 { ^ } {}
    : ( Vec u ) dcid ( quic_hdr_dcid h dgram )
    : ~ * QuicConn c # *QuicConn 0
    ? >= ( vec_len [u] dcid ) 8 { = c # *QuicConn ( __qs_map_get . s by_cid ( __qs_key dcid 0 ) ) } {}
    ? == # i c 0 {
        ? & != . h ptype 4 != . h version 1 {
            // Version Negotiation (§6): the client's ids swapped, our versions
            ? != . h ptype 5 {
                : ( Vec u ) scid ( quic_hdr_scid h dgram )
                : ( Vec i ) vers ( vec_new [i] )
                ( vec_push [i] vers 1 )
                : ( Vec u ) vn ( quic_vn_build scid dcid vers )
                : !i NetErr w ( udp_send_addr . s sock vn from )
                ?? w { T _ → {} F _ → {} }
                ( vec_free [u] vn ) ( vec_free [i] vers ) ( vec_free [u] scid )
            } {}
        } {
            // A new connection: a client Initial of at least 1200 bytes (§14.1)
            ? & & == . h ptype 0 >= n 1200 >= ( vec_len [u] dcid ) 8 {
                : ( Vec u ) scid ( __qs_new_scid s )
                = c ( quic_conn_new_server scid dcid from . s creds . s alpn_prefs . s tp now )
                ( vec_push [i] . s conns # i c )
                ( __qs_map_set . s by_cid ( __qs_key dcid 0 ) # i c )
                ( __qs_register s c )
                ( vec_free [u] scid )
                = . s accepted + . s accepted 1
            } { = . s rejected + . s rejected 1 }
        }
    } {}
    ( vec_free [u] dcid )
    ( quic_hdr_free h )
    ? == # i c 0 { ^ } {}
    : i before ( quic_conn_state c )
    ( quic_conn_recv c dgram from now )
    ( __qs_after c s now before )
}

@ __qs_new_scid * QuicServer s → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 8 )
    : b _ok ( vec_resize_zeroed [u] v 8 )
    ~ T {
        : i r ( nurl_rand_fill # *u ( vec_data [u] v ) 8 )
        ? == r 0 { ( nurl_panic `quic: CSPRNG (nurl_rand_fill) failed` ) } {}
        ? == ( __qs_map_get . s by_cid ( __qs_key v 0 ) ) 0 { ^ v } {}
    }
    ^ v
}

// After input or a timer: events to the application, then output.
@ __qs_after * QuicConn c * QuicServer s i now i before → v {
    : i st ( quic_conn_state c )
    : ( @ v i i ) ev . s on_event
    ? & == before 0 == st 1 { ( ev # i c 1 ) } {}
    ? < st 2 {
        : ( Vec i ) r ( quic_conn_take_readable c )
        ? > ( vec_len [i] r ) 0 {
            // hand the ids back so the application sees them in its own call
            ( __qs_requeue c r )
            ( ev # i c 2 )
        } {}
        ( vec_free [i] r )
    } {}
    ( quic_server_pump s c now )
}

// The event handler reads `quic_conn_take_readable` itself; put the
// ids we peeked back in front.
@ __qs_requeue * QuicConn c ( Vec i ) r → v {
    ( _qc_requeue_readable c r )
}

@ __qs_reap * QuicServer s → v {
    : ( Vec i ) keep ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [i] . s conns ) {
        : *QuicConn c # *QuicConn ?? ( vec_get [i] . s conns k ) { T x → x F → 0 }
        ? >= ( quic_conn_state c ) 4 {
            : ( @ v i i ) ev . s on_event
            ( ev # i c 3 )
            ( __qs_unregister s c )
            : ( Vec u ) od ( quic_conn_odcid c )
            ? >= ( vec_len [u] od ) 8 { ( __qs_map_del . s by_cid ( __qs_key od 0 ) ) } {}
            ( quic_conn_free c )
        } { ( vec_push [i] keep # i c ) }
        = k + k 1
    }
    ( vec_free [i] . s conns )
    = . s conns keep
}

@ quic_server_run * QuicServer s → v {
    = . s running 1
    : ( Vec u ) buf ( vec_with_cap [u] 65536 )
    : ( Vec u ) from ( udp_addr_new )
    ~ != . s running 0 {
        // the earliest deadline over all connections
        : i now0 ( __qs_now )
        : ~ i wait 1000
        : ~ i k 0
        ~ < k ( vec_len [i] . s conns ) {
            : *QuicConn c # *QuicConn ?? ( vec_get [i] . s conns k ) { T x → x F → 0 }
            : i t ( quic_conn_next_timeout c )
            ? > t 0 {
                : i d - t now0
                ? < d wait { = wait ? < d 0 0 d } {}
            } {}
            = k + k 1
        }
        : !i NetErr r ( udp_recv_into_deadline . s sock buf from wait )
        : i now ( __qs_now )
        ?? r {
            T n → { ( __qs_dispatch s buf from now ) }
            F e → {}
        }
        // drain what else is ready without blocking
        : ~ i more 1
        ~ != more 0 {
            : !i NetErr r2 ( udp_recv_into_deadline . s sock buf from 0 )
            ?? r2 {
                T n → { ( __qs_dispatch s buf from ( __qs_now ) ) }
                F e → { = more 0 }
            }
        }
        // timers
        : i now2 ( __qs_now )
        = k 0
        ~ < k ( vec_len [i] . s conns ) {
            : *QuicConn c # *QuicConn ?? ( vec_get [i] . s conns k ) { T x → x F → 0 }
            : i t ( quic_conn_next_timeout c )
            ? & > t 0 <= t now2 {
                : i before ( quic_conn_state c )
                ( quic_conn_on_timeout c now2 )
                ( __qs_after c s now2 before )
            } {}
            = k + k 1
        }
        ( __qs_reap s )
    }
    ( vec_free [u] from )
    ( vec_free [u] buf )
}
