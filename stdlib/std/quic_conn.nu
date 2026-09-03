// stdlib/std/quic_conn.nu — one QUIC v1 connection, server role
// (RFC 9000 / 9001 / 9002). Sans-IO: datagrams in with a clock,
// datagrams out, timers as absolute deadlines; the listener
// (`std/quic_server.nu`) owns the socket, the loop and the clock, and the
// application (HTTP/3 in `ext/http3_conn.nu`) talks to streams.
//
//   ( quic_conn_new_server scid odcid peer creds alpn_prefs tp now ) → *QuicConn
//   ( quic_conn_free c )                                 → v
//   ( quic_conn_recv c dgram from now )                  → v        one UDP datagram (coalesced packets)
//   ( quic_conn_send c now )                             → ( Vec u ) OWNED next datagram, empty when nothing to send
//   ( quic_conn_on_timeout c now )                       → v
//   ( quic_conn_next_timeout c )                         → i        absolute ms, 0 = none
//   ( quic_conn_state c )                                → i        0 handshaking · 1 established · 2 closing · 3 draining · 4 closed
//   ( quic_conn_close c app code reason )                → v        start closing (app = 1 for an application error)
//   ( quic_conn_alpn c ) · ( quic_conn_peer c ) · ( quic_conn_cids c )  BORROWED
//
// Streams (ids per RFC 9000 §2.1; the server's own streams are odd):
//
//   ( quic_conn_take_readable c )                        → ( Vec i ) OWNED stream ids with new data / FIN / RESET
//   ( quic_conn_stream_recv c id max )                   → ( Vec u ) OWNED bytes (empty when none)
//   ( quic_conn_stream_fin c id )                        → b        FIN reached and all data read
//   ( quic_conn_stream_reset_err c id )                  → i        RESET_STREAM error code, -1 none
//   ( quic_conn_open_uni c )                             → i        a new server-initiated unidirectional stream, -1 at the peer's limit
//   ( quic_conn_stream_send c id data fin )              → i        bytes accepted (buffered), -1 no such / closed stream
//   ( quic_conn_stream_reset c id err ) · ( quic_conn_stream_stop_sending c id err )
//   ( quic_conn_stream_stop_err c id )                   → i        STOP_SENDING error code from the peer, -1 none
//   ( quic_conn_stream_done c id )                       → v        the application is finished with the stream
//
// Deliberately absent (documented in temp.md / NETWORKING.md): 0-RTT,
// Retry / address-validation tokens, preferred_address, stateless
// reset emission, ECN marking, path migration beyond following a
// validated peer address, and 1-RTT packets that arrive before the
// client's Finished (dropped; the peer's PTO retransmits them).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_packet.nu`
$ `stdlib/std/quic_frame.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_rxbuf.nu`
$ `stdlib/std/quic_tls.nu`
$ `stdlib/std/quic_recovery.nu`

// ── error codes (RFC 9000 §20.1) ─────────────────────────────────
@ quic_err_no_error → i { ^ 0 }

@ quic_err_internal → i { ^ 1 }

@ quic_err_flow_control → i { ^ 3 }

@ quic_err_stream_limit → i { ^ 4 }

@ quic_err_stream_state → i { ^ 5 }

@ quic_err_final_size → i { ^ 6 }

@ quic_err_frame_encoding → i { ^ 7 }

@ quic_err_transport_parameter → i { ^ 8 }

@ quic_err_connection_id_limit → i { ^ 9 }

@ quic_err_application → i { ^ 12 }

// Server credentials, the same inputs `tls_accept*` takes.
: QuicCreds {
    ( Vec u ) cert_chain
    i keytype
    ( Vec u ) ec_priv
    ( Vec u ) rsa_n
    ( Vec u ) rsa_e
    ( Vec u ) rsa_d
    i ml_level
}

@ quic_creds_new ( Vec u ) cert_chain i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d i ml_level → *QuicCreds {
    : *QuicCreds k # *QuicCreds ( nurl_alloc Z QuicCreds )
    = . k cert_chain ( bytes_slice cert_chain 0 ( vec_len [u] cert_chain ) )
    = . k keytype keytype
    = . k ec_priv ( bytes_slice ec_priv 0 ( vec_len [u] ec_priv ) )
    = . k rsa_n ( bytes_slice rsa_n 0 ( vec_len [u] rsa_n ) )
    = . k rsa_e ( bytes_slice rsa_e 0 ( vec_len [u] rsa_e ) )
    = . k rsa_d ( bytes_slice rsa_d 0 ( vec_len [u] rsa_d ) )
    = . k ml_level ml_level
    ^ k
}

