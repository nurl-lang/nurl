// quic_client_retry.nu — the client role of std/quic_conn.nu on the
// two server answers that arrive before any packet can be decrypted,
// driven sans-IO (datagrams built with std/quic_packet.nu, no socket):
//
//   * Retry (RFC 9000 §17.2.5): a Retry with a good integrity tag
//     changes the DCID to the Retry's SCID, puts the token in every
//     following Initial, sends the ClientHello again, and continues the
//     packet-number space (the second Initial is packet 1, not 0); a
//     second Retry is ignored, and so is one with a bad tag or one that
//     names our own DCID.
//   * Version Negotiation (§6.2): one that lists version 1 is a fake
//     and ignored; one without it ends the attempt (closed, nothing
//     sent); one arriving after a Retry — i.e. after the client has
//     acted on a server packet — is ignored too.
//
// The first datagram is also checked to be what §14.1 and §7.2 ask of a
// client Initial: 1200 bytes, an 8-byte DCID we chose, no token.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/quic_packet.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ label_int s k i v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` )
}

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

// Every datagram the connection wants to send right now, concatenated
// — the hybrid ClientHello spans two Initials. `first` gets the first.
@ drain * QuicConn c i now ( Vec u ) first → i {
    : ~ i n 0
    : ~ i more 1
    ~ != more 0 {
        : ( Vec u ) d ( quic_conn_send c now )
        ? == ( vec_len [u] d ) 0 { = more 0 } {
            ? == n 0 { ( bytes_extend_bytes first d ) } {}
            = n + n 1
        }
        ( vec_free [u] d )
    }
    ^ n
}

@ fresh_client * QuicTp tp → *QuicConn {
    : ( Vec u ) peer ( udp_addr_new )
    : *QuicConn c ( quic_conn_new_client peer `localhost` `h3` tp 0 1000 )
    ( vec_free [u] peer )
    ^ c
}

// A Version Negotiation packet for the client's first Initial.
@ vn_for ( Vec u ) initial ( Vec i ) versions → ( Vec u ) {
    : *QuicHdr h ( quic_hdr_parse initial 0 8 )
    : ( Vec u ) dcid ( quic_hdr_dcid h initial )
    : ( Vec u ) scid ( quic_hdr_scid h initial )
    : ( Vec u ) vn ( quic_vn_build scid dcid versions )
    ( vec_free [u] scid ) ( vec_free [u] dcid ) ( quic_hdr_free h )
    ^ vn
}

