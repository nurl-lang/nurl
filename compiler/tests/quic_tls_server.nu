// quic_tls_server.nu — stdlib/std/quic_tls.nu (RFC 9001 §4, server
// role) driven with the RFC 9001 Appendix A.2 ClientHello, which
// carries a quic_transport_parameters extension, ALPN "alpn" and an
// x25519 key share. Offline: the client's key is random, so the client
// Finished cannot be produced here; what is pinned is everything up to
// and including the server's first flight, plus every refusal the
// h3spec transport suite provokes at the TLS layer:
//
//   * a ClientHello delivered in three CRYPTO chunks, out of order
//   * ServerHello out at Initial, EE‖Certificate‖CertificateVerify‖Finished
//     out at Handshake; EE carries our transport parameters (0x0039)
//   * handshake secrets present, application secrets present
//   * the client's transport parameters read back verbatim
//   * CH without 0x0039           → CRYPTO_ERROR(missing_extension)      0x16d
//   * ALPN with nothing we serve  → CRYPTO_ERROR(no_application_protocol) 0x178
//   * CH offering no ALPN at all  → 0x178 as well (QUIC needs ALPN)
//   * KeyUpdate at Handshake / 1-RTT, EndOfEarlyData at Handshake,
//     ClientHello at Handshake    → CRYPTO_ERROR(unexpected_message)     0x10a
//   * a second ClientHello        → 0x10a
//   * CRYPTO past the 64 KB cap   → CRYPTO_BUFFER_EXCEEDED               0x0d
//   * any CRYPTO after a failure  → PROTOCOL_VIOLATION                   0x0a

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_tls.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

@ check_int s label i got i want → i {
    ? == got want {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( nurl_str_int got ) ) ( nurl_print ` want ` )
        ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
        ^ 1
    }
}

// The A.2 ClientHello handshake message (the CRYPTO frame payload
// without its 4-byte frame header).
@ client_hello → ( Vec u ) {
    ^ ( hx `010000ed0303ebf8fa56f12939b9584a3896472ec40bb863cfd3e86804fe3a47f06a2b69484c00000413011302010000c000000010000e00000b6578616d706c652e636f6dff01000100000a00080006001d0017001800100007000504616c706e000500050100000000003300260024001d00209370b2c9caa47fbabaf4559fedba753de171fa71f50f1ce15d43e994ec74d748002b0003020304000d0010000e0403050306030203080408050806002d00020101001c00024001003900320408ffffffffffffffff05048000ffff07048000ffff0801100104800075300901100f088394c8f03e51570806048000ffff` )
}

