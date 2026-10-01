// stdlib/std/quic_server.nu — the QUIC listener: one UDP socket, one
// loop, a table of connections keyed by connection ID, and an event
// callback for the application protocol on top (HTTP/3 in
// `ext/http3_server.nu`).
//
//   ( quic_server_new sock creds alpn_prefs tp on_event ) → QuicServer
//   ( quic_server_free s )                                → v   early release (optional: the last owner
//                                                               of a QuicServer releases it)
//   ( quic_server_run s )                                 → v   the loop; returns when `quic_server_stop`
//   ( quic_server_stop s )                                → v   from another fiber / thread
//   ( quic_server_pump s conn now )                       → v   send whatever `conn` has ready (the
//                                                               application calls this after writing streams)
//
// `on_event conn event` is called with the connection (BORROWED: an
// application that keeps it keeps a `QuicConn_share`) and: 1 = new
// connection (handshake confirmed, ALPN known) · 2 = streams readable
// (`quic_conn_take_readable`) · 3 = connection gone (the listener lets
// go of it right after the callback returns).
//
// A QuicServer is a handle: every copy (the thread running the loop,
// the one that stops it) is the same listener, and the last owner
// releases the connections, the routing table and the event closure.
// The socket stays the caller's.
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
$ `stdlib/core/rcbox.nu`

// The routing table maps the first 8 bytes of every connection ID a
// connection answers to onto the connection (one owner per entry).
: QuicServerImpl {
    UdpSocket sock
    QuicCreds creds
    ( Vec u ) alpn_prefs
    QuicTp tp
    ( @ v QuicConn i ) on_event
    ( HashMap i QuicConn ) by_cid
    ( Vec QuicConn ) conns
    i running
    i accepted
    i rejected
}

// A QuicServer is a handle on its state in an rcbox (stdlib/core/rcbox.nu).
: QuicServer { s ctl }