@ run_retry → v {
    : *QuicTp tp ( quic_tp_new )
    = . tp initial_max_data 65536
    = . tp initial_max_stream_data_bidi_local 16384
    = . tp initial_max_stream_data_bidi_remote 16384
    = . tp initial_max_stream_data_uni 16384
    = . tp initial_max_streams_bidi 4
    = . tp initial_max_streams_uni 3
    : *QuicConn c ( fresh_client tp )
    : ( Vec u ) peer ( udp_addr_new )
    : ( Vec u ) d1 ( vec_new [u] )
    ( label_int `initial_datagrams` ( drain c 1000 d1 ) )
    ( label_int `initial_len` ( vec_len [u] d1 ) )
    : *QuicHdr h1 ( quic_hdr_parse d1 0 8 )
    ( label `initial_type` ? == . h1 ptype 0 `Initial` `OTHER` )
    ( label_int `initial_dcid_len` . h1 dcid_len )
    ( label_int `initial_token_len` . h1 token_len )
    : ( Vec u ) odcid ( quic_hdr_dcid h1 d1 )
    : ( Vec u ) cscid ( quic_hdr_scid h1 d1 )
    ( quic_hdr_free h1 )
    ( label `odcid_is_ours` ? ( bytes_eq odcid ( quic_conn_odcid c ) ) `T` `F` )

    // a Retry from the server: new SCID, a token, the tag over our ODCID
    : ( Vec u ) rscid ( hx `a1a2a3a4a5a6a7a8` )
    : ( Vec u ) token ( hx `746f6b656e2d31` )
    : ( Vec u ) retry ( quic_retry_build cscid rscid odcid token )
    // ... first a corrupted one (tag wrong): must be ignored
    : ( Vec u ) bad ( bytes_slice retry 0 ( vec_len [u] retry ) )
    : i lastk - ( vec_len [u] bad ) 1
    : i lastv ?? ( vec_get [u] bad lastk ) { T x → # i x F → 0 }
    : b _s ( vec_set [u] bad lastk # u ^^ lastv 255 )
    ( quic_conn_recv c bad peer 1001 )
    : ( Vec u ) after_bad ( vec_new [u] )
    : i nbad ( drain c 1002 after_bad )
    ( label `bad_tag_ignored` ? & == nbad 0 == ( quic_conn_state c ) 0 `T` `F` )
    ( vec_free [u] after_bad ) ( vec_free [u] bad )
    // ... then the real one
    ( quic_conn_recv c retry peer 1003 )
    : ( Vec u ) d2 ( vec_new [u] )
    ( label_int `retried_datagrams` ( drain c 1004 d2 ) )
    ( label_int `retried_len` ( vec_len [u] d2 ) )
    : *QuicHdr h2 ( quic_hdr_parse d2 0 8 )
    : ( Vec u ) d2dcid ( quic_hdr_dcid h2 d2 )
    : ( Vec u ) d2tok ( quic_hdr_token h2 d2 )
    ( label `retried_dcid_is_retry_scid` ? ( bytes_eq d2dcid rscid ) `T` `F` )
    ( label `retried_carries_token` ? ( bytes_eq d2tok token ) `T` `F` )
    // the packet number continues (§17.2.5.3): remove header protection
    // with the Initial keys of the new DCID and read it
    : *QuicKeys k ( quic_initial_keys rscid T )
    : ( Vec u ) pkt ( bytes_slice d2 0 . h2 end )
    : i pn_len ( quic_hp_remove k pkt . h2 pn_off )
    : i pn ( quic_pn_read pkt . h2 pn_off pn_len )
    ( label_int `retried_pn` pn )
    // and it carries the ClientHello again: the payload decrypts and
    // starts with a CRYPTO frame at offset 0 (0x06 0x00)
    : ( Vec u ) hdr ( bytes_slice pkt 0 + . h2 pn_off pn_len )
    : ( Vec u ) body ( bytes_slice pkt + . h2 pn_off pn_len ( vec_len [u] pkt ) )
    ?? ( quic_open k pn hdr body ) {
        T pl → {
            : i b0 ?? ( vec_get [u] pl 0 ) { T x → # i x F → -1 }
            : i b1 ?? ( vec_get [u] pl 1 ) { T x → # i x F → -1 }
            ( label `retried_crypto_at_0` ? & == b0 6 == b1 0 `T` `F` )
            ( vec_free [u] pl )
        }
        F → { ( label `retried_crypto_at_0` `NO-DECRYPT` ) }
    }
    ( vec_free [u] body ) ( vec_free [u] hdr ) ( vec_free [u] pkt ) ( quic_keys_free k )
    ( vec_free [u] d2tok ) ( vec_free [u] d2dcid ) ( quic_hdr_free h2 )
    // a second Retry is ignored (§17.2.5.2)
    : ( Vec u ) rscid2 ( hx `b1b2b3b4b5b6b7b8` )
    : ( Vec u ) retry2 ( quic_retry_build cscid rscid2 odcid token )
    ( quic_conn_recv c retry2 peer 1005 )
    : ( Vec u ) d3 ( vec_new [u] )
    : i n3 ( drain c 1006 d3 )
    ( label `second_retry_ignored` ? == n3 0 `T` `F` )
    ( vec_free [u] d3 ) ( vec_free [u] retry2 ) ( vec_free [u] rscid2 )
    // a Version Negotiation after the Retry is ignored too (§6.2)
    : ( Vec i ) vers ( vec_new [i] )
    ( vec_push [i] vers 2 )
    : ( Vec u ) vn ( vn_for d1 vers )
    ( quic_conn_recv c vn peer 1007 )
    ( label_int `state_after_late_vn` ( quic_conn_state c ) )
    ( vec_free [u] vn ) ( vec_free [i] vers )
    ( vec_free [u] d2 ) ( vec_free [u] retry ) ( vec_free [u] token ) ( vec_free [u] rscid )
    ( vec_free [u] cscid ) ( vec_free [u] odcid ) ( vec_free [u] d1 ) ( vec_free [u] peer )
    ( quic_conn_free c )
    ( quic_tp_free tp )
}

@ run_vn → v {
    : *QuicTp tp ( quic_tp_new )
    = . tp initial_max_data 65536
    = . tp initial_max_streams_bidi 4
    : ( Vec u ) peer ( udp_addr_new )
    // lists version 1: a fake, ignored
    : *QuicConn c1 ( fresh_client tp )
    : ( Vec u ) i1 ( vec_new [u] )
    : i _n1 ( drain c1 1000 i1 )
    : ( Vec i ) v1 ( vec_new [i] )
    ( vec_push [i] v1 1 ) ( vec_push [i] v1 2 )
    : ( Vec u ) vn1 ( vn_for i1 v1 )
    ( quic_conn_recv c1 vn1 peer 1001 )
    ( label_int `vn_with_v1_state` ( quic_conn_state c1 ) )
    ( vec_free [u] vn1 ) ( vec_free [i] v1 ) ( vec_free [u] i1 ) ( quic_conn_free c1 )
    // no version in common: the attempt ends, nothing more is sent
    : *QuicConn c2 ( fresh_client tp )
    : ( Vec u ) i2 ( vec_new [u] )
    : i _n2 ( drain c2 1000 i2 )
    : ( Vec i ) v2 ( vec_new [i] )
    ( vec_push [i] v2 2 ) ( vec_push [i] v2 4278190335 )
    : ( Vec u ) vn2 ( vn_for i2 v2 )
    ( quic_conn_recv c2 vn2 peer 1001 )
    ( label_int `vn_without_v1_state` ( quic_conn_state c2 ) )
    : ( Vec u ) after ( vec_new [u] )
    ( label_int `vn_without_v1_sent_after` ( drain c2 1002 after ) )
    ( vec_free [u] after ) ( vec_free [u] vn2 ) ( vec_free [i] v2 ) ( vec_free [u] i2 ) ( quic_conn_free c2 )
    ( vec_free [u] peer )
    ( quic_tp_free tp )
}

@ main → i {
    ( run_retry )
    ( run_vn )
    ^ 0
}
