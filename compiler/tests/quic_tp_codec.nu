// quic_tp_codec.nu — stdlib/std/quic_tp.nu: encode/decode round-trip
// of a client's transport parameters, the RFC 9000 §18.2 defaults, and
// every value a server must refuse with TRANSPORT_PARAMETER_ERROR (the
// h3spec "QUIC servers" transport-parameter cases).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_tp.nu`

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

@ check_hex s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ( string_free gh )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( string_data gh ) ) ( nurl_print ` want ` )
        ( nurl_print want ) ( nurl_print `\n` )
        ( string_free gh )
        ^ 1
    }
}

// Decode `hex` as a client's parameters and expect rejection.
@ expect_reject s label s hex → i {
    : ( Vec u ) b ( hx hex )
    : QuicTp t ( quic_tp_decode b T )
    ( vec_free [u] b )
    ? == 0 # i . t ctl {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL (accepted)\n` )
        ( quic_tp_free t )
        ^ 1
    }
}

// A minimal valid client set: initial_source_connection_id only.
@ minimal_client → s { ^ `0f08c1c2c3c4c5c6c7c8` }

@ main → i {
    : ~ i fails 0

    // ── the RFC 9001 A.2 ClientHello's parameters, verbatim ──────
    // 39 00 32 | 04 08 ffffffffffffffff | 05 04 8000ffff | 07 04 8000ffff |
    // 08 01 10 | 01 04 80007530 | 09 01 10 | 0f 08 8394c8f03e515708 | 06 04 8000ffff
    : ( Vec u ) a2 ( hx `0408ffffffffffffffff05048000ffff07048000ffff0801100104800075300901100f088394c8f03e51570806048000ffff` )
    : QuicTp t ( quic_tp_decode a2 T )
    ? == 0 # i . t ctl { ( nurl_print `a2_decode: FAIL (rejected)\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `a2_initial_max_data` ( quic_tp_initial_max_data t ) 4611686018427387903 )
        = fails + fails ( check_int `a2_bidi_local` ( quic_tp_initial_max_stream_data_bidi_local t ) 65535 )
        = fails + fails ( check_int `a2_bidi_remote` ( quic_tp_initial_max_stream_data_bidi_remote t ) 65535 )
        = fails + fails ( check_int `a2_uni` ( quic_tp_initial_max_stream_data_uni t ) 65535 )
        = fails + fails ( check_int `a2_streams_bidi` ( quic_tp_initial_max_streams_bidi t ) 16 )
        = fails + fails ( check_int `a2_streams_uni` ( quic_tp_initial_max_streams_uni t ) 16 )
        = fails + fails ( check_int `a2_idle` ( quic_tp_max_idle_timeout t ) 30000 )
        = fails + fails ( check_hex `a2_initial_scid` ( quic_tp_initial_scid t ) `8394c8f03e515708` )
        // defaults for what was absent
        = fails + fails ( check_int `a2_default_udp_payload` ( quic_tp_max_udp_payload_size t ) 65527 )
        = fails + fails ( check_int `a2_default_ack_exp` ( quic_tp_ack_delay_exponent t ) 3 )
        = fails + fails ( check_int `a2_default_max_ack_delay` ( quic_tp_max_ack_delay t ) 25 )
        = fails + fails ( check_int `a2_default_cid_limit` ( quic_tp_active_connection_id_limit t ) 2 )
        = fails + fails ( check_int `a2_no_odcid` ? ( quic_tp_has_original_dcid t ) 1 0 0 )
        // re-encode as the client would: same set, canonical order
        : ( Vec u ) enc ( quic_tp_encode t F )
        : QuicTp t2 ( quic_tp_decode enc T )
        ? == 0 # i . t2 ctl { ( nurl_print `a2_reencode: FAIL\n` ) = fails + fails 1 } {
            = fails + fails ( check_int `a2_reencode_max_data` ( quic_tp_initial_max_data t2 ) 4611686018427387903 )
            = fails + fails ( check_int `a2_reencode_idle` ( quic_tp_max_idle_timeout t2 ) 30000 )
            = fails + fails ( check_hex `a2_reencode_scid` ( quic_tp_initial_scid t2 ) `8394c8f03e515708` )
            ( quic_tp_free t2 )
        }
        ( vec_free [u] enc )
        ( quic_tp_free t )
    }
    ( vec_free [u] a2 )

    // ── a server's set round-trips, including the server-only ids ──
    : QuicTp st ( quic_tp_new )
    ( quic_tp_set_max_idle_timeout st 30000 )
    ( quic_tp_set_max_udp_payload_size st 1350 )
    ( quic_tp_set_initial_max_data st 1048576 )
    ( quic_tp_set_initial_max_stream_data_bidi_local st 262144 )
    ( quic_tp_set_initial_max_stream_data_bidi_remote st 262144 )
    ( quic_tp_set_initial_max_stream_data_uni st 262144 )
    ( quic_tp_set_initial_max_streams_bidi st 100 )
    ( quic_tp_set_initial_max_streams_uni st 3 )
    ( quic_tp_set_ack_delay_exponent st 3 )
    ( quic_tp_set_max_ack_delay st 25 )
    ( quic_tp_set_disable_active_migration st 1 )
    ( quic_tp_set_active_connection_id_limit st 4 )
    : ( Vec u ) tmp1 ( hx `8394c8f03e515708` )
    ( quic_tp_set_original_dcid st tmp1 )
    ( vec_free [u] tmp1 )
    : ( Vec u ) tmp2 ( hx `f067a5502a4262b5` )
    ( quic_tp_set_initial_scid st tmp2 )
    ( vec_free [u] tmp2 )
    : ( Vec u ) tmp3 ( hx `000102030405060708090a0b0c0d0e0f` )
    ( quic_tp_set_stateless_reset_token st tmp3 )
    ( vec_free [u] tmp3 )
    : ( Vec u ) senc ( quic_tp_encode st T )
    = fails + fails ( check_hex `server_encode` senc `00088394c8f03e5157080104800075300210000102030405060708090a0b0c0d0e0f03024546040480100000050480040000060480040000070480040000080240640901030c000e01040f08f067a5502a4262b5` )
    : QuicTp sdec ( quic_tp_decode senc F )
    ? == 0 # i . sdec ctl { ( nurl_print `server_decode: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `server_decode_odcid` ? ( quic_tp_has_original_dcid sdec ) 1 0 1 )
        = fails + fails ( check_hex `server_decode_token` ( quic_tp_stateless_reset_token sdec ) `000102030405060708090a0b0c0d0e0f` )
        = fails + fails ( check_int `server_decode_migration` ( quic_tp_disable_active_migration sdec ) 1 )
        = fails + fails ( check_int `server_decode_cid_limit` ( quic_tp_active_connection_id_limit sdec ) 4 )
        = fails + fails ( check_int `server_decode_udp` ( quic_tp_max_udp_payload_size sdec ) 1350 )
        ( quic_tp_free sdec )
    }
    // the same bytes read as a CLIENT's must be refused (server-only ids)
    : QuicTp wrong ( quic_tp_decode senc T )
    = fails + fails ( check_int `server_set_from_client_rejected` ? == 0 # i . wrong ctl 1 0 1 )
    ( quic_tp_free wrong )
    ( vec_free [u] senc )
    ( quic_tp_free st )

    // ── what a server refuses from a client (h3spec cases) ───────
    = fails + fails ( expect_reject `reject_missing_initial_scid` `0104800075300408ffffffffffffffff` )
    = fails + fails ( expect_reject `reject_original_dcid` `00088394c8f03e5157080f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_preferred_address` `0d297f0000010bb8000000000000000000000000000000010bb8010100000000000000000000000000000000000f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_retry_scid` `1008a1a2a3a4a5a6a7a80f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_stateless_reset_token` `0210000102030405060708090a0b0c0d0e0f0f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_udp_payload_1199` `030244af0f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_ack_delay_exponent_21` `0a01150f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_max_ack_delay_2p14` `0b04800040000f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_cid_limit_1` `0e01010f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_duplicate_id` `0401050401060f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_streams_bidi_2p61` `0808e0000000000000000f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_cid_21_bytes` `0f15c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5` )
    = fails + fails ( expect_reject `reject_truncated_value` `04080102` )
    = fails + fails ( expect_reject `reject_int_length_mismatch` `0402050f08c1c2c3c4c5c6c7c8` )
    = fails + fails ( expect_reject `reject_migration_with_body` `0c01000f08c1c2c3c4c5c6c7c8` )

    // ── still accepted: boundary values and unknown ids ──────────
    : ( Vec u ) ok1 ( hx `030244b00a01140b0480003fff0e01020f08c1c2c3c4c5c6c7c8` )
    : QuicTp t3 ( quic_tp_decode ok1 T )
    ? == 0 # i . t3 ctl { ( nurl_print `accept_boundaries: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `accept_udp_1200` ( quic_tp_max_udp_payload_size t3 ) 1200 )
        = fails + fails ( check_int `accept_ack_exp_20` ( quic_tp_ack_delay_exponent t3 ) 20 )
        = fails + fails ( check_int `accept_max_ack_delay_16383` ( quic_tp_max_ack_delay t3 ) 16383 )
        ( quic_tp_free t3 )
    }
    ( vec_free [u] ok1 )
    // GREASE id 0x1b (27) with an arbitrary body, and a 2-byte id
    : ( Vec u ) ok2 ( hx `1b03aabbcc4aca000f08c1c2c3c4c5c6c7c8` )
    : QuicTp t4 ( quic_tp_decode ok2 T )
    = fails + fails ( check_int `accept_unknown_ids` ? != 0 # i . t4 ctl 1 0 1 )
    ( quic_tp_free t4 )
    ( vec_free [u] ok2 )
    : ( Vec u ) ok3 ( hx ( minimal_client ) )
    : QuicTp t5 ( quic_tp_decode ok3 T )
    = fails + fails ( check_int `accept_minimal` ? != 0 # i . t5 ctl 1 0 1 )
    ( quic_tp_free t5 )
    ( vec_free [u] ok3 )

    ? == fails 0 { ( nurl_print `quic_tp: all PASS\n` ) } { ( nurl_print `quic_tp: FAILURES\n` ) }
    ^ fails
}
