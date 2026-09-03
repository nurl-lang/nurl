// stdlib/std/quic_tls.nu — QUIC's use of TLS 1.3 (RFC 9001 §4), server
// role. The handshake itself is `std/tls_server.nu`'s message-level
// machine (`_srv_hs_*`); this file is the CRYPTO-frame side of it:
// bytes arrive per encryption level with stream offsets (any order,
// any split), whole handshake messages go in, and the messages the
// server must send come out per level for the connection to put in
// CRYPTO frames. Traffic secrets are read straight off the machine so
// the connection derives packet keys with `quic_keys_derive`.
//
//   ( quic_tls_srv_new cert_chain keytype ec_priv rsa_n rsa_e rsa_d ml_level alpn_prefs tp )
//                                         → *QuicTlsSrv   `tp` = encoded quic_transport_parameters body
//   ( quic_tls_srv_free s )               → v
//   ( quic_tls_srv_crypto s level off data ) → i          0 ok, else a QUIC transport error code:
//                                                          0x100+alert (CRYPTO_ERROR), 0x0a PROTOCOL_VIOLATION,
//                                                          0x0d CRYPTO_BUFFER_EXCEEDED
//   ( quic_tls_srv_state s )              → i             0 awaiting ClientHello · 1 awaiting client Finished ·
//                                                          2 handshake confirmed · 3 failed
//   ( quic_tls_srv_take_out s level )     → ( Vec u )     OWNED bytes to send as CRYPTO at that level
//                                                          (0 Initial, 1 Handshake, 2 1-RTT); empty when none
//   ( quic_tls_srv_client_tp s )          → ( Vec u )     BORROWED body of the client's transport parameters
//   ( quic_tls_srv_cipher s )             → i             quic_packet cipher id: 1 AES-128-GCM, 2 ChaCha20-Poly1305
//   ( quic_tls_srv_alpn s )               → ( Vec u )     BORROWED selected ALPN
//   secrets (BORROWED, valid once state ≥ 1): quic_tls_srv_c_hs / _s_hs / _c_ap / _s_ap
//
// What this refuses (each an h3spec "QUIC servers" case, RFC 9001 §4.1.3
// / §8.1–8.3): a TLS KeyUpdate or EndOfEarlyData message at any level,
// a ClientHello anywhere but Initial, anything after the Finished, a
// ClientHello without the transport-parameters extension
// (missing_extension), a ClientHello whose ALPN does not name a protocol
// this server serves — or that offers no ALPN at all
// (no_application_protocol; QUIC has no other way to pick one).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/quic_rxbuf.nu`

// RFC 9000 §7.5 asks for at least 4096 bytes of buffering per level; a
// ClientHello with a hybrid key share is ~1.3 KB, a post-quantum
// certificate chain several KB. 64 KB is well past any handshake.
@ quic_crypto_rx_cap → i { ^ 65536 }

@ __qt_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// The next complete handshake message ([type][u24 len][body]) from the
// contiguous prefix, or an empty Vec when none is complete yet.
@ __qt_rx_take * QuicRxBuf r → ( Vec u ) {
    : i avail ( quic_rxbuf_avail r )
    ? < avail 4 { ^ ( vec_new [u] ) } {}
    : i mlen | | << ( quic_rxbuf_peek_u8 r 1 ) 16 << ( quic_rxbuf_peek_u8 r 2 ) 8 ( quic_rxbuf_peek_u8 r 3 )
    ? < avail + 4 mlen { ^ ( vec_new [u] ) } {}
    ^ ( quic_rxbuf_read r + 4 mlen )
}

: QuicTlsSrv {
    * SrvHs hs
    * QuicRxBuf rx0
    * QuicRxBuf rx1
    * QuicRxBuf rx2
    i state
    i seen_ch
    ( Vec u ) out0
    ( Vec u ) out1
    ( Vec u ) out2
}

@ quic_tls_srv_new ( Vec u ) cert_chain i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d i ml_level ( Vec u ) alpn_prefs ( Vec u ) tp → *QuicTlsSrv {
    : *QuicTlsSrv s # *QuicTlsSrv ( nurl_alloc Z QuicTlsSrv )
    = . s hs ( _srv_hs_new cert_chain keytype ec_priv rsa_n rsa_e rsa_d ml_level alpn_prefs )
    // EncryptedExtensions carries quic_transport_parameters (0x0039).
    : ( Vec u ) ext ( vec_with_cap [u] + 4 ( vec_len [u] tp ) )
    ( _tls_u16 ext 57 )
    ( _blk16 ext tp )
    ( _srv_hs_set_ext . s hs 57 ext )
    ( vec_free [u] ext )
    = . s rx0 ( quic_rxbuf_new ( quic_crypto_rx_cap ) )
    = . s rx1 ( quic_rxbuf_new ( quic_crypto_rx_cap ) )
    = . s rx2 ( quic_rxbuf_new ( quic_crypto_rx_cap ) )
    = . s state 0
    = . s seen_ch 0
    = . s out0 ( vec_new [u] )
    = . s out1 ( vec_new [u] )
    = . s out2 ( vec_new [u] )
    ^ s
}