// The same ClientHello with the extension of type `drop` removed and
// the three length fields fixed up. Extensions start at offset 0xd1
// (4 + 2 + 32 + 1 + 6 + 1 + 2 ... computed below from the message).
@ client_hello_without i drop → ( Vec u ) {
    : ( Vec u ) ch ( client_hello )
    : ( Vec u ) out ( vec_new [u] )
    // fixed part: type(1) len(3) version(2) random(32) sid_len(1)
    : i sidlen ( _t_bget ch 38 )
    : i p1 + 39 sidlen
    : i cslen ( _rdint ch p1 2 )
    : i p2 + + p1 2 cslen
    : i complen ( _t_bget ch p2 )
    : i p3 + + p2 1 complen
    : i extlen ( _rdint ch p3 2 )
    : i es + p3 2
    : i ee + es extlen
    : ( Vec u ) head ( bytes_slice ch 4 p3 )
    : ( Vec u ) exts ( vec_new [u] )
    : ~ i p es
    ~ < + p 4 ee {
        : i t ( _rdint ch p 2 )
        : i l ( _rdint ch + p 2 2 )
        ? != t drop {
            : ( Vec u ) e ( bytes_slice ch p + + p 4 l )
            ( bytes_extend_bytes exts e )
            ( vec_free [u] e )
        } {}
        = p + + p 4 l
    }
    : ( Vec u ) body ( vec_new [u] )
    ( bytes_extend_bytes body head )
    ( _blk16 body exts )
    ( vec_push [u] out # u 1 )
    ( _u24 out ( vec_len [u] body ) )
    ( bytes_extend_bytes out body )
    ( vec_free [u] body )
    ( vec_free [u] exts )
    ( vec_free [u] head )
    ( vec_free [u] ch )
    ^ out
}

@ new_server ( Vec u ) g_chain ( Vec u ) g_priv ( Vec u ) g_tp s alpn → *QuicTlsSrv {
    : ( Vec u ) e ( vec_new [u] )
    : ( Vec u ) prefs ( tls_alpn_pack alpn )
    : *QuicTlsSrv s ( quic_tls_srv_new g_chain 0 g_priv e e e 0 prefs g_tp )
    ( vec_free [u] prefs )
    ( vec_free [u] e )
    ^ s
}

@ feed * QuicTlsSrv s i level i off ( Vec u ) msg → i {
    ^ ( quic_tls_srv_crypto s level off msg )
}

@ main → i {
    : ~ i fails 0

    // ── credentials: a fresh self-signed P-256 leaf ──────────────
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : ~ ( Vec u ) g_chain ( vec_new [u] )
    : ~ ( Vec u ) g_priv ( vec_new [u] )
    ?? ( pem_to_der ( string_data . cert cert_pem ) ) {
        T der → { ( vec_free [u] g_chain ) = g_chain ( tls_cert_entry der ) ( vec_free [u] der ) }
        F _ → { ( nurl_print `cert_der: FAIL\n` ) ^ 1 }
    }
    ?? ( ec_p256_priv_from_pem ( string_data . cert key_pem ) ) {
        T k → { ( vec_free [u] g_priv ) = g_priv k }
        F _ → { ( nurl_print `key_pem: FAIL\n` ) ^ 1 }
    }
    ( x509_selfsigned_free cert )
    : *QuicTp tp ( quic_tp_new )
    = . tp initial_max_data 1048576
    = . tp initial_max_streams_bidi 100
    = . tp has_initial_scid 1
    : ( Vec u ) tmp1 ( hx `f067a5502a4262b5` )
    ( bytes_extend_bytes . tp initial_scid tmp1 )
    ( vec_free [u] tmp1 )
    = . tp has_original_dcid 1
    : ( Vec u ) tmp2 ( hx `8394c8f03e515708` )
    ( bytes_extend_bytes . tp original_dcid tmp2 )
    ( vec_free [u] tmp2 )
    : ( Vec u ) g_tp ( quic_tp_encode tp T )
    ( quic_tp_free tp )

    // ── 1. the A.2 ClientHello in three chunks, out of order ─────
    : ( Vec u ) ch ( client_hello )
    = fails + fails ( check_int `ch_len` ( vec_len [u] ch ) 241 )
    : *QuicTlsSrv s ( new_server g_chain g_priv g_tp `alpn` )
    : ( Vec u ) c1 ( bytes_slice ch 0 100 )
    : ( Vec u ) c2 ( bytes_slice ch 100 180 )
    : ( Vec u ) c3 ( bytes_slice ch 180 241 )
    = fails + fails ( check_int `chunk3_first` ( feed s 0 180 c3 ) 0 )
    = fails + fails ( check_int `state_after_chunk3` ( quic_tls_srv_state s ) 0 )
    = fails + fails ( check_int `chunk1` ( feed s 0 0 c1 ) 0 )
    = fails + fails ( check_int `state_after_chunk1` ( quic_tls_srv_state s ) 0 )
    = fails + fails ( check_int `chunk2_completes` ( feed s 0 100 c2 ) 0 )
    = fails + fails ( check_int `state_after_ch` ( quic_tls_srv_state s ) 1 )
    // retransmitted chunk: harmless
    = fails + fails ( check_int `chunk1_again` ( feed s 0 0 c1 ) 0 )
    = fails + fails ( check_int `state_after_dup` ( quic_tls_srv_state s ) 1 )
    ( vec_free [u] c1 ) ( vec_free [u] c2 ) ( vec_free [u] c3 )

    // outputs
    : ( Vec u ) o0 ( quic_tls_srv_take_out s 0 )
    = fails + fails ( check_int `initial_out_is_serverhello` ( _t_bget o0 0 ) 2 )
    = fails + fails ( check_int `initial_out_len` ( vec_len [u] o0 ) + 4 ( _rdint o0 1 3 ) )
    : ( Vec u ) o0b ( quic_tls_srv_take_out s 0 )
    = fails + fails ( check_int `initial_out_taken_once` ( vec_len [u] o0b ) 0 )
    : ( Vec u ) o1 ( quic_tls_srv_take_out s 1 )
    = fails + fails ( check_int `handshake_out_is_ee` ( _t_bget o1 0 ) 8 )
    // EE body: [ext block len:2] then extensions; ALPN (0x0010) comes
    // first, quic_transport_parameters (0x0039) after it.
    : i extblk ( _rdint o1 4 2 )
    : ~ i ep 6
    : ~ i seen_alpn 0
    : ~ i seen_tp 0
    : ~ i tp_match 0
    ~ < + ep 4 + 6 extblk {
        : i et ( _rdint o1 ep 2 )
        : i el ( _rdint o1 + ep 2 2 )
        ? == et 16 { = seen_alpn 1 } {}
        ? == et 57 {
            = seen_tp 1
            : ( Vec u ) tpb ( bytes_slice o1 + ep 4 + + ep 4 el )
            ? ( bytes_eq tpb g_tp ) { = tp_match 1 } {}
            ( vec_free [u] tpb )
        } {}
        = ep + + ep 4 el
    }
    = fails + fails ( check_int `ee_has_alpn` seen_alpn 1 )
    = fails + fails ( check_int `ee_has_0x39` seen_tp 1 )
    = fails + fails ( check_int `ee_tp_bytes_match` tp_match 1 )
    = fails + fails ( check_int `ee_ext_block_exact` ep + 6 extblk )
    // walk the message list: EE(8), Certificate(11), CertificateVerify(15), Finished(20)
    : ~ i off 0
    : ~ i types 0
    ~ < + off 4 ( vec_len [u] o1 ) {
        : i mt ( _t_bget o1 off )
        = types + * types 100 mt
        = off + + off 4 ( _rdint o1 + off 1 3 )
    }
    = fails + fails ( check_int `handshake_out_types` types 8111520 )
    = fails + fails ( check_int `handshake_out_exact` off ( vec_len [u] o1 ) )
    : ( Vec u ) o2 ( quic_tls_srv_take_out s 2 )
    = fails + fails ( check_int `app_out_empty_before_finished` ( vec_len [u] o2 ) 0 )
    ( vec_free [u] o2 ) ( vec_free [u] o1 ) ( vec_free [u] o0b ) ( vec_free [u] o0 )

    // secrets + negotiated values
    = fails + fails ( check_int `c_hs_len` ( vec_len [u] ( quic_tls_srv_c_hs s ) ) 32 )
    = fails + fails ( check_int `s_hs_len` ( vec_len [u] ( quic_tls_srv_s_hs s ) ) 32 )
    = fails + fails ( check_int `c_ap_len` ( vec_len [u] ( quic_tls_srv_c_ap s ) ) 32 )
    = fails + fails ( check_int `s_ap_len` ( vec_len [u] ( quic_tls_srv_s_ap s ) ) 32 )
    = fails + fails ( check_int `cipher_aes_only_offered` ( quic_tls_srv_cipher s ) 1 )
    : ( Vec u ) alpn ( quic_tls_srv_alpn s )
    = fails + fails ( check_int `alpn_len` ( vec_len [u] alpn ) 4 )
    : ( Vec u ) ctp ( quic_tls_srv_client_tp s )
    = fails + fails ( check_int `client_tp_len` ( vec_len [u] ctp ) 50 )
    : *QuicTp dec ( quic_tp_decode ctp T )
    ? == # i dec 0 { ( nurl_print `client_tp_decode: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `client_tp_idle` . dec max_idle_timeout 30000 )
        ( quic_tp_free dec )
    }

    // ── 2. wrong messages after the ClientHello ──────────────────
    : ( Vec u ) keyupdate ( hx `1800000100` )
    = fails + fails ( check_int `keyupdate_at_handshake` ( feed s 1 0 keyupdate ) 266 )
    = fails + fails ( check_int `state_failed` ( quic_tls_srv_state s ) 3 )
    : ( Vec u ) ping ( hx `01` )
    = fails + fails ( check_int `after_failure_protocol_violation` ( feed s 2 0 ping ) 10 )
    ( quic_tls_srv_free s )

    : *QuicTlsSrv s2 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `s2_ch` ( feed s2 0 0 ch ) 0 )
    = fails + fails ( check_int `keyupdate_at_1rtt` ( feed s2 2 0 keyupdate ) 266 )
    ( quic_tls_srv_free s2 )

    : *QuicTlsSrv s3 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `s3_ch` ( feed s3 0 0 ch ) 0 )
    : ( Vec u ) eoed ( hx `05000000` )
    = fails + fails ( check_int `end_of_early_data_at_handshake` ( feed s3 1 0 eoed ) 266 )
    ( quic_tls_srv_free s3 )

    : *QuicTlsSrv s4 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `s4_ch` ( feed s4 0 0 ch ) 0 )
    = fails + fails ( check_int `second_client_hello` ( feed s4 0 241 ch ) 266 )
    ( quic_tls_srv_free s4 )

    : *QuicTlsSrv s5 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `client_hello_at_handshake_level` ( feed s5 1 0 ch ) 266 )
    ( quic_tls_srv_free s5 )

    // ── 3. ClientHello refusals ──────────────────────────────────
    : *QuicTlsSrv s6 ( new_server g_chain g_priv g_tp `h3` )
    = fails + fails ( check_int `alpn_no_overlap` ( feed s6 0 0 ch ) 376 )
    ( quic_tls_srv_free s6 )

    : ( Vec u ) ch_no_tp ( client_hello_without 57 )
    = fails + fails ( check_int `ch_no_tp_shorter` ? < ( vec_len [u] ch_no_tp ) 241 1 0 1 )
    : *QuicTlsSrv s7 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `missing_transport_parameters` ( feed s7 0 0 ch_no_tp ) 365 )
    ( quic_tls_srv_free s7 )
    ( vec_free [u] ch_no_tp )

    : ( Vec u ) ch_no_alpn ( client_hello_without 16 )
    : *QuicTlsSrv s8 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `no_alpn_at_all` ( feed s8 0 0 ch_no_alpn ) 376 )
    ( quic_tls_srv_free s8 )
    ( vec_free [u] ch_no_alpn )

    // ── 4. buffer cap ────────────────────────────────────────────
    : *QuicTlsSrv s9 ( new_server g_chain g_priv g_tp `alpn` )
    = fails + fails ( check_int `crypto_past_cap` ( feed s9 0 65536 ping ) 13 )
    // an in-range chunk that does not complete a message: fine
    : *QuicTlsSrv s10 ( new_server g_chain g_priv g_tp `alpn` )
    : ( Vec u ) partial ( bytes_slice ch 0 3 )
    = fails + fails ( check_int `partial_header_waits` ( feed s10 0 0 partial ) 0 )
    = fails + fails ( check_int `partial_state` ( quic_tls_srv_state s10 ) 0 )
    ( vec_free [u] partial )
    ( quic_tls_srv_free s10 )
    ( quic_tls_srv_free s9 )

    ( vec_free [u] eoed )
    ( vec_free [u] ping )
    ( vec_free [u] keyupdate )
    ( vec_free [u] ch )
    ( vec_free [u] g_tp )
    ( vec_free [u] g_priv )
    ( vec_free [u] g_chain )

    ? == fails 0 { ( nurl_print `quic_tls_server: all PASS\n` ) } { ( nurl_print `quic_tls_server: FAILURES\n` ) }
    ^ fails
}
