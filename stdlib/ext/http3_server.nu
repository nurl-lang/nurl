// stdlib/ext/http3_server.nu — HTTP/3 on a UDP socket: the QUIC
// listener (`std/quic_server.nu`) with an HTTP/3 connection per QUIC
// connection, all requests handed to the same `( @ HttpResponse
// HttpRequest )` handler the HTTP/1.1 and HTTP/2 paths use.
//
//   ( http3_server_new sock creds alpn_prefs tp handler body_max ) → *H3Server
//   ( http3_server_run s )                                         → v   the loop (a fiber or a thread)
//   ( http3_server_stop s )                                        → v
//   ( http3_server_free s )                                        → v
//   ( http3_creds_load cert_path key_path )                        → *QuicCreds   0 on error (EC P-256 or RSA PEM)
//   ( http3_default_tp )                                           → *QuicTp      the limits this server advertises
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

: H3Server {
    * QuicServer qs
    ( HashMap i i ) h3s
    ( @ HttpResponse HttpRequest ) handler
    i body_max
    ( @ v i i ) ev
}

@ __h3s_map_get ( HashMap i i ) m i key → i {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    ^ ?? ( map_get [i i] m key hf ef ) { T v → v F → 0 }
}

@ __h3s_map_set ( HashMap i i ) m i key i val → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?i _old ( map_set [i i] m key val hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __h3s_map_del ( HashMap i i ) m i key → v {
    : ( @ i i ) hf \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ef \ i a i b → b { ^ ( eq_int a b ) }
    : ?i _old ( map_remove [i i] m key hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __h3s_event * H3Server s i cp i ev → v {
    : *QuicConn qc # *QuicConn cp
    ? == ev 1 {
        : *H3Conn h ( h3_conn_new qc . s body_max )
        ( __h3s_map_set . s h3s cp # i h )
        ^
    } {}
    : *H3Conn h # *H3Conn ( __h3s_map_get . s h3s cp )
    ? == ev 2 {
        ? != # i h 0 { ( h3_conn_on_readable h . s handler ) } {}
        ^
    } {}
    ? == ev 3 {
        ? != # i h 0 { ( h3_conn_free h ) ( __h3s_map_del . s h3s cp ) } {}
    } {}
}

@ http3_server_new UdpSocket sock * QuicCreds creds ( Vec u ) alpn_prefs * QuicTp tp ( @ HttpResponse HttpRequest ) handler i body_max → *H3Server {
    : *H3Server s # *H3Server ( nurl_alloc Z H3Server )
    = . s h3s ( map_new [i i] )
    = . s handler handler
    = . s body_max body_max
    : ( @ v i i ) ev \ i cp i e → v { ( __h3s_event s cp e ) }
    = . s ev ev
    = . s qs ( quic_server_new sock creds alpn_prefs tp ev )
    ^ s
}

@ http3_server_run * H3Server s → v { ( quic_server_run . s qs ) }

@ http3_server_stop * H3Server s → v { ( quic_server_stop . s qs ) }

@ http3_server_accepted * H3Server s → i { ^ ( quic_server_accepted . s qs ) }

@ http3_server_free * H3Server s → v {
    ? == # i s 0 { ^ } {}
    ( quic_server_free . s qs )
    ( map_free [i i] . s h3s )
    // the event closure captured `s`; its env is ours to release
    : *u env # *u . s ev 1
    ( nurl_free # s env )
    ( nurl_free # s s )
}

// The same certificate / key files the TLS listener takes, through the
// same loader (`std/net.nu` `_load_tls_creds`: fullchain PEM; EC P-256,
// RSA or ML-DSA key auto-detected).
@ http3_creds_load s cert_path s key_path → *QuicCreds {
    : ( Vec u ) chain ( vec_new [u] )
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : i kt ( _load_tls_creds cert_path key_path chain k1 k2 k3 )
    : ~ * QuicCreds out # *QuicCreds 0
    : ( Vec u ) e ( vec_new [u] )
    // keytype 0: EC scalar in k1 · 1: RSA n in k1, d in k2, e in k3 ·
    // 2: ML-DSA secret key in k1, its length naming the parameter set
    ? == kt 0 { = out ( quic_creds_new chain 0 k1 e e e 0 ) } {}
    ? == kt 1 { = out ( quic_creds_new chain 1 e k1 k3 k2 0 ) } {}
    ? == kt 2 { = out ( quic_creds_new chain 2 k1 e e e ( mldsa_level_of_sk_len ( vec_len [u] k1 ) ) ) } {}
    ( vec_free [u] e ) ( vec_free [u] k3 ) ( vec_free [u] k2 ) ( vec_free [u] k1 ) ( vec_free [u] chain )
    ^ out
}

// Add the second, ML-DSA identity `tcp_listen_tls_dual` serves on the TCP
// side, so QUIC connections get the same per-ClientHello choice
// (RFC 8446 §4.4.2.2). F when the files do not load or the key is not
// an ML-DSA key — the same refusal the TCP listener makes.
@ http3_creds_add_pq * QuicCreds k s pq_cert_path s pq_key_path → b {
    : ( Vec u ) chain ( vec_new [u] )
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : i kt ( _load_tls_creds pq_cert_path pq_key_path chain k1 k2 k3 )
    : b ok == kt 2
    ? ok { ( quic_creds_set_pq k chain ( mldsa_level_of_sk_len ( vec_len [u] k1 ) ) k1 ) } {}
    ( vec_free [u] k3 ) ( vec_free [u] k2 ) ( vec_free [u] k1 ) ( vec_free [u] chain )
    ^ ok
}

// Limits: 30 s idle, 1 MiB connection window, 256 KiB per stream,
// 100 request streams, 3 unidirectional (control + 2 QPACK).
@ http3_default_tp → *QuicTp {
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