@ quic_tls_srv_free * QuicTlsSrv s → v {
    ? == # i s 0 { ^ } {}
    ( _srv_hs_free . s hs )
    ( quic_rxbuf_free . s rx0 )
    ( quic_rxbuf_free . s rx1 )
    ( quic_rxbuf_free . s rx2 )
    ( vec_free [u] . s out0 )
    ( vec_free [u] . s out1 )
    ( vec_free [u] . s out2 )
    ( nurl_free # s s )
}

@ quic_tls_srv_state * QuicTlsSrv s → i { ^ . s state }

@ __qt_rx_of * QuicTlsSrv s i level → *QuicRxBuf {
    ? == level 0 { ^ . s rx0 } {}
    ? == level 1 { ^ . s rx1 } {}
    ^ . s rx2
}

// QUIC transport error codes this file produces.
@ quic_err_protocol_violation → i { ^ 10 }

@ quic_err_crypto_buffer_exceeded → i { ^ 13 }

@ quic_err_crypto i alert → i { ^ + 256 alert }

// Handle one complete handshake message at `level`.
@ __qt_message * QuicTlsSrv s i level ( Vec u ) m → i {
    : i mtype ( __qt_bget m 0 )
    // Messages QUIC forbids outright (RFC 9001 §4.1.3, §8.3, §6).
    ? | == mtype 24 == mtype 5 { ^ ( quic_err_crypto 10 ) } {}
    ? == level 0 {
        ? | != mtype 1 != . s seen_ch 0 { ^ ( quic_err_crypto 10 ) } {}
        = . s seen_ch 1
        : i rc ( _srv_hs_client_hello . s hs m )
        ? != rc 0 { = . s state 3 ^ ( quic_err_crypto rc ) } {}
        // QUIC has no other way to agree on an application protocol
        // (RFC 9001 §8.1): no ALPN at all is no_application_protocol too.
        ? == ( vec_len [u] . . s hs alpn_sel ) 0 { = . s state 3 ^ ( quic_err_crypto 120 ) } {}
        ( bytes_extend_bytes . s out0 . . s hs out_sh )
        ( bytes_extend_bytes . s out1 . . s hs out_hs )
        = . s state 1
        ^ 0
    } {}
    ? == level 1 {
        ? | != mtype 20 != . s state 1 { ^ ( quic_err_crypto 10 ) } {}
        : i rc ( _srv_hs_client_finished . s hs m )
        ? != rc 0 { = . s state 3 ^ ( quic_err_crypto rc ) } {}
        ( bytes_extend_bytes . s out2 . . s hs out_ticket )
        = . s state 2
        ^ 0
    } {}
    // 1-RTT: a server expects no post-handshake message from a client
    // (client NewSessionTicket / KeyUpdate are both illegal here).
    ^ ( quic_err_crypto 10 )
}

// Feed CRYPTO frame bytes. Returns 0, or the transport error code the
// connection must close with.
@ quic_tls_srv_crypto * QuicTlsSrv s i level i off ( Vec u ) data → i {
    ? == . s state 3 { ^ ( quic_err_protocol_violation ) } {}
    ? | < level 0 > level 2 { ^ ( quic_err_protocol_violation ) } {}
    : *QuicRxBuf r ( __qt_rx_of s level )
    ? ! ( quic_rxbuf_add r off data ) { ^ ( quic_err_crypto_buffer_exceeded ) } {}
    ~ T {
        : ( Vec u ) m ( __qt_rx_take r )
        ? == ( vec_len [u] m ) 0 { ( vec_free [u] m ) ^ 0 } {}
        : i rc ( __qt_message s level m )
        ( vec_free [u] m )
        ? != rc 0 { = . s state 3 ^ rc } {}
    }
    ^ 0
}

// OWNED: the bytes queued for CRYPTO frames at `level`, cleared here.
@ quic_tls_srv_take_out * QuicTlsSrv s i level → ( Vec u ) {
    : ( Vec u ) src ? == level 0 . s out0 ? == level 1 . s out1 . s out2
    : ( Vec u ) out ( bytes_slice src 0 ( vec_len [u] src ) )
    ( vec_clear [u] src )
    ^ out
}

@ quic_tls_srv_client_tp * QuicTlsSrv s → ( Vec u ) { ^ . . s hs ext_in }

@ quic_tls_srv_alpn * QuicTlsSrv s → ( Vec u ) { ^ . . s hs alpn_sel }

@ quic_tls_srv_cipher * QuicTlsSrv s → i { ^ ? == . . s hs cipher 1 1 2 }

@ quic_tls_srv_c_hs * QuicTlsSrv s → ( Vec u ) { ^ . . s hs c_hs }

@ quic_tls_srv_s_hs * QuicTlsSrv s → ( Vec u ) { ^ . . s hs s_hs }

@ quic_tls_srv_c_ap * QuicTlsSrv s → ( Vec u ) { ^ . . s hs c_ap }

@ quic_tls_srv_s_ap * QuicTlsSrv s → ( Vec u ) { ^ . . s hs s_ap }
