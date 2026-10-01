// stdlib/ext/http3_server.nu — HTTP/3 on a UDP socket: the QUIC
// listener (`std/quic_server.nu`) with an HTTP/3 connection per QUIC
// connection, all requests handed to the same `( @ HttpResponse
// HttpRequest )` handler the HTTP/1.1 and HTTP/2 paths use.
//
//   ( http3_server_new sock creds alpn_prefs tp handler body_max ) → H3Server
//   ( http3_server_run s )                                         → v   the loop (a fiber or a thread)
//   ( http3_server_stop s )                                        → v
//   ( http3_server_accepted s )                                    → i   QUIC connections accepted so far
//   ( http3_server_free s )                                        → v   early release (optional: the last
//                                                                        owner of an H3Server releases it)
//   ( http3_creds_load cert_path key_path )                        → QuicCreds    null (`== 0 # i . k ctl`) on error
//                                                                                 (EC P-256, RSA or ML-DSA PEM)
//   ( http3_default_tp )                                           → QuicTp       the limits this server advertises
//
// `stdlib/ext/http_server.nu` / `packages/http` call these to put HTTP/3
// next to a TLS listener; a program that wants HTTP/3 alone calls them
// directly (see examples/h3_server.nu).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`
$ `stdlib/std/quic_server.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http3_conn.nu`
$ `stdlib/core/rcbox.nu`

// The HTTP/3 connection over each QUIC connection, keyed by the QUIC
// connection's identity (its rcbox address) while the listener has it.
: H3ServerImpl {
    QuicServer qs
    ( HashMap i H3Conn ) h3s
    ( @ HttpResponse HttpRequest ) handler
    i body_max
}

// An H3Server is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy (the thread running it, the one that stops it) is the same
// server, and the last owner releases the listener and its connections.
: H3Server { s ctl }

@ H3Server_share H3Server h → H3Server { ^ @ H3Server { # s ( rcbox_share # i . h ctl ) } }

@ H3Server_drop sink H3Server h → v {
    ( mem_forget h )
    ( rcbox_release [H3ServerImpl] # i . h ctl )
}

@ __H3Server_ptr H3Server h → *H3ServerImpl { ^ ( rcbox_ptr [H3ServerImpl] # i . h ctl ) }

@ __h3s_map_set ( HashMap i H3Conn ) m i key H3Conn h → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?H3Conn _old ( map_set [i H3Conn] m key ( H3Conn_share h ) hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __h3s_map_del ( HashMap i H3Conn ) m i key → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?H3Conn _old ( map_remove [i H3Conn] m key hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __h3s_event * H3ServerImpl s QuicConn qc i ev → v {
    : i key # i . qc ctl
    ? == ev 1 {
        : H3Conn h ( h3_conn_new qc . s body_max )
        ( __h3s_map_set . s h3s key h )
        ^
    } {}
    ? == ev 2 {
        : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
        : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
        ?? ( map_get [i H3Conn] . s h3s key hf ef ) { T h → { ( h3_conn_on_readable h . s handler ) } F → {} }
        ^
    } {}
    ? == ev 3 { ( __h3s_map_del . s h3s key ) } {}
}

@ http3_server_new UdpSocket sock QuicCreds creds ( Vec u ) alpn_prefs QuicTp tp ( @ HttpResponse HttpRequest ) handler i body_max → H3Server {
    : i s__box ( rcbox_zero [H3ServerImpl] )
    : *H3ServerImpl s ( rcbox_ptr [H3ServerImpl] s__box )
    = . s h3s ( map_new [i H3Conn] )
    = . s handler handler
    = . s body_max body_max
    // The listener's event closure points back at this server without
    // owning it: the server owns the listener, which owns the closure.
    : ( @ v QuicConn i ) ev \ QuicConn qc i e → v { ( __h3s_event s qc e ) }
    = . s qs ( quic_server_new sock creds alpn_prefs tp ev )
    ^ @ H3Server { # s s__box }
}

@ http3_server_run H3Server s__h → v {
    : *H3ServerImpl s ( __H3Server_ptr s__h )
    ( quic_server_run . s qs )
}

@ http3_server_stop H3Server s__h → v {
    : *H3ServerImpl s ( __H3Server_ptr s__h )
    ( quic_server_stop . s qs )
}

@ http3_server_accepted H3Server s__h → i {
    : *H3ServerImpl s ( __H3Server_ptr s__h )
    ^ ( quic_server_accepted . s qs )
}

// Let go of `s` now rather than at the end of its owner's scope.
@ http3_server_free sink H3Server s → v {}

// The same certificate / key files the TLS listener takes, through the
// same loader (`std/net.nu` `_load_tls_creds`: fullchain PEM; EC P-256,
// RSA or ML-DSA key auto-detected).
@ http3_creds_load s cert_path s key_path → QuicCreds {
    : ( Vec u ) chain ( vec_new [u] )
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : i kt ( _load_tls_creds cert_path key_path chain k1 k2 k3 )
    : ~ QuicCreds out @ QuicCreds { # s 0 }
    : ( Vec u ) e ( vec_new [u] )
    // keytype 0: EC scalar in k1 · 1: RSA n in k1, d in k2, e in k3 ·
    // 2: ML-DSA secret key in k1, its length naming the parameter set
    ? == kt 0 { = out ( quic_creds_new chain 0 k1 e e e 0 ) } {}
    ? == kt 1 { = out ( quic_creds_new chain 1 e k1 k3 k2 0 ) } {}
    ? == kt 2 { = out ( quic_creds_new chain 2 k1 e e e ( mldsa_level_of_sk_len ( vec_len [u] k1 ) ) ) } {}
    ^ out
}

// Add the second, ML-DSA identity `tcp_listen_tls_dual` serves on the TCP
// side, so QUIC connections get the same per-ClientHello choice
// (RFC 8446 §4.4.2.2). F when the files do not load or the key is not
// an ML-DSA key — the same refusal the TCP listener makes.
@ http3_creds_add_pq QuicCreds k s pq_cert_path s pq_key_path → b {
    : ( Vec u ) chain ( vec_new [u] )
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : i kt ( _load_tls_creds pq_cert_path pq_key_path chain k1 k2 k3 )
    : b ok == kt 2
    ? ok { ( quic_creds_set_pq k chain ( mldsa_level_of_sk_len ( vec_len [u] k1 ) ) k1 ) } {}
    ^ ok
}

// Limits: 30 s idle, 1 MiB connection window, 256 KiB per stream,
// 100 request streams, 3 unidirectional (control + 2 QPACK).
@ http3_default_tp → QuicTp {
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