@ QuicServer_share QuicServer h → QuicServer { ^ @ QuicServer { # s ( rcbox_share # i . h ctl ) } }

@ QuicServer_drop sink QuicServer h → v {
    ( mem_forget h )
    ( rcbox_release [QuicServerImpl] # i . h ctl )
}

@ __QuicServer_ptr QuicServer h → *QuicServerImpl { ^ ( rcbox_ptr [QuicServerImpl] # i . h ctl ) }

// `creds` and `tp` are shared with every connection; `on_event` is the
// server's own copy.
@ quic_server_new UdpSocket sock QuicCreds creds ( Vec u ) alpn_prefs QuicTp tp ( @ v QuicConn i ) on_event → QuicServer {
    : i s__box ( rcbox_zero [QuicServerImpl] )
    : *QuicServerImpl s ( rcbox_ptr [QuicServerImpl] s__box )
    = . s sock sock
    = . s creds ( QuicCreds_share creds )
    = . s alpn_prefs ( bytes_slice alpn_prefs 0 ( vec_len [u] alpn_prefs ) )
    = . s tp ( QuicTp_share tp )
    = . s on_event on_event
    = . s by_cid ( map_new [i QuicConn] )
    = . s conns ( vec_new [QuicConn] )
    = . s running 0
    = . s accepted 0
    = . s rejected 0
    ^ @ QuicServer { # s s__box }
}

// Let go of `s` now rather than at the end of its owner's scope.
@ quic_server_free sink QuicServer s → v {}

@ quic_server_stop QuicServer s__h → v {
    : *QuicServerImpl s ( __QuicServer_ptr s__h )
    = . s running 0
}

@ quic_server_accepted QuicServer s__h → i {
    : *QuicServerImpl s ( __QuicServer_ptr s__h )
    ^ . s accepted
}

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

// The connection `key` routes to, one more owner of it; null for none.
@ __qs_map_get ( HashMap i QuicConn ) m i key → QuicConn {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    ^ ?? ( map_get [i QuicConn] m key hf ef ) { T c → ( QuicConn_share c ) F → @ QuicConn { # s 0 } }
}

@ __qs_map_has ( HashMap i QuicConn ) m i key → b {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    ^ ( map_contains [i QuicConn] m key hf ef )
}

@ __qs_map_set ( HashMap i QuicConn ) m i key QuicConn c → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?QuicConn _old ( map_set [i QuicConn] m key ( QuicConn_share c ) hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __qs_map_del ( HashMap i QuicConn ) m i key → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?QuicConn _old ( map_remove [i QuicConn] m key hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __qs_now → i { ^ / ( monotonic_ns ) 1000000 }

// Register every id the connection answers to (issued ids may grow),
// and forget the ones the peer retired: a stale entry would keep a
// finished connection alive.
@ __qs_register * QuicServerImpl s QuicConn c → v {
    : ( Vec u ) cids ( quic_conn_cids c )
    : ~ i off 0
    ~ < + off 8 + ( vec_len [u] cids ) 1 {
        : i key ( __qs_key cids off )
        ? ! ( __qs_map_has . s by_cid key ) { ( __qs_map_set . s by_cid key c ) } {}
        = off + off 8
    }
    : ( Vec u ) gone ( quic_conn_retired_cids c )
    ? > ( vec_len [u] gone ) 0 {
        = off 0
        ~ < + off 8 + ( vec_len [u] gone ) 1 {
            ( __qs_map_del . s by_cid ( __qs_key gone off ) )
            = off + off 8
        }
        ( quic_conn_clear_retired_cids c )
    } {}
}

@ __qs_unregister * QuicServerImpl s QuicConn c → v {
    : ( Vec u ) cids ( quic_conn_cids c )
    : ~ i off 0
    ~ < + off 8 + ( vec_len [u] cids ) 1 {
        ( __qs_map_del . s by_cid ( __qs_key cids off ) )
        = off + off 8
    }
}

@ __qs_pump * QuicServerImpl s QuicConn c i now → v {
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

// Send everything `conn` has ready.
@ quic_server_pump QuicServer s__h QuicConn c i now → v {
    : *QuicServerImpl s ( __QuicServer_ptr s__h )
    ( __qs_pump s c now )
}

@ __qs_dispatch * QuicServerImpl s ( Vec u ) dgram ( Vec u ) from i now → v {
    : i n ( vec_len [u] dgram )
    ? < n 1 { ^ } {}
    : QuicHdr h ( quic_hdr_parse dgram 0 ( quic_conn_scid_len ) )
    ? < . h ptype 0 { ^ } {}
    : ( Vec u ) dcid ( quic_hdr_dcid h dgram )
    : ~ QuicConn c @ QuicConn { # s 0 }
    ? >= ( vec_len [u] dcid ) 8 { = c ( __qs_map_get . s by_cid ( __qs_key dcid 0 ) ) } {}
    ? == 0 # i . c ctl {
        ? & != . h ptype 4 != . h version 1 {
            // Version Negotiation (§6): the client's ids swapped, our versions
            ? != . h ptype 5 {
                : ( Vec u ) scid ( quic_hdr_scid h dgram )
                : ( Vec i ) vers ( vec_new [i] )
                ( vec_push [i] vers 1 )
                : ( Vec u ) vn ( quic_vn_build scid dcid vers )
                : !i NetErr w ( udp_send_addr . s sock vn from )
                ?? w { T _ → {} F _ → {} }
                ( vec_free [u] vn ) ( vec_free [u] scid )
            } {}
        } {
            // A new connection: a client Initial of at least 1200 bytes (§14.1)
            ? & & == . h ptype 0 >= n 1200 >= ( vec_len [u] dcid ) 8 {
                : ( Vec u ) scid ( __qs_new_scid s )
                = c ( quic_conn_new_server scid dcid from . s creds . s alpn_prefs . s tp now )
                ( vec_push [QuicConn] . s conns ( QuicConn_share c ) )
                ( __qs_map_set . s by_cid ( __qs_key dcid 0 ) c )
                ( __qs_register s c )
                ( vec_free [u] scid )
                = . s accepted + . s accepted 1
            } { = . s rejected + . s rejected 1 }
        }
    } {}
    ( vec_free [u] dcid )
    ? == 0 # i . c ctl { ^ } {}
    : i before ( quic_conn_state c )
    ( quic_conn_recv c dgram from now )
    ( __qs_after c s now before )
}

@ __qs_new_scid * QuicServerImpl s → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 8 )
    : b _ok ( vec_resize_zeroed [u] v 8 )
    ~ T {
        : i r ( nurl_rand_fill # *u ( vec_data [u] v ) 8 )
        ? == r 0 { ( nurl_panic `quic: CSPRNG (nurl_rand_fill) failed` ) } {}
        ? ! ( __qs_map_has . s by_cid ( __qs_key v 0 ) ) { ^ v } {}
    }
    ^ v
}

// After input or a timer: events to the application, then output.
@ __qs_after QuicConn c * QuicServerImpl s i now i before → v {
    : i st ( quic_conn_state c )
    : ( @ v QuicConn i ) ev . s on_event
    ? & == before 0 == st 1 { ( ev c 1 ) } {}
    ? < st 2 {
        : ( Vec i ) r ( quic_conn_take_readable c )
        ? > ( vec_len [i] r ) 0 {
            // hand the ids back so the application sees them in its own call
            ( _qc_requeue_readable c r )
            ( ev c 2 )
        } {}
        ( vec_free [i] r )
    } {}
    ( __qs_pump s c now )
}

// Closed connections leave the table (from the end, so the indexes still
// to visit stay put); a turn without one rebuilds nothing.
@ __qs_reap * QuicServerImpl s → v {
    : ~ i k - ( vec_len [QuicConn] . s conns ) 1
    ~ >= k 0 {
        : ~ b gone F
        ?? ( vec_get [QuicConn] . s conns k ) {
            T c → {
                ? >= ( quic_conn_state c ) 4 {
                    : ( @ v QuicConn i ) ev . s on_event
                    ( ev c 3 )
                    ( __qs_unregister s c )
                    : ( Vec u ) od ( quic_conn_odcid c )
                    ? >= ( vec_len [u] od ) 8 { ( __qs_map_del . s by_cid ( __qs_key od 0 ) ) } {}
                    = gone T
                } {}
            }
            F → {}
        }
        ? gone { : ?QuicConn _r ( vec_remove [QuicConn] . s conns k ) } {}
        = k - k 1
    }
}

@ quic_server_run QuicServer s__h → v {
    : *QuicServerImpl s ( __QuicServer_ptr s__h )
    = . s running 1
    : ( Vec u ) buf ( vec_with_cap [u] 65536 )
    : ( Vec u ) from ( udp_addr_new )
    ~ != . s running 0 {
        // the earliest deadline over all connections
        : i now0 ( __qs_now )
        : ~ i wait 1000
        : ~ i k 0
        ~ < k ( vec_len [QuicConn] . s conns ) {
            ?? ( vec_get [QuicConn] . s conns k ) {
                T c → {
                    : i t ( quic_conn_next_timeout c )
                    ? > t 0 {
                        : i d - t now0
                        ? < d wait { = wait ? < d 0 0 d } {}
                    } {}
                }
                F → {}
            }
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
        ~ < k ( vec_len [QuicConn] . s conns ) {
            ?? ( vec_get [QuicConn] . s conns k ) {
                T c → {
                    : i t ( quic_conn_next_timeout c )
                    ? & > t 0 <= t now2 {
                        : i before ( quic_conn_state c )
                        ( quic_conn_on_timeout c now2 )
                        ( __qs_after c s now2 before )
                    } {}
                }
                F → {}
            }
            = k + k 1
        }
        ( __qs_reap s )
    }
    ( vec_free [u] from )
}