@ quic_creds_free * QuicCreds k → v {
    ? == # i k 0 { ^ } {}
    ( vec_free [u] . k cert_chain ) ( vec_free [u] . k ec_priv )
    ( vec_free [u] . k rsa_n ) ( vec_free [u] . k rsa_e ) ( vec_free [u] . k rsa_d )
    ( nurl_free # s k )
}

// ── streams ──────────────────────────────────────────────────────

: QuicStream {
    i id
    * QuicRxBuf rx
    i rx_window
    i rx_max_data
    i rx_fin_off
    i rx_reset_err
    i rx_done
    i readable
    ( Vec u ) tx_buf
    i tx_off
    i tx_fin
    i tx_fin_sent
    i tx_max_data
    i tx_reset_err
    i tx_reset_sent
    i tx_stop_err
    i tx_done
    i app_done
}

@ __qc_stream_is_bidi i id → b { ^ == & id 2 0 }

@ _qc_stream_is_server i id → b { ^ == & id 1 1 }

@ __qc_stream_new i id i rx_window i tx_max → *QuicStream {
    : *QuicStream s # *QuicStream ( nurl_alloc Z QuicStream )
    = . s id id
    // A server-initiated unidirectional stream has no receive side.
    : b has_rx ! & ( _qc_stream_is_server id ) ! ( __qc_stream_is_bidi id )
    = . s rx ? has_rx ( quic_rxbuf_new rx_window ) # *QuicRxBuf 0
    = . s rx_window rx_window
    = . s rx_max_data rx_window
    = . s rx_fin_off -1
    = . s rx_reset_err -1
    = . s rx_done ? has_rx 0 1
    = . s readable 0
    = . s tx_buf ( vec_new [u] )
    = . s tx_off 0
    = . s tx_fin 0
    = . s tx_fin_sent 0
    = . s tx_max_data tx_max
    = . s tx_reset_err -1
    = . s tx_reset_sent 0
    = . s tx_stop_err -1
    // A client-initiated unidirectional stream has no send side.
    : b has_tx | ( _qc_stream_is_server id ) ( __qc_stream_is_bidi id )
    = . s tx_done ? has_tx 0 1
    = . s app_done 0
    ^ s
}

@ __qc_stream_free * QuicStream s → v {
    ( quic_rxbuf_free . s rx )
    ( vec_free [u] . s tx_buf )
    ( nurl_free # s s )
}

// ── the connection ───────────────────────────────────────────────

: QuicConn {
    i state
    i now
    ( Vec u ) scid
    ( Vec u ) dcid
    ( Vec u ) odcid
    ( Vec u ) peer
    ( Vec u ) cids
    ( Vec i ) cid_seqs
    i cid_next_seq
    i cid_extra_issued
    ( Vec u ) peer_cids
    ( Vec i ) peer_cid_seqs
    i peer_cid_retire_prior
    i validated
    i bytes_recv
    i bytes_sent
    * QuicTlsSrv tls
    i tls_state
    * QuicKeys k_rx0
    * QuicKeys k_tx0
    * QuicKeys k_rx1
    * QuicKeys k_tx1
    * QuicKeys k_rx2
    * QuicKeys k_tx2
    * QuicKeys k_rx2_prev
    * QuicKeys k_rx2_next
    i key_phase
    i key_update_pn
    i keys0_dropped
    i keys1_dropped
    i next_pn0
    i next_pn1
    i next_pn2
    i largest_rx0
    i largest_rx1
    i largest_rx2
    i largest_rx_time2
    ( Vec i ) rx_ranges0
    ( Vec i ) rx_ranges1
    ( Vec i ) rx_ranges2
    i ack_needed0
    i ack_needed1
    i ack_needed2
    i ae_since_ack2
    * QuicRecovery rec
    i crypto_sent0
    i crypto_sent1
    i crypto_sent2
    ( Vec u ) crypto_out0
    ( Vec u ) crypto_out1
    ( Vec u ) crypto_out2
    ( Vec u ) retx0
    ( Vec u ) retx1
    ( Vec u ) retx2
    ( Vec u ) ctl2
    * QuicTp local_tp
    * QuicTp peer_tp
    i max_data_local
    i data_recv
    i data_consumed
    i max_data_peer
    i data_sent
    i max_streams_bidi_local
    i max_streams_uni_local
    i peer_bidi_opened
    i peer_uni_opened
    i peer_bidi_closed
    i peer_uni_closed
    i max_streams_bidi_peer
    i max_streams_uni_peer
    i next_local_bidi
    i next_local_uni
    ( Vec i ) streams
    ( Vec i ) readable
    i idle_timeout
    i last_activity
    i handshake_done_sent
    i confirmed
    i close_code
    i close_app
    i close_frame_type
    ( Vec u ) close_reason
    i close_deadline
    i close_sent
    i close_pkts_since
    i max_udp
    i stream_rx_window
    i alpn_ok
}

@ quic_conn_default_idle_ms → i { ^ 30000 }

@ quic_conn_default_stream_window → i { ^ 262144 }

@ quic_conn_default_conn_window → i { ^ 1048576 }

@ quic_conn_default_max_streams_bidi → i { ^ 100 }

@ quic_conn_default_max_streams_uni → i { ^ 3 }

@ __qc_rand i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : b _ok ( vec_resize_zeroed [u] v n )
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    ? & > n 0 == r 0 { ( nurl_panic `quic: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

// The transport parameters this server sends: `tp` is the caller's
// template (limits); the connection IDs are filled in here.
@ quic_conn_new_server ( Vec u ) scid ( Vec u ) odcid ( Vec u ) peer * QuicCreds creds ( Vec u ) alpn_prefs * QuicTp tp i now → *QuicConn {
    : *QuicConn c # *QuicConn ( nurl_alloc Z QuicConn )
    = . c state 0
    = . c now now
    = . c scid ( bytes_slice scid 0 ( vec_len [u] scid ) )
    = . c dcid ( vec_new [u] )
    = . c odcid ( bytes_slice odcid 0 ( vec_len [u] odcid ) )
    = . c peer ( bytes_slice peer 0 ( vec_len [u] peer ) )
    = . c cids ( bytes_slice scid 0 ( vec_len [u] scid ) )
    = . c cid_seqs ( vec_new [i] )
    ( vec_push [i] . c cid_seqs 0 )
    = . c cid_next_seq 1
    = . c cid_extra_issued 0
    = . c peer_cids ( vec_new [u] )
    = . c peer_cid_seqs ( vec_new [i] )
    = . c peer_cid_retire_prior 0
    = . c validated 0
    = . c bytes_recv 0
    = . c bytes_sent 0
    // our transport parameters
    : *QuicTp mine ( quic_tp_new )
    = . mine max_idle_timeout . tp max_idle_timeout
    = . mine max_udp_payload_size . tp max_udp_payload_size
    = . mine initial_max_data . tp initial_max_data
    = . mine initial_max_stream_data_bidi_local . tp initial_max_stream_data_bidi_local
    = . mine initial_max_stream_data_bidi_remote . tp initial_max_stream_data_bidi_remote
    = . mine initial_max_stream_data_uni . tp initial_max_stream_data_uni
    = . mine initial_max_streams_bidi . tp initial_max_streams_bidi
    = . mine initial_max_streams_uni . tp initial_max_streams_uni
    = . mine ack_delay_exponent 3
    = . mine max_ack_delay 25
    = . mine disable_active_migration 1
    = . mine active_connection_id_limit 4
    = . mine has_original_dcid 1
    ( bytes_extend_bytes . mine original_dcid odcid )
    = . mine has_initial_scid 1
    ( bytes_extend_bytes . mine initial_scid scid )
    = . mine has_stateless_reset_token 1
    : ( Vec u ) tok ( __qc_rand 16 )
    ( bytes_extend_bytes . mine stateless_reset_token tok )
    ( vec_free [u] tok )
    = . c local_tp mine
    : ( Vec u ) tpb ( quic_tp_encode mine T )
    = . c tls ( quic_tls_srv_new . creds cert_chain . creds keytype . creds ec_priv . creds rsa_n . creds rsa_e . creds rsa_d . creds ml_level alpn_prefs tpb )
    ( vec_free [u] tpb )
    = . c tls_state 0
    = . c k_rx0 ( quic_initial_keys odcid T )
    = . c k_tx0 ( quic_initial_keys odcid F )
    = . c k_rx1 # *QuicKeys 0
    = . c k_tx1 # *QuicKeys 0
    = . c k_rx2 # *QuicKeys 0
    = . c k_tx2 # *QuicKeys 0
    = . c k_rx2_prev # *QuicKeys 0
    = . c k_rx2_next # *QuicKeys 0
    = . c key_phase 0
    = . c key_update_pn -1
    = . c keys0_dropped 0
    = . c keys1_dropped 0
    = . c next_pn0 0
    = . c next_pn1 0
    = . c next_pn2 0
    = . c largest_rx0 -1
    = . c largest_rx1 -1
    = . c largest_rx2 -1
    = . c largest_rx_time2 0
    = . c rx_ranges0 ( vec_new [i] )
    = . c rx_ranges1 ( vec_new [i] )
    = . c rx_ranges2 ( vec_new [i] )
    = . c ack_needed0 0
    = . c ack_needed1 0
    = . c ack_needed2 0
    = . c ae_since_ack2 0
    = . c rec ( quic_rec_new 1200 )
    = . c crypto_sent0 0
    = . c crypto_sent1 0
    = . c crypto_sent2 0
    = . c crypto_out0 ( vec_new [u] )
    = . c crypto_out1 ( vec_new [u] )
    = . c crypto_out2 ( vec_new [u] )
    = . c retx0 ( vec_new [u] )
    = . c retx1 ( vec_new [u] )
    = . c retx2 ( vec_new [u] )
    = . c ctl2 ( vec_new [u] )
    = . c peer_tp # *QuicTp 0
    = . c max_data_local . tp initial_max_data
    = . c data_recv 0
    = . c data_consumed 0
    = . c max_data_peer 0
    = . c data_sent 0
    = . c max_streams_bidi_local . tp initial_max_streams_bidi
    = . c max_streams_uni_local . tp initial_max_streams_uni
    = . c peer_bidi_opened 0
    = . c peer_uni_opened 0
    = . c peer_bidi_closed 0
    = . c peer_uni_closed 0
    = . c max_streams_bidi_peer 0
    = . c max_streams_uni_peer 0
    = . c next_local_bidi 1
    = . c next_local_uni 3
    = . c streams ( vec_new [i] )
    = . c readable ( vec_new [i] )
    = . c idle_timeout . tp max_idle_timeout
    = . c last_activity now
    = . c handshake_done_sent 0
    = . c confirmed 0
    = . c close_code -1
    = . c close_app 0
    = . c close_frame_type 0
    = . c close_reason ( vec_new [u] )
    = . c close_deadline 0
    = . c close_sent 0
    = . c close_pkts_since 0
    = . c max_udp 1200
    = . c stream_rx_window . tp initial_max_stream_data_bidi_remote
    = . c alpn_ok 0
    ^ c
}

@ quic_conn_free * QuicConn c → v {
    ? == # i c 0 { ^ } {}
    ( vec_free [u] . c scid ) ( vec_free [u] . c dcid ) ( vec_free [u] . c odcid )
    ( vec_free [u] . c peer ) ( vec_free [u] . c cids ) ( vec_free [i] . c cid_seqs )
    ( vec_free [u] . c peer_cids ) ( vec_free [i] . c peer_cid_seqs )
    ( quic_tls_srv_free . c tls )
    ( quic_keys_free . c k_rx0 ) ( quic_keys_free . c k_tx0 )
    ( quic_keys_free . c k_rx1 ) ( quic_keys_free . c k_tx1 )
    ( quic_keys_free . c k_rx2 ) ( quic_keys_free . c k_tx2 )
    ( quic_keys_free . c k_rx2_prev ) ( quic_keys_free . c k_rx2_next )
    ( vec_free [i] . c rx_ranges0 ) ( vec_free [i] . c rx_ranges1 ) ( vec_free [i] . c rx_ranges2 )
    ( quic_rec_free . c rec )
    ( vec_free [u] . c crypto_out0 ) ( vec_free [u] . c crypto_out1 ) ( vec_free [u] . c crypto_out2 )
    ( vec_free [u] . c retx0 ) ( vec_free [u] . c retx1 ) ( vec_free [u] . c retx2 )
    ( vec_free [u] . c ctl2 )
    ( quic_tp_free . c local_tp ) ( quic_tp_free . c peer_tp )
    : ~ i k 0
    ~ < k ( vec_len [i] . c streams ) {
        ( __qc_stream_free # *QuicStream ?? ( vec_get [i] . c streams k ) { T x → x F → 0 } )
        = k + k 1
    }
    ( vec_free [i] . c streams ) ( vec_free [i] . c readable )
    ( vec_free [u] . c close_reason )
    ( nurl_free # s c )
}

@ quic_conn_state * QuicConn c → i { ^ . c state }

@ quic_conn_alpn * QuicConn c → ( Vec u ) { ^ ( quic_tls_srv_alpn . c tls ) }

@ quic_conn_peer * QuicConn c → ( Vec u ) { ^ . c peer }

@ quic_conn_cids * QuicConn c → ( Vec u ) { ^ . c cids }

@ quic_conn_scid_len → i { ^ 8 }

@ __qc_ri ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F → ^ 0 }
}

@ __qc_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// ── closing ──────────────────────────────────────────────────────

// Enter the closing state with a transport (`app` = 0) or application
// (`app` = 1) error. The CONNECTION_CLOSE goes out with the next
// `quic_conn_send`; the state lasts 3 PTOs (§10.2).
@ __qc_fail * QuicConn c i app i code i frame_type → v {
    ? >= . c state 2 { ^ } {}
    = . c state 2
    = . c close_app app
    = . c close_code code
    = . c close_frame_type frame_type
    = . c close_sent 0
    = . c close_pkts_since 0
    = . c close_deadline + . c now * 3 ( quic_rec_pto . c rec )
}

@ quic_conn_close * QuicConn c i app i code ( Vec u ) reason → v {
    ( vec_clear [u] . c close_reason )
    ( bytes_extend_bytes . c close_reason reason )
    ( __qc_fail c app code 0 )
}

// ── streams: lookup / open ───────────────────────────────────────

@ __qc_stream_get * QuicConn c i id → *QuicStream {
    : ~ i k 0
    ~ < k ( vec_len [i] . c streams ) {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        ? == . s id id { ^ s } {}
        = k + k 1
    }
    ^ # *QuicStream 0
}

// The peer's stream `id`: open it (and every lower one of its kind not
// yet seen) unless it is beyond the limit we advertised. Returns the
// stream, or 0 with the connection failed.
@ __qc_peer_stream * QuicConn c i id → *QuicStream {
    : *QuicStream s ( __qc_stream_get c id )
    ? != # i s 0 { ^ s } {}
    : b bidi ( __qc_stream_is_bidi id )
    : i idx >> id 2
    : i limit ? bidi . c max_streams_bidi_local . c max_streams_uni_local
    ? >= idx limit { ( __qc_fail c 0 ( quic_err_stream_limit ) 0 ) ^ # *QuicStream 0 } {}
    // A stream below one already closed and forgotten: nothing to reopen.
    : i opened ? bidi . c peer_bidi_opened . c peer_uni_opened
    ? < idx opened {
        // it was opened and later released — treat as closed: no state
        ^ # *QuicStream 0
    } {}
    : i window ? bidi . . c local_tp initial_max_stream_data_bidi_remote . . c local_tp initial_max_stream_data_uni
    : i tx_max ? bidi ? != # i . c peer_tp 0 . . c peer_tp initial_max_stream_data_bidi_local 0 0
    : ~ i i opened
    ~ <= i idx {
        : i nid | << i 2 & id 3
        : *QuicStream ns ( __qc_stream_new nid window tx_max )
        ( vec_push [i] . c streams # i ns )
        = i + i 1
    }
    ? bidi { = . c peer_bidi_opened + idx 1 } { = . c peer_uni_opened + idx 1 }
    ^ ( __qc_stream_get c id )
}

@ __qc_mark_readable * QuicConn c * QuicStream s → v {
    ? != . s readable 0 { ^ } {}
    = . s readable 1
    ( vec_push [i] . c readable . s id )
}

// Put ids back in front of the readable queue (the listener peeked).
@ _qc_requeue_readable * QuicConn c ( Vec i ) ids → v {
    : ~ i k 0
    ~ < k ( vec_len [i] ids ) {
        : *QuicStream s ( __qc_stream_get c ( __qc_ri ids k ) )
        ? != # i s 0 { ( __qc_mark_readable c s ) } {}
        = k + k 1
    }
}

@ quic_conn_odcid * QuicConn c → ( Vec u ) { ^ . c odcid }

@ quic_conn_take_readable * QuicConn c → ( Vec i ) {
    : ( Vec i ) out . c readable
    = . c readable ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [i] out ) {
        : *QuicStream s ( __qc_stream_get c ( __qc_ri out k ) )
        ? != # i s 0 { = . s readable 0 } {}
        = k + k 1
    }
    ^ out
}

// ── streams: application side ────────────────────────────────────

@ quic_conn_stream_recv * QuicConn c i id i max → ( Vec u ) {
    : *QuicStream s ( __qc_stream_get c id )
    ? | == # i s 0 == # i . s rx 0 { ^ ( vec_new [u] ) } {}
    ? >= . s rx_reset_err 0 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( quic_rxbuf_read . s rx max )
    : i n ( vec_len [u] out )
    ? > n 0 {
        = . c data_consumed + . c data_consumed n
        // stream window: re-advertise when half is used up
        : i consumed ( quic_rxbuf_consumed . s rx )
        ? < - . s rx_max_data consumed / . s rx_window 2 {
            = . s rx_max_data + consumed . s rx_window
            ( quic_rxbuf_set_cap . s rx . s rx_max_data )
            ( quic_push_max_stream_data . c ctl2 id . s rx_max_data )
        } {}
        // connection window likewise
        ? < - . c max_data_local . c data_consumed / . . c local_tp initial_max_data 2 {
            = . c max_data_local + . c data_consumed . . c local_tp initial_max_data
            ( quic_push_max_data . c ctl2 . c max_data_local )
        } {}
    } {}
    ? & >= . s rx_fin_off 0 == ( quic_rxbuf_consumed . s rx ) . s rx_fin_off { = . s rx_done 1 } {}
    ^ out
}

@ quic_conn_stream_fin * QuicConn c i id → b {
    : *QuicStream s ( __qc_stream_get c id )
    ? | == # i s 0 == # i . s rx 0 { ^ F } {}
    ? < . s rx_fin_off 0 { ^ F } {}
    ^ == ( quic_rxbuf_consumed . s rx ) . s rx_fin_off
}

@ quic_conn_stream_reset_err * QuicConn c i id → i {
    : *QuicStream s ( __qc_stream_get c id )
    ? == # i s 0 { ^ -1 } {}
    ^ . s rx_reset_err
}

@ quic_conn_stream_stop_err * QuicConn c i id → i {
    : *QuicStream s ( __qc_stream_get c id )
    ? == # i s 0 { ^ -1 } {}
    ^ . s tx_stop_err
}

@ quic_conn_open_uni * QuicConn c → i {
    : i idx >> . c next_local_uni 2
    ? >= idx . c max_streams_uni_peer { ^ -1 } {}
    : i id . c next_local_uni
    = . c next_local_uni + id 4
    : i tx_max ? != # i . c peer_tp 0 . . c peer_tp initial_max_stream_data_uni 0
    : *QuicStream s ( __qc_stream_new id 0 tx_max )
    ( vec_push [i] . c streams # i s )
    ^ id
}

// Buffer `data` (and a FIN) for sending. Everything is accepted up to
// 4 MB of unsent bytes per stream; flow control applies at send time.
@ quic_conn_stream_send * QuicConn c i id ( Vec u ) data b fin → i {
    : *QuicStream s ( __qc_stream_get c id )
    ? == # i s 0 { ^ -1 } {}
    ? | != . s tx_done 0 != . s tx_fin 0 { ^ -1 } {}
    ? >= . s tx_reset_err 0 { ^ -1 } {}
    : i room - 4194304 ( vec_len [u] . s tx_buf )
    : i n ( vec_len [u] data )
    : i take ? < n room n room
    ? > take 0 {
        : *u p ( vec_data [u] data )
        ( bytes_extend_raw . s tx_buf # s p take )
    } {}
    ? & fin == take n { = . s tx_fin 1 } {}
    ^ take
}

@ quic_conn_stream_reset * QuicConn c i id i err → v {
    : *QuicStream s ( __qc_stream_get c id )
    ? | == # i s 0 != . s tx_done 0 { ^ } {}
    ? >= . s tx_reset_err 0 { ^ } {}
    = . s tx_reset_err err
    = . s tx_reset_sent 0
    ( vec_clear [u] . s tx_buf )
}

@ quic_conn_stream_stop_sending * QuicConn c i id i err → v {
    : *QuicStream s ( __qc_stream_get c id )
    ? | == # i s 0 == # i . s rx 0 { ^ } {}
    ? != . s rx_done 0 { ^ } {}
    ( quic_push_stop_sending . c ctl2 id err )
}

@ quic_conn_stream_done * QuicConn c i id → v {
    : *QuicStream s ( __qc_stream_get c id )
    ? == # i s 0 { ^ } {}
    = . s app_done 1
    ( __qc_stream_gc c )
}

// Release streams both sides are done with; credit the peer's stream
// limit for its streams (MAX_STREAMS keeps `max_streams_*_local` open
// slots ahead of what has been closed).
@ __qc_stream_gc * QuicConn c → v {
    : ( Vec i ) keep ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [i] . c streams ) {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        : b tx_finished | != . s tx_done 0 | & != . s tx_fin_sent 0 == ( vec_len [u] . s tx_buf ) 0 != . s tx_reset_sent 0
        : b rx_finished | != . s rx_done 0 >= . s rx_reset_err 0
        ? & & != . s app_done 0 tx_finished rx_finished {
            ? ! ( _qc_stream_is_server . s id ) {
                ? ( __qc_stream_is_bidi . s id ) {
                    = . c peer_bidi_closed + . c peer_bidi_closed 1
                    : i want + . c peer_bidi_closed . . c local_tp initial_max_streams_bidi
                    ? > want . c max_streams_bidi_local {
                        = . c max_streams_bidi_local want
                        ( quic_push_max_streams . c ctl2 T want )
                    } {}
                } {
                    = . c peer_uni_closed + . c peer_uni_closed 1
                    : i want + . c peer_uni_closed . . c local_tp initial_max_streams_uni
                    ? > want . c max_streams_uni_local {
                        = . c max_streams_uni_local want
                        ( quic_push_max_streams . c ctl2 F want )
                    } {}
                }
            } {}
            ( __qc_stream_free s )
        } { ( vec_push [i] keep # i s ) }
        = k + k 1
    }
    ( vec_free [i] . c streams )
    = . c streams keep
}

// ── receive: packet-number bookkeeping ───────────────────────────

@ __qc_rx_ranges * QuicConn c i space → ( Vec i ) {
    ? == space 0 { ^ . c rx_ranges0 } {}
    ? == space 1 { ^ . c rx_ranges1 } {}
    ^ . c rx_ranges2
}

@ __qc_largest_rx * QuicConn c i space → i {
    ? == space 0 { ^ . c largest_rx0 } {}
    ? == space 1 { ^ . c largest_rx1 } {}
    ^ . c largest_rx2
}

// Is `pn` already in the received set?
@ __qc_rx_seen * QuicConn c i space i pn → b {
    : ( Vec i ) r ( __qc_rx_ranges c space )
    : ~ i k 0
    ~ < k ( vec_len [i] r ) {
        ? & >= pn ( __qc_ri r k ) <= pn ( __qc_ri r + k 1 ) { ^ T } {}
        = k + k 2
    }
    ^ F
}

// Record `pn`; ranges are kept sorted descending [hi, lo] pairs as an
// ACK frame wants them, at most 32 ranges (older ones fall off).
@ __qc_rx_record * QuicConn c i space i pn → v {
    : ( Vec i ) r ( __qc_rx_ranges c space )
    : ( Vec i ) out ( vec_new [i] )
    : ~ b placed F
    : ~ i lo pn
    : ~ i hi pn
    : ~ i k 0
    ~ < k ( vec_len [i] r ) {
        : i rlo ( __qc_ri r k )
        : i rhi ( __qc_ri r + k 1 )
        ? > rlo + hi 1 {
            ( vec_push [i] out rlo ) ( vec_push [i] out rhi )
        } {
            ? < rhi - lo 1 {
                ? ! placed { ( vec_push [i] out lo ) ( vec_push [i] out hi ) = placed T } {}
                ( vec_push [i] out rlo ) ( vec_push [i] out rhi )
            } {
                ? < rlo lo { = lo rlo } {}
                ? > rhi hi { = hi rhi } {}
            }
        }
        = k + k 2
    }
    ? ! placed { ( vec_push [i] out lo ) ( vec_push [i] out hi ) } {}
    ~ > ( vec_len [i] out ) 64 { : ?i _a ( vec_pop [i] out ) : ?i _b ( vec_pop [i] out ) }
    ( vec_free [i] r )
    ? == space 0 { = . c rx_ranges0 out } {}
    ? == space 1 { = . c rx_ranges1 out } {}
    ? == space 2 { = . c rx_ranges2 out } {}
    ? > pn ( __qc_largest_rx c space ) {
        ? == space 0 { = . c largest_rx0 pn } {}
        ? == space 1 { = . c largest_rx1 pn } {}
        ? == space 2 { = . c largest_rx2 pn = . c largest_rx_time2 . c now } {}
    } {}
}

// Build an ACK frame for `space` from the received ranges.
@ __qc_push_ack * QuicConn c i space ( Vec u ) out → v {
    : ( Vec i ) r ( __qc_rx_ranges c space )
    ? == ( vec_len [i] r ) 0 { ^ } {}
    : i largest ( __qc_ri r 1 )
    : i first_lo ( __qc_ri r 0 )
    : ( Vec i ) rest ( vec_new [i] )
    : ~ i prev_lo first_lo
    : ~ i k 2
    ~ < k ( vec_len [i] r ) {
        : i lo ( __qc_ri r k )
        : i hi ( __qc_ri r + k 1 )
        ( vec_push [i] rest - - prev_lo hi 2 )
        ( vec_push [i] rest - hi lo )
        = prev_lo lo
        = k + k 2
    }
    : ~ i delay 0
    ? == space 2 { = delay >> * - . c now . c largest_rx_time2 1000 3 } {}
    ? < delay 0 { = delay 0 } {}
    ( quic_push_ack out largest delay - largest first_lo rest -1 0 0 )
    ( vec_free [i] rest )
}

// ── receive: keys per space ──────────────────────────────────────

@ __qc_install_handshake_keys * QuicConn c → v {
    ? != # i . c k_tx1 0 { ^ } {}
    : i cipher ( quic_tls_srv_cipher . c tls )
    = . c k_tx1 ( quic_keys_derive cipher ( quic_tls_srv_s_hs . c tls ) )
    = . c k_rx1 ( quic_keys_derive cipher ( quic_tls_srv_c_hs . c tls ) )
    = . c k_tx2 ( quic_keys_derive cipher ( quic_tls_srv_s_ap . c tls ) )
    = . c k_rx2 ( quic_keys_derive cipher ( quic_tls_srv_c_ap . c tls ) )
}

// The peer's transport parameters, once the TLS layer has them.
@ __qc_apply_peer_tp * QuicConn c → v {
    ? != # i . c peer_tp 0 { ^ } {}
    : *QuicTp p ( quic_tp_decode ( quic_tls_srv_client_tp . c tls ) T )
    ? == # i p 0 { ( __qc_fail c 0 ( quic_err_transport_parameter ) 0 ) ^ } {}
    // §7.3: initial_source_connection_id must be the SCID of the client's
    // Initial packet — the DCID we send to.
    ? ! ( bytes_eq . p initial_scid . c dcid ) {
        ( quic_tp_free p )
        ( __qc_fail c 0 ( quic_err_transport_parameter ) 0 )
        ^
    } {}
    = . c peer_tp p
    = . c max_data_peer . p initial_max_data
    = . c max_streams_bidi_peer . p initial_max_streams_bidi
    = . c max_streams_uni_peer . p initial_max_streams_uni
    ( quic_rec_set_peer . c rec . p max_ack_delay . p ack_delay_exponent )
    : ~ i idle . . c local_tp max_idle_timeout
    ? > . p max_idle_timeout 0 { ? | == idle 0 < . p max_idle_timeout idle { = idle . p max_idle_timeout } {} } {}
    = . c idle_timeout idle
    : i mu ? < . p max_udp_payload_size 1350 . p max_udp_payload_size 1350
    = . c max_udp mu
    // streams opened before the parameters arrived (none for a server —
    // client data waits for 1-RTT — but keep the invariant)
    : ~ i k 0
    ~ < k ( vec_len [i] . c streams ) {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        ? ( __qc_stream_is_bidi . s id ) { = . s tx_max_data . p initial_max_stream_data_bidi_local } {}
        = k + k 1
    }
}

// Drain the TLS layer's outputs into the CRYPTO queues and react to
// its state changes.
@ __qc_tls_pump * QuicConn c → v {
    : ( Vec u ) o0 ( quic_tls_srv_take_out . c tls 0 )
    ( bytes_extend_bytes . c crypto_out0 o0 ) ( vec_free [u] o0 )
    : ( Vec u ) o1 ( quic_tls_srv_take_out . c tls 1 )
    ( bytes_extend_bytes . c crypto_out1 o1 ) ( vec_free [u] o1 )
    : ( Vec u ) o2 ( quic_tls_srv_take_out . c tls 2 )
    ( bytes_extend_bytes . c crypto_out2 o2 ) ( vec_free [u] o2 )
    : i st ( quic_tls_srv_state . c tls )
    ? & >= st 1 == . c tls_state 0 {
        = . c tls_state 1
        ( __qc_install_handshake_keys c )
        ( __qc_apply_peer_tp c )
    } {}
    ? & >= st 2 < . c tls_state 2 {
        = . c tls_state 2
        // Handshake confirmed (§4.1.2): 1-RTT both ways, HANDSHAKE_DONE,
        // Handshake keys dropped (§4.9.2), extra connection IDs issued.
        = . c state 1
        = . c confirmed 1
        ( quic_rec_set_confirmed . c rec )
        ( __qc_drop_keys c 1 )
        ( quic_rec_new_max_datagram . c rec . c max_udp )
        ( __qc_issue_cids c )
    } {}
}

@ __qc_drop_keys * QuicConn c i space → v {
    ? == space 0 {
        ? != . c keys0_dropped 0 { ^ } {}
        = . c keys0_dropped 1
        ( quic_keys_free . c k_rx0 ) ( quic_keys_free . c k_tx0 )
        = . c k_rx0 # *QuicKeys 0
        = . c k_tx0 # *QuicKeys 0
        ( vec_clear [u] . c crypto_out0 ) ( vec_clear [u] . c retx0 )
        ( quic_rec_discard_space . c rec 0 )
        ^
    } {}
    ? != . c keys1_dropped 0 { ^ } {}
    = . c keys1_dropped 1
    ( quic_keys_free . c k_rx1 ) ( quic_keys_free . c k_tx1 )
    = . c k_rx1 # *QuicKeys 0
    = . c k_tx1 # *QuicKeys 0
    ( vec_clear [u] . c crypto_out1 ) ( vec_clear [u] . c retx1 )
    ( quic_rec_discard_space . c rec 1 )
}

// More connection IDs for the peer (§5.1.1), each with a reset token:
// up to two extra, never more than its active_connection_id_limit allows
// (the initial one counts; the default limit of 2 leaves room for one).
@ __qc_issue_cids * QuicConn c → v {
    : i limit ? != # i . c peer_tp 0 . . c peer_tp active_connection_id_limit 2
    : ~ i want - limit 1
    ? > want 2 { = want 2 } {}
    ~ < . c cid_extra_issued want {
        : ( Vec u ) cid ( __qc_rand 8 )
        : ( Vec u ) tok ( __qc_rand 16 )
        ( quic_push_new_connection_id . c ctl2 . c cid_next_seq 0 cid tok )
        ( bytes_extend_bytes . c cids cid )
        ( vec_push [i] . c cid_seqs . c cid_next_seq )
        = . c cid_next_seq + . c cid_next_seq 1
        = . c cid_extra_issued + . c cid_extra_issued 1
        ( vec_free [u] tok ) ( vec_free [u] cid )
    }
}

// ── receive: frames ──────────────────────────────────────────────

// Returns 0 to continue, 1 when the connection has failed.
@ __qc_on_stream_frame * QuicConn c * QuicFrame f → i {
    : i id . f a
    ? ( _qc_stream_is_server id ) {
        ? ! ( __qc_stream_is_bidi id ) { ( __qc_fail c 0 ( quic_err_stream_state ) . f ftype ) ^ 1 } {}
        ? >= id . c next_local_bidi { ( __qc_fail c 0 ( quic_err_stream_state ) . f ftype ) ^ 1 } {}
    } {}
    : *QuicStream s ? ( _qc_stream_is_server id ) ( __qc_stream_get c id ) ( __qc_peer_stream c id )
    ? == # i s 0 { ^ ? >= . c state 2 1 0 } {}
    ? == # i . s rx 0 { ( __qc_fail c 0 ( quic_err_stream_state ) . f ftype ) ^ 1 } {}
    : i off . f b
    : i len . f c
    : i end + off len
    // §4.1 flow control on the stream, then on the connection
    ? > end . s rx_max_data { ( __qc_fail c 0 ( quic_err_flow_control ) . f ftype ) ^ 1 } {}
    : i prev_high ( quic_rxbuf_highest . s rx )
    ? > end prev_high {
        : i grow - end prev_high
        ? > + . c data_recv grow . c max_data_local { ( __qc_fail c 0 ( quic_err_flow_control ) . f ftype ) ^ 1 } {}
        = . c data_recv + . c data_recv grow
    } {}
    // final size consistency (§4.5)
    ? != . f d 0 {
        ? & >= . s rx_fin_off 0 != . s rx_fin_off end { ( __qc_fail c 0 ( quic_err_final_size ) . f ftype ) ^ 1 } {}
        ? < end prev_high { ( __qc_fail c 0 ( quic_err_final_size ) . f ftype ) ^ 1 } {}
        = . s rx_fin_off end
    } {
        ? & >= . s rx_fin_off 0 > end . s rx_fin_off { ( __qc_fail c 0 ( quic_err_final_size ) . f ftype ) ^ 1 } {}
    }
    ? ! ( quic_rxbuf_add . s rx off . f bytes ) { ( __qc_fail c 0 ( quic_err_flow_control ) . f ftype ) ^ 1 } {}
    ? | > ( quic_rxbuf_avail . s rx ) 0 != . f d 0 { ( __qc_mark_readable c s ) } {}
    ^ 0
}

@ __qc_on_frame * QuicConn c i space * QuicFrame f → i {
    : i ft . f ftype
    ? | == ft 0 == ft 1 { ^ 0 } {}
    ? | == ft 2 == ft 3 {
        ? < ( quic_rec_on_ack . c rec space f . c now ) 0 { ( __qc_fail c 0 10 ft ) ^ 1 } {}
        : ( Vec u ) lost ( quic_rec_take_lost . c rec space )
        ? == space 0 { ( bytes_extend_bytes . c retx0 lost ) } {}
        ? == space 1 { ( bytes_extend_bytes . c retx1 lost ) } {}
        ? == space 2 { ( bytes_extend_bytes . c retx2 lost ) } {}
        ( vec_free [u] lost )
        ^ 0
    } {}
    ? == ft 6 {
        : i rc ( quic_tls_srv_crypto . c tls space . f a . f bytes )
        ? != rc 0 { ( __qc_fail c 0 rc ft ) ^ 1 } {}
        ( __qc_tls_pump c )
        ^ ? >= . c state 2 1 0
    } {}
    ? == ft 7 { ( __qc_fail c 0 10 ft ) ^ 1 } {}
    ? ( quic_frame_is_stream ft ) { ^ ( __qc_on_stream_frame c f ) } {}
    ? == ft 4 {
        : i id . f a
        ? & ( _qc_stream_is_server id ) ! ( __qc_stream_is_bidi id ) { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        ? & ( _qc_stream_is_server id ) >= id . c next_local_bidi { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        : *QuicStream s ? ( _qc_stream_is_server id ) ( __qc_stream_get c id ) ( __qc_peer_stream c id )
        ? == # i s 0 { ^ ? >= . c state 2 1 0 } {}
        ? == # i . s rx 0 { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        : i final . f c
        ? & >= . s rx_fin_off 0 != . s rx_fin_off final { ( __qc_fail c 0 ( quic_err_final_size ) ft ) ^ 1 } {}
        ? < final ( quic_rxbuf_highest . s rx ) { ( __qc_fail c 0 ( quic_err_final_size ) ft ) ^ 1 } {}
        ? > final . s rx_max_data { ( __qc_fail c 0 ( quic_err_flow_control ) ft ) ^ 1 } {}
        : i grow - final ( quic_rxbuf_highest . s rx )
        ? > + . c data_recv grow . c max_data_local { ( __qc_fail c 0 ( quic_err_flow_control ) ft ) ^ 1 } {}
        = . c data_recv + . c data_recv grow
        = . s rx_fin_off final
        ? < . s rx_reset_err 0 { = . s rx_reset_err . f b } {}
        ( __qc_mark_readable c s )
        ^ 0
    } {}
    ? == ft 5 {
        : i id . f a
        // receive-only for us: the peer's unidirectional streams
        ? & ! ( _qc_stream_is_server id ) ! ( __qc_stream_is_bidi id ) { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        ? & ( _qc_stream_is_server id ) >= id ? ( __qc_stream_is_bidi id ) . c next_local_bidi . c next_local_uni { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        : *QuicStream s ? ( _qc_stream_is_server id ) ( __qc_stream_get c id ) ( __qc_peer_stream c id )
        ? == # i s 0 { ^ ? >= . c state 2 1 0 } {}
        ? < . s tx_stop_err 0 {
            = . s tx_stop_err . f b
            ? < . s tx_reset_err 0 { = . s tx_reset_err . f b = . s tx_reset_sent 0 ( vec_clear [u] . s tx_buf ) } {}
            ( __qc_mark_readable c s )
        } {}
        ^ 0
    } {}
    ? == ft 16 { ? > . f a . c max_data_peer { = . c max_data_peer . f a } {} ^ 0 } {}
    ? == ft 17 {
        : i id . f a
        ? & ! ( _qc_stream_is_server id ) ! ( __qc_stream_is_bidi id ) { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        ? & ( _qc_stream_is_server id ) >= id ? ( __qc_stream_is_bidi id ) . c next_local_bidi . c next_local_uni { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        : *QuicStream s ? ( _qc_stream_is_server id ) ( __qc_stream_get c id ) ( __qc_peer_stream c id )
        ? == # i s 0 { ^ ? >= . c state 2 1 0 } {}
        ? > . f b . s tx_max_data { = . s tx_max_data . f b } {}
        ^ 0
    } {}
    ? | == ft 18 == ft 19 {
        ? > . f a 1152921504606846976 { ( __qc_fail c 0 ( quic_err_frame_encoding ) ft ) ^ 1 } {}
        ? == ft 18 { ? > . f a . c max_streams_bidi_peer { = . c max_streams_bidi_peer . f a } {} }
        { ? > . f a . c max_streams_uni_peer { = . c max_streams_uni_peer . f a } {} }
        ^ 0
    } {}
    ? == ft 20 { ^ 0 } {}
    ? == ft 21 {
        : i id . f a
        ? & ! ( _qc_stream_is_server id ) ! ( __qc_stream_is_bidi id ) { ( __qc_fail c 0 ( quic_err_stream_state ) ft ) ^ 1 } {}
        ^ 0
    } {}
    ? | == ft 22 == ft 23 {
        ? > . f a 1152921504606846976 { ( __qc_fail c 0 ( quic_err_frame_encoding ) ft ) ^ 1 } {}
        ^ 0
    } {}
    ? == ft 24 {
        // the peer chose a zero-length connection id: it may not then send us more
        ? == ( vec_len [u] . c dcid ) 0 { ( __qc_fail c 0 10 ft ) ^ 1 } {}
        : i seq . f a
        : i rpt . f b
        : i cl . f c
        : ( Vec u ) cid ( bytes_slice . f bytes 0 cl )
        // known sequence number: must repeat the same id
        : ~ i k 0
        : ~ b known F
        ~ < k ( vec_len [i] . c peer_cid_seqs ) {
            ? == ( __qc_ri . c peer_cid_seqs k ) seq { = known T } {}
            = k + k 1
        }
        ? ! known {
            ( vec_push [i] . c peer_cid_seqs seq )
            ( bytes_extend_bytes . c peer_cids cid )
        } {}
        ( vec_free [u] cid )
        // retire what the peer asks us to
        ? > rpt . c peer_cid_retire_prior {
            : ~ i r . c peer_cid_retire_prior
            ~ < r rpt { ( quic_push_retire_connection_id . c ctl2 r ) = r + r 1 }
            = . c peer_cid_retire_prior rpt
        } {}
        : ~ i active 0
        = k 0
        ~ < k ( vec_len [i] . c peer_cid_seqs ) {
            ? >= ( __qc_ri . c peer_cid_seqs k ) . c peer_cid_retire_prior { = active + active 1 } {}
            = k + k 1
        }
        ? > active . . c local_tp active_connection_id_limit { ( __qc_fail c 0 ( quic_err_connection_id_limit ) ft ) ^ 1 } {}
        ^ 0
    } {}
    ? == ft 25 {
        : i seq . f a
        ? >= seq . c cid_next_seq { ( __qc_fail c 0 10 ft ) ^ 1 } {}
        // retiring the id this very packet arrived on is a violation
        : ~ i k 0
        ~ < k ( vec_len [i] . c cid_seqs ) {
            ? == ( __qc_ri . c cid_seqs k ) seq {
                : ( Vec u ) that ( bytes_slice . c cids * k 8 + * k 8 8 )
                : b same ( bytes_eq that . c scid )
                ( vec_free [u] that )
                ? same { ( __qc_fail c 0 10 ft ) ^ 1 } {}
                : ?i _r ( vec_remove [i] . c cid_seqs k )
                : ( Vec u ) rest ( bytes_slice . c cids + * k 8 8 ( vec_len [u] . c cids ) )
                : b _t ( vec_set_len [u] . c cids * k 8 )
                ( bytes_extend_bytes . c cids rest )
                ( vec_free [u] rest )
                = . c cid_extra_issued - . c cid_extra_issued 1
                ( __qc_issue_cids c )
                ^ 0
            } {}
            = k + k 1
        }
        ^ 0
    } {}
    ? == ft 26 { ( quic_push_path_response . c ctl2 . f bytes ) ^ 0 } {}
    ? == ft 27 { ^ 0 } {}
    ? | == ft 28 == ft 29 {
        // the peer is closing: drain (§10.2.2)
        ? < . c state 3 {
            = . c state 3
            = . c close_deadline + . c now * 3 ( quic_rec_pto . c rec )
        } {}
        ^ 1
    } {}
    ? == ft 30 { ( __qc_fail c 0 10 ft ) ^ 1 } {}
    ( __qc_fail c 0 ( quic_err_frame_encoding ) ft )
    ^ 1
}

// ── receive: packets ─────────────────────────────────────────────

@ __qc_rx_keys * QuicConn c i space → *QuicKeys {
    ? == space 0 { ^ . c k_rx0 } {}
    ? == space 1 { ^ . c k_rx1 } {}
    ^ . c k_rx2
}

// Does this packet's DCID name us? Initial packets may still carry the
// client's original DCID (it learns ours from the ServerHello packet).
@ __qc_is_ours * QuicConn c ( Vec u ) pkt * QuicHdr h → b {
    : i dl . h dcid_len
    : ( Vec u ) d ( quic_hdr_dcid h pkt )
    ? & == . h ptype 0 ( bytes_eq d . c odcid ) { ( vec_free [u] d ) ^ T } {}
    ? != dl 8 { ( vec_free [u] d ) ^ F } {}
    : ~ i k 0
    : ~ b ok F
    ~ & ! ok < + k 8 + ( vec_len [u] . c cids ) 1 {
        : ( Vec u ) cid ( bytes_slice . c cids k + k 8 )
        ? ( bytes_eq cid d ) { = ok T } {}
        ( vec_free [u] cid )
        = k + k 8
    }
    ( vec_free [u] d )
    ^ ok
}

// One packet out of a datagram. Returns the offset after it, or -1 to
// stop processing the datagram.
@ __qc_recv_packet * QuicConn c ( Vec u ) dgram i off → i {
    : *QuicHdr h ( quic_hdr_parse dgram off 8 )
    ? == # i h 0 { ^ -1 } {}
    : i ptype . h ptype
    : i end . h end
    ? == ptype 5 { ( quic_hdr_free h ) ^ -1 } {}
    ? & != ptype 4 != . h version 1 { ( quic_hdr_free h ) ^ -1 } {}
    ? ! ( __qc_is_ours c dgram h ) { ( quic_hdr_free h ) ^ end } {}
    ? | == ptype 1 == ptype 3 { ( quic_hdr_free h ) ^ end } {}
    : i space ? == ptype 0 0 ? == ptype 2 1 2
    // 1-RTT before the client's Finished: dropped (see the header).
    ? & == space 2 < . c tls_state 2 { ( quic_hdr_free h ) ^ end } {}
    : *QuicKeys keys ( __qc_rx_keys c space )
    ? == # i keys 0 { ( quic_hdr_free h ) ^ end } {}
    : ( Vec u ) pkt ( bytes_slice dgram off end )
    : i pn_off - . h pn_off off
    : i pn_len ( quic_hp_remove keys pkt pn_off )
    ? < pn_len 0 { ( vec_free [u] pkt ) ( quic_hdr_free h ) ^ end } {}
    : i b0 ( __qc_bget pkt 0 )
    : i pn ( quic_pn_decode ( quic_pn_read pkt pn_off pn_len ) pn_len ( __qc_largest_rx c space ) )
    : ( Vec u ) hdr ( bytes_slice pkt 0 + pn_off pn_len )
    : ( Vec u ) body ( bytes_slice pkt + pn_off pn_len ( vec_len [u] pkt ) )
    : ~ ( Vec u ) payload ( vec_new [u] )
    : ~ b opened F
    : ~ b phase_flip F
    ? == space 2 {
        : i phase ? != & b0 4 0 1 0
        ? == phase . c key_phase {
            ?? ( quic_open keys pn hdr body ) { T p → { ( vec_free [u] payload ) = payload p = opened T } F → {} }
            // an old-phase packet after an update
            ? & ! opened != # i . c k_rx2_prev 0 {
                ?? ( quic_open . c k_rx2_prev pn hdr body ) { T p → { ( vec_free [u] payload ) = payload p = opened T } F → {} }
            } {}
        } {
            ? == # i . c k_rx2_next 0 { = . c k_rx2_next ( quic_keys_update . c k_rx2 ) } {}
            ?? ( quic_open . c k_rx2_next pn hdr body ) { T p → { ( vec_free [u] payload ) = payload p = opened T = phase_flip T } F → {} }
        }
    } {
        ?? ( quic_open keys pn hdr body ) { T p → { ( vec_free [u] payload ) = payload p = opened T } F → {} }
    }
    ( vec_free [u] body ) ( vec_free [u] hdr ) ( vec_free [u] pkt ) ( quic_hdr_free h )
    ? ! opened { ( vec_free [u] payload ) ^ end } {}
    // reserved bits (§17.2 / §17.3.1), only meaningful once authenticated
    ? != & b0 12 0 { ( vec_free [u] payload ) ( __qc_fail c 0 10 0 ) ^ -1 } {}
    ? ( __qc_rx_seen c space pn ) { ( vec_free [u] payload ) ^ end } {}
    ? phase_flip {
        // key update (§6): the peer's new keys are good; rotate ours too
        ( quic_keys_free . c k_rx2_prev )
        = . c k_rx2_prev . c k_rx2
        = . c k_rx2 . c k_rx2_next
        = . c k_rx2_next # *QuicKeys 0
        : *QuicKeys ntx ( quic_keys_update . c k_tx2 )
        ( quic_keys_free . c k_tx2 )
        = . c k_tx2 ntx
        = . c key_phase ? == . c key_phase 0 1 0
        = . c key_update_pn pn
    } {}
    ( __qc_rx_record c space pn )
    = . c last_activity . c now
    // a Handshake packet proves the address (§8.1) and ends Initial (§4.9.1)
    ? == space 1 {
        = . c validated 1
        ( __qc_drop_keys c 0 )
    } {}
    ? == ( vec_len [u] payload ) 0 { ( vec_free [u] payload ) ( __qc_fail c 0 10 0 ) ^ -1 } {}
    : ~ i p 0
    : ~ i ack_eliciting 0
    : ~ i stop 0
    ~ & == stop 0 < p ( vec_len [u] payload ) {
        : *QuicFrame f ( quic_frame_parse payload p )
        ? == # i f 0 {
            : i ft ( quic_varint_read payload p )
            ( __qc_fail c 0 ( quic_err_frame_encoding ) ? < ft 0 0 ft )
            = stop 1
        } {
            ? ! ( quic_frame_allowed . f ftype ptype ) {
                ( __qc_fail c 0 10 . f ftype )
                = stop 1
            } {
                ? ( quic_frame_is_ack_eliciting . f ftype ) { = ack_eliciting 1 } {}
                = p . f next
                ? != ( __qc_on_frame c space f ) 0 { = stop 1 } {}
            }
            ( quic_frame_free f )
        }
    }
    ( vec_free [u] payload )
    ? != ack_eliciting 0 {
        ? == space 0 { = . c ack_needed0 1 } {}
        ? == space 1 { = . c ack_needed1 1 } {}
        ? == space 2 {
            = . c ae_since_ack2 + . c ae_since_ack2 1
            ? >= . c ae_since_ack2 2 { = . c ack_needed2 1 } {}
            ? == . c ack_needed2 0 { = . c ack_needed2 2 } {}
        } {}
    } {}
    ? != stop 0 { ^ -1 } {}
    ^ end
}

@ quic_conn_recv * QuicConn c ( Vec u ) dgram ( Vec u ) from i now → v {
    = . c now now
    ? >= . c state 3 {
        // draining / closed: nothing is processed
        ^
    } {}
    = . c bytes_recv + . c bytes_recv ( vec_len [u] dgram )
    // Before the address is validated only the original path counts.
    ? & != . c validated 0 ! ( bytes_eq from . c peer ) {
        // migration to a new address: follow it (no active migration
        // is advertised, so a real client never does this; a NAT
        // rebinding does)
        ( vec_clear [u] . c peer )
        ( bytes_extend_bytes . c peer from )
    } {}
    // first Initial: learn the peer's SCID
    ? == ( vec_len [u] . c dcid ) 0 {
        : *QuicHdr h ( quic_hdr_parse dgram 0 8 )
        ? != # i h 0 {
            ? == . h ptype 0 {
                : ( Vec u ) sc ( quic_hdr_scid h dgram )
                ( bytes_extend_bytes . c dcid sc )
                ( vec_free [u] sc )
            } {}
            ( quic_hdr_free h )
        } {}
    } {}
    : ~ i off 0
    ~ & >= off 0 < off ( vec_len [u] dgram ) {
        = off ( __qc_recv_packet c dgram off )
    }
    ? == . c state 2 {
        // a packet arrived while closing: repeat the close, rate-limited
        = . c close_pkts_since + . c close_pkts_since 1
        ? >= . c close_pkts_since 3 { = . c close_sent 0 = . c close_pkts_since 0 } {}
    } {}
}

// ── send ─────────────────────────────────────────────────────────

@ __qc_tx_keys * QuicConn c i space → *QuicKeys {
    ? == space 0 { ^ . c k_tx0 } {}
    ? == space 1 { ^ . c k_tx1 } {}
    ^ . c k_tx2
}

@ __qc_next_pn * QuicConn c i space → i {
    ? == space 0 { ^ . c next_pn0 } {}
    ? == space 1 { ^ . c next_pn1 } {}
    ^ . c next_pn2
}

@ __qc_bump_pn * QuicConn c i space → v {
    ? == space 0 { = . c next_pn0 + . c next_pn0 1 ^ } {}
    ? == space 1 { = . c next_pn1 + . c next_pn1 1 ^ } {}
    = . c next_pn2 + . c next_pn2 1
}

@ __qc_crypto_out * QuicConn c i space → ( Vec u ) {
    ? == space 0 { ^ . c crypto_out0 } {}
    ? == space 1 { ^ . c crypto_out1 } {}
    ^ . c crypto_out2
}

@ __qc_crypto_sent * QuicConn c i space → i {
    ? == space 0 { ^ . c crypto_sent0 } {}
    ? == space 1 { ^ . c crypto_sent1 } {}
    ^ . c crypto_sent2
}

@ __qc_retx * QuicConn c i space → ( Vec u ) {
    ? == space 0 { ^ . c retx0 } {}
    ? == space 1 { ^ . c retx1 } {}
    ^ . c retx2
}

// Move whole frames from `src` into `dst` while they fit in `room`.
// Frames were built by this endpoint, so they parse; a frame that does
// not fit stays for the next packet.
@ __qc_move_frames ( Vec u ) src ( Vec u ) dst i room → i {
    : ~ i used 0
    : ~ i p 0
    ~ < p ( vec_len [u] src ) {
        : *QuicFrame f ( quic_frame_parse src p )
        ? == # i f 0 { : b _t ( vec_set_len [u] src p ) = p ( vec_len [u] src ) } {
            : i fl - . f next p
            ? > fl - room used { ( quic_frame_free f ) = p ( vec_len [u] src ) } {
                : ( Vec u ) piece ( bytes_slice src p . f next )
                ( bytes_extend_bytes dst piece )
                ( vec_free [u] piece )
                = used + used fl
                = p . f next
                ( quic_frame_free f )
            }
        }
    }
    ? > used 0 {
        : ( Vec u ) rest ( bytes_slice src used ( vec_len [u] src ) )
        ( vec_clear [u] src )
        ( bytes_extend_bytes src rest )
        ( vec_free [u] rest )
    } {}
    ^ used
}

// Frames for one packet in `space`. `retx` receives the retransmittable
// frames (everything but ACK / PADDING / CONNECTION_CLOSE); returns
// 1 when the packet is ack-eliciting.

// Append the reserved ACK when it is due or the packet has other frames;
// returns the packet's ack-eliciting flag unchanged.
@ __qc_finish_ack * QuicConn c i space ( Vec u ) out ( Vec u ) ackbuf b due i ae → i {
    ? & > ( vec_len [u] ackbuf ) 0 | due > ( vec_len [u] out ) 0 {
        ( bytes_extend_bytes out ackbuf )
        ? == space 0 { = . c ack_needed0 0 } {}
        ? == space 1 { = . c ack_needed1 0 } {}
        ? == space 2 { = . c ack_needed2 0 = . c ae_since_ack2 0 } {}
    } {}
    ( vec_free [u] ackbuf )
    ^ ae
}

@ __qc_build_payload * QuicConn c i space i room ( Vec u ) out ( Vec u ) retx → i {
    : ~ i ae 0
    : ~ i left room
    // CONNECTION_CLOSE, alone (§10.2.3)
    ? == . c state 2 {
        ? == . c close_sent 0 {
            ? != . c close_app 0 {
                ? == space 2 { ( quic_push_application_close out . c close_code . c close_reason ) }
                { : ( Vec u ) e ( vec_new [u] ) ( quic_push_connection_close out ( quic_err_application ) 0 e ) ( vec_free [u] e ) }
            } { ( quic_push_connection_close out . c close_code . c close_frame_type . c close_reason ) }
        } {}
        ^ 0
    } {}
    // ACK — built first so its size is reserved; it goes into the packet
    // when it is due (immediately in Initial/Handshake, after two
    // ack-eliciting packets or max_ack_delay in 1-RTT) or whenever this
    // packet carries anything else (§13.2.1: a pending ACK rides along
    // with any packet sent, delaying only when there is nothing to send).
    : i need ? == space 0 . c ack_needed0 ? == space 1 . c ack_needed1 . c ack_needed2
    : ( Vec u ) ackbuf ( vec_new [u] )
    : ~ b ack_due F
    ? != need 0 {
        ( __qc_push_ack c space ackbuf )
        = ack_due | != space 2 | == need 1 >= . c now + . c largest_rx_time2 25
        = left - left ( vec_len [u] ackbuf )
    } {}
    // retransmissions first, then probes
    : ( Vec u ) rq ( __qc_retx c space )
    ? > ( vec_len [u] rq ) 0 {
        : ( Vec u ) piece ( vec_new [u] )
        : i moved ( __qc_move_frames rq piece left )
        ? > moved 0 { ( bytes_extend_bytes out piece ) ( bytes_extend_bytes retx piece ) = ae 1 = left - left moved } {}
        ( vec_free [u] piece )
    } {}
    // CRYPTO
    : ( Vec u ) co ( __qc_crypto_out c space )
    ? & > ( vec_len [u] co ) 0 > left 12 {
        : i sent ( __qc_crypto_sent c space )
        : i overhead + 1 + ( quic_varint_size sent ) 4
        : i cap - left overhead
        : i n ? < ( vec_len [u] co ) cap ( vec_len [u] co ) cap
        ? > n 0 {
            : ( Vec u ) chunk ( bytes_slice co 0 n )
            : ( Vec u ) fr ( vec_new [u] )
            ( quic_push_crypto fr sent chunk )
            ( bytes_extend_bytes out fr ) ( bytes_extend_bytes retx fr )
            = left - left ( vec_len [u] fr )
            = ae 1
            : ( Vec u ) rest ( bytes_slice co n ( vec_len [u] co ) )
            ( vec_clear [u] co ) ( bytes_extend_bytes co rest )
            ( vec_free [u] rest ) ( vec_free [u] fr ) ( vec_free [u] chunk )
            ? == space 0 { = . c crypto_sent0 + sent n } {}
            ? == space 1 { = . c crypto_sent1 + sent n } {}
            ? == space 2 { = . c crypto_sent2 + sent n } {}
        } {}
    } {}
    ? != space 2 { ^ ( __qc_finish_ack c space out ackbuf ack_due ae ) } {}
    // HANDSHAKE_DONE once
    ? & != . c confirmed 0 == . c handshake_done_sent 0 {
        ? > left 1 {
            ( quic_push_handshake_done out ) ( quic_push_handshake_done retx )
            = . c handshake_done_sent 1
            = left - left 1
            = ae 1
        } {}
    } {}
    // control frames
    ? > ( vec_len [u] . c ctl2 ) 0 {
        : ( Vec u ) piece ( vec_new [u] )
        : i moved ( __qc_move_frames . c ctl2 piece left )
        ? > moved 0 { ( bytes_extend_bytes out piece ) ( bytes_extend_bytes retx piece ) = ae 1 = left - left moved } {}
        ( vec_free [u] piece )
    } {}
    // RESET_STREAM for streams asked to stop / reset by the application
    : ~ i k 0
    ~ & < k ( vec_len [i] . c streams ) > left 16 {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        ? & >= . s tx_reset_err 0 == . s tx_reset_sent 0 {
            ( quic_push_reset_stream out . s id . s tx_reset_err . s tx_off )
            ( quic_push_reset_stream retx . s id . s tx_reset_err . s tx_off )
            = . s tx_reset_sent 1
            = . s tx_done 1
            = left - room ( vec_len [u] out )
            = ae 1
        } {}
        = k + k 1
    }
    // STREAM data, round-robin, under both flow-control limits and cwnd
    ? ! ( quic_rec_can_send . c rec room ) { ^ ( __qc_finish_ack c space out ackbuf ack_due ae ) } {}
    = k 0
    ~ & < k ( vec_len [i] . c streams ) > left 8 {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        : i pending ( vec_len [u] . s tx_buf )
        : b want_fin & != . s tx_fin 0 == . s tx_fin_sent 0
        ? & == . s tx_done 0 | > pending 0 want_fin {
            : i win_s - . s tx_max_data . s tx_off
            : i win_c - . c max_data_peer . c data_sent
            : ~ i allow pending
            ? < win_s allow { = allow win_s } {}
            ? < win_c allow { = allow win_c } {}
            ? < allow 0 { = allow 0 } {}
            // the frame overhead computed for the largest candidate is an
            // upper bound for any smaller one (varints only shrink)
            : i overhead ( quic_stream_frame_overhead . s id . s tx_off allow )
            ? > + overhead allow left { = allow - left overhead } {}
            ? < allow 0 { = allow 0 } {}
            ? > allow pending { = allow pending } {}
            : b fin_now & want_fin == allow pending
            ? | > allow 0 fin_now {
                : ( Vec u ) chunk ( bytes_slice . s tx_buf 0 allow )
                : ( Vec u ) fr ( vec_new [u] )
                ( quic_push_stream fr . s id . s tx_off chunk fin_now )
                ? <= ( vec_len [u] fr ) left {
                    ( bytes_extend_bytes out fr ) ( bytes_extend_bytes retx fr )
                    = left - left ( vec_len [u] fr )
                    = ae 1
                    : ( Vec u ) rest ( bytes_slice . s tx_buf allow pending )
                    ( vec_clear [u] . s tx_buf ) ( bytes_extend_bytes . s tx_buf rest ) ( vec_free [u] rest )
                    = . s tx_off + . s tx_off allow
                    = . c data_sent + . c data_sent allow
                    ? fin_now { = . s tx_fin_sent 1 = . s tx_done 1 } {}
                } {}
                ( vec_free [u] fr ) ( vec_free [u] chunk )
            } {
                // blocked by flow control: say so once per limit
                ? & > pending 0 <= win_s 0 { ( quic_push_stream_data_blocked out . s id . s tx_max_data ) = left - room ( vec_len [u] out ) = ae 1 } {}
            }
        } {}
        = k + k 1
    }
    ^ ( __qc_finish_ack c space out ackbuf ack_due ae )
}

// Is there anything to send in `space`?
@ __qc_space_wants_send * QuicConn c i space → b {
    ? == # i ( __qc_tx_keys c space ) 0 { ^ F } {}
    ? == . c state 2 { ^ == . c close_sent 0 } {}
    : i need ? == space 0 . c ack_needed0 ? == space 1 . c ack_needed1 . c ack_needed2
    ? & != need 0 | != space 2 | == need 1 >= . c now + . c largest_rx_time2 25 { ^ T } {}
    ? > ( vec_len [u] ( __qc_retx c space ) ) 0 { ^ T } {}
    ? > ( vec_len [u] ( __qc_crypto_out c space ) ) 0 { ^ T } {}
    ? != space 2 { ^ F } {}
    ? & != . c confirmed 0 == . c handshake_done_sent 0 { ^ T } {}
    ? > ( vec_len [u] . c ctl2 ) 0 { ^ T } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . c streams ) {
        : *QuicStream s # *QuicStream ( __qc_ri . c streams k )
        ? & >= . s tx_reset_err 0 == . s tx_reset_sent 0 { ^ T } {}
        ? & == . s tx_done 0 | > ( vec_len [u] . s tx_buf ) 0 & != . s tx_fin 0 == . s tx_fin_sent 0 {
            ? & > ( vec_len [u] . s tx_buf ) 0 | <= - . s tx_max_data . s tx_off 0 <= - . c max_data_peer . c data_sent 0 {} { ^ T }
        } {}
        = k + k 1
    }
    ^ F
}

@ quic_conn_send * QuicConn c i now → ( Vec u ) {
    = . c now now
    : ( Vec u ) dgram ( vec_new [u] )
    ? >= . c state 3 { ^ dgram } {}
    // amplification limit before the address is validated (§8.1)
    : ~ i budget . c max_udp
    ? == . c validated 0 {
        : i allowed - * 3 . c bytes_recv . c bytes_sent
        ? < allowed budget { = budget allowed } {}
        ? < budget 40 { ^ dgram } {}
    } {}
    : i probe ( quic_rec_take_probe . c rec )
    ? >= probe 0 {
        : ( Vec u ) pf ( quic_rec_probe_frames . c rec probe )
        : ( Vec u ) rq ( __qc_retx c probe )
        ? > ( vec_len [u] pf ) 0 { ( bytes_extend_bytes rq pf ) } { ( quic_push_ping rq ) }
        ( vec_free [u] pf )
    } {}
    // Plaintext payloads per space first, so the datagram can be padded
    // as a whole; then seal in order.
    : ( Vec u ) pay0 ( vec_new [u] )
    : ( Vec u ) pay1 ( vec_new [u] )
    : ( Vec u ) pay2 ( vec_new [u] )
    : ( Vec u ) rt0 ( vec_new [u] )
    : ( Vec u ) rt1 ( vec_new [u] )
    : ( Vec u ) rt2 ( vec_new [u] )
    : ~ i ae0 0
    : ~ i ae1 0
    : ~ i ae2 0
    : ~ i used 0
    // per-space header cost: long = 1+4+1+8+1+dcid+len(2)+pn(4 at most) + 16 tag
    : i hdr_long + + + + + 1 4 1 8 1 + ( vec_len [u] . c dcid ) + 2 4
    : i hdr_short + + 1 ( vec_len [u] . c dcid ) 4
    : ~ i has0 0
    : ~ i has1 0
    : ~ i has2 0
    ? & ( __qc_space_wants_send c 0 ) == . c keys0_dropped 0 {
        : i room - - budget used + hdr_long 16
        ? > room 0 { = ae0 ( __qc_build_payload c 0 room pay0 rt0 ) } {}
        ? | > ( vec_len [u] pay0 ) 0 == . c close_sent 0 { = has0 1 = used + used + + hdr_long 16 ( vec_len [u] pay0 ) } {}
    } {}
    ? & ( __qc_space_wants_send c 1 ) == . c keys1_dropped 0 {
        : i room - - budget used + hdr_long 16
        ? > room 0 { = ae1 ( __qc_build_payload c 1 room pay1 rt1 ) } {}
        ? > ( vec_len [u] pay1 ) 0 { = has1 1 = used + used + + hdr_long 16 ( vec_len [u] pay1 ) } {}
    } {}
    ? & ( __qc_space_wants_send c 2 ) != # i . c k_tx2 0 {
        ? >= . c tls_state 2 {
            : i room - - budget used + hdr_short 16
            ? > room 0 { = ae2 ( __qc_build_payload c 2 room pay2 rt2 ) } {}
            ? > ( vec_len [u] pay2 ) 0 { = has2 1 = used + used + + hdr_short 16 ( vec_len [u] pay2 ) } {}
        } {}
    } {}
    ? == . c state 2 { ? | | != has0 0 != has1 0 != has2 0 { = . c close_sent 1 } {} } {}
    ? & & == has0 0 == has1 0 == has2 0 {
        ( vec_free [u] pay0 ) ( vec_free [u] pay1 ) ( vec_free [u] pay2 )
        ( vec_free [u] rt0 ) ( vec_free [u] rt1 ) ( vec_free [u] rt2 )
        ^ dgram
    } {}
    // A datagram carrying an ack-eliciting Initial is padded to 1200 (§14.1).
    ? & != has0 0 != ae0 0 {
        ? < used 1200 {
            : i pad - 1200 used
            ? != has2 0 { ( quic_push_padding pay2 pad ) } { ? != has1 0 { ( quic_push_padding pay1 pad ) } { ( quic_push_padding pay0 pad ) } }
            = used 1200
        } {}
    } {}
    : ( Vec u ) empty ( vec_new [u] )
    ? != has0 0 {
        : i pn . c next_pn0
        : i pn_len 4
        : i length + + pn_len ( vec_len [u] pay0 ) 16
        : ( Vec u ) hdr ( quic_long_hdr_build 0 . c dcid . c scid empty length pn pn_len )
        : ( Vec u ) pkt ( quic_packet_protect . c k_tx0 hdr pn pn_len pay0 )
        ( bytes_extend_bytes dgram pkt )
        ( quic_rec_on_sent . c rec 0 pn now ( vec_len [u] pkt ) ae0 rt0 )
        ( __qc_bump_pn c 0 )
        ( vec_free [u] pkt ) ( vec_free [u] hdr )
    } {}
    ? != has1 0 {
        : i pn . c next_pn1
        : i pn_len 4
        : i length + + pn_len ( vec_len [u] pay1 ) 16
        : ( Vec u ) hdr ( quic_long_hdr_build 2 . c dcid . c scid empty length pn pn_len )
        : ( Vec u ) pkt ( quic_packet_protect . c k_tx1 hdr pn pn_len pay1 )
        ( bytes_extend_bytes dgram pkt )
        ( quic_rec_on_sent . c rec 1 pn now ( vec_len [u] pkt ) ae1 rt1 )
        ( __qc_bump_pn c 1 )
        ( vec_free [u] pkt ) ( vec_free [u] hdr )
    } {}
    ? != has2 0 {
        : i pn . c next_pn2
        : i pn_len 4
        : ( Vec u ) hdr ( quic_short_hdr_build . c dcid . c key_phase pn pn_len )
        : ( Vec u ) pkt ( quic_packet_protect . c k_tx2 hdr pn pn_len pay2 )
        ( bytes_extend_bytes dgram pkt )
        ( quic_rec_on_sent . c rec 2 pn now ( vec_len [u] pkt ) ae2 rt2 )
        ( __qc_bump_pn c 2 )
        ( vec_free [u] pkt ) ( vec_free [u] hdr )
    } {}
    ( vec_free [u] empty )
    ( vec_free [u] pay0 ) ( vec_free [u] pay1 ) ( vec_free [u] pay2 )
    ( vec_free [u] rt0 ) ( vec_free [u] rt1 ) ( vec_free [u] rt2 )
    = . c bytes_sent + . c bytes_sent ( vec_len [u] dgram )
    ? > ( vec_len [u] dgram ) 0 { = . c last_activity now } {}
    ^ dgram
}

// ── timers ───────────────────────────────────────────────────────

@ quic_conn_next_timeout * QuicConn c → i {
    ? >= . c state 2 { ^ . c close_deadline } {}
    : ~ i best 0
    : i lt ( quic_rec_next_timeout . c rec )
    ? > lt 0 { = best lt } {}
    ? == . c ack_needed2 2 {
        : i t + . c largest_rx_time2 25
        ? | == best 0 < t best { = best t } {}
    } {}
    ? > . c idle_timeout 0 {
        : i t + . c last_activity . c idle_timeout
        ? | == best 0 < t best { = best t } {}
    } {}
    ^ best
}

@ quic_conn_on_timeout * QuicConn c i now → v {
    = . c now now
    ? >= . c state 2 {
        ? >= now . c close_deadline { = . c state 4 } {}
        ^
    } {}
    ? & > . c idle_timeout 0 >= now + . c last_activity . c idle_timeout {
        // idle: silently done (§10.1)
        = . c state 4
        ^
    } {}
    ( quic_rec_on_timeout . c rec now )
    : ~ i space 0
    ~ < space 3 {
        : ( Vec u ) lost ( quic_rec_take_lost . c rec space )
        ? > ( vec_len [u] lost ) 0 { ( bytes_extend_bytes ( __qc_retx c space ) lost ) } {}
        ( vec_free [u] lost )
        = space + space 1
    }
    ? == . c ack_needed2 2 { ? >= now + . c largest_rx_time2 25 { = . c ack_needed2 1 } {} } {}
}
