// quic_frame_codec.nu — stdlib/std/quic_frame.nu round-trips, the
// per-packet-type allow list (RFC 9000 §12.4) and the malformed inputs
// a server must refuse with FRAME_ENCODING_ERROR.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_frame.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
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

// Parse `buf` from 0 and expect failure.
@ expect_bad s label ( Vec u ) buf → i {
    : *QuicFrame f ( quic_frame_parse buf 0 )
    ? == # i f 0 {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL (parsed type ` )
        ( nurl_print ( nurl_str_int . f ftype ) ) ( nurl_print `)\n` )
        ( quic_frame_free f )
        ^ 1
    }
}

@ main → i {
    : ~ i fails 0
    : ( Vec u ) out ( vec_new [u] )

    // ── STREAM with offset, length, FIN ─────────────────────────
    : ( Vec u ) data ( hx `48656c6c6f` )
    ( quic_push_stream out 4 1000 data T )
    = fails + fails ( check_hex `stream_encode` out `0f0443e80548656c6c6f` )
    : *QuicFrame f1 ( quic_frame_parse out 0 )
    ? == # i f1 0 { ( nurl_print `stream_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `stream_type` . f1 ftype 15 )
        = fails + fails ( check_int `stream_id` . f1 a 4 )
        = fails + fails ( check_int `stream_off` . f1 b 1000 )
        = fails + fails ( check_int `stream_len` . f1 c 5 )
        = fails + fails ( check_int `stream_fin` . f1 d 1 )
        = fails + fails ( check_hex `stream_data` . f1 bytes `48656c6c6f` )
        = fails + fails ( check_int `stream_next` . f1 next ( vec_len [u] out ) )
        ( quic_frame_free f1 )
    }
    ( vec_clear [u] out )

    // ── STREAM without offset (0), with length, no FIN; then a PING
    //    behind it — `next` must land on the PING ───────────────────
    ( quic_push_stream out 8 0 data F )
    ( quic_push_ping out )
    = fails + fails ( check_hex `stream0_encode` out `0a080548656c6c6f01` )
    : *QuicFrame f2 ( quic_frame_parse out 0 )
    ? == # i f2 0 { ( nurl_print `stream0_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `stream0_type` . f2 ftype 10 )
        = fails + fails ( check_int `stream0_off` . f2 b 0 )
        : *QuicFrame f3 ( quic_frame_parse out . f2 next )
        ? == # i f3 0 { ( nurl_print `ping_parse: FAIL\n` ) = fails + fails 1 } {
            = fails + fails ( check_int `ping_type` . f3 ftype 1 )
            = fails + fails ( check_int `ping_next` . f3 next ( vec_len [u] out ) )
            ( quic_frame_free f3 )
        }
        ( quic_frame_free f2 )
    }
    ( vec_clear [u] out )

    // ── STREAM without length: data runs to the end of the packet ──
    : ( Vec u ) nolen ( hx `0804616263` )
    : *QuicFrame f4 ( quic_frame_parse nolen 0 )
    ? == # i f4 0 { ( nurl_print `stream_nolen_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `stream_nolen_len` . f4 c 3 )
        = fails + fails ( check_hex `stream_nolen_data` . f4 bytes `616263` )
        ( quic_frame_free f4 )
    }

    // ── ACK with two extra ranges and ECN ────────────────────────
    : ( Vec i ) ranges ( vec_new [i] )
    ( vec_push [i] ranges 1 )
    ( vec_push [i] ranges 2 )
    ( vec_push [i] ranges 0 )
    ( vec_push [i] ranges 3 )
    ( quic_push_ack out 100 5 10 ranges 7 8 9 )
    = fails + fails ( check_hex `ack_encode` out `03406405020a01020003070809` )
    : *QuicFrame f5 ( quic_frame_parse out 0 )
    ? == # i f5 0 { ( nurl_print `ack_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `ack_largest` . f5 a 100 )
        = fails + fails ( check_int `ack_delay` . f5 b 5 )
        = fails + fails ( check_int `ack_first_range` . f5 c 10 )
        = fails + fails ( check_int `ack_ecn_flag` . f5 d 1 )
        = fails + fails ( check_int `ack_ints_len` ( vec_len [i] . f5 ints ) 7 )
        = fails + fails ( check_int `ack_ints_ce` ?? ( vec_get [i] . f5 ints 6 ) { T x → x F → -1 } 9 )
        ( quic_frame_free f5 )
    }
    ( vec_free [i] ranges )
    ( vec_clear [u] out )

    // ── ACK whose range does not fit below the previous one ──────
    : ( Vec u ) badack ( hx `020a0001050009` )
    = fails + fails ( expect_bad `ack_range_underflow` badack )
    // first range larger than the largest acknowledged
    : ( Vec u ) badack2 ( hx `0205000009` )
    = fails + fails ( expect_bad `ack_first_range_too_big` badack2 )

    // ── CRYPTO ───────────────────────────────────────────────────
    ( quic_push_crypto out 300 data )
    = fails + fails ( check_hex `crypto_encode` out `06412c0548656c6c6f` )
    : *QuicFrame f6 ( quic_frame_parse out 0 )
    ? == # i f6 0 { ( nurl_print `crypto_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `crypto_off` . f6 a 300 )
        = fails + fails ( check_int `crypto_len` . f6 b 5 )
        ( quic_frame_free f6 )
    }
    ( vec_clear [u] out )
    // CRYPTO claiming more bytes than present
    : ( Vec u ) badcrypto ( hx `0600104142` )
    = fails + fails ( expect_bad `crypto_truncated` badcrypto )

    // ── NEW_CONNECTION_ID + RETIRE ───────────────────────────────
    : ( Vec u ) cid ( hx `0102030405060708` )
    : ( Vec u ) token ( hx `000102030405060708090a0b0c0d0e0f` )
    ( quic_push_new_connection_id out 7 3 cid token )
    = fails + fails ( check_hex `ncid_encode` out `180703080102030405060708000102030405060708090a0b0c0d0e0f` )
    : *QuicFrame f7 ( quic_frame_parse out 0 )
    ? == # i f7 0 { ( nurl_print `ncid_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `ncid_seq` . f7 a 7 )
        = fails + fails ( check_int `ncid_retire` . f7 b 3 )
        = fails + fails ( check_int `ncid_len` . f7 c 8 )
        = fails + fails ( check_int `ncid_bytes` ( vec_len [u] . f7 bytes ) 24 )
        ( quic_frame_free f7 )
    }
    ( vec_clear [u] out )
    // Retire_Prior_To > Sequence
    : ( Vec u ) badncid ( hx `180307080102030405060708000102030405060708090a0b0c0d0e0f` )
    = fails + fails ( expect_bad `ncid_retire_gt_seq` badncid )
    // zero-length connection id
    : ( Vec u ) badncid2 ( hx `18070300000102030405060708090a0b0c0d0e0f` )
    = fails + fails ( expect_bad `ncid_zero_len` badncid2 )
    ( quic_push_retire_connection_id out 9 )
    = fails + fails ( check_hex `retire_encode` out `1909` )
    ( vec_clear [u] out )

    // ── CONNECTION_CLOSE, both flavours ──────────────────────────
    : ( Vec u ) reason ( hx `6279` )
    ( quic_push_connection_close out 10 6 reason )
    = fails + fails ( check_hex `close_encode` out `1c0a06026279` )
    : *QuicFrame f8 ( quic_frame_parse out 0 )
    ? == # i f8 0 { ( nurl_print `close_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `close_code` . f8 a 10 )
        = fails + fails ( check_int `close_frame_type` . f8 b 6 )
        = fails + fails ( check_int `close_app_flag` . f8 c 0 )
        = fails + fails ( check_hex `close_reason` . f8 bytes `6279` )
        ( quic_frame_free f8 )
    }
    ( vec_clear [u] out )
    ( quic_push_application_close out 256 reason )
    = fails + fails ( check_hex `appclose_encode` out `1d4100026279` )
    : *QuicFrame f9 ( quic_frame_parse out 0 )
    ? == # i f9 0 { ( nurl_print `appclose_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `appclose_code` . f9 a 256 )
        = fails + fails ( check_int `appclose_app_flag` . f9 c 1 )
        ( quic_frame_free f9 )
    }
    ( vec_clear [u] out )

    // ── MAX_STREAMS / STREAMS_BLOCKED directions ─────────────────
    ( quic_push_max_streams out T 100 )
    ( quic_push_max_streams out F 3 )
    ( quic_push_streams_blocked out F 3 )
    = fails + fails ( check_hex `max_streams_encode` out `12406413031703` )
    : *QuicFrame f10 ( quic_frame_parse out 0 )
    ? == # i f10 0 { ( nurl_print `max_streams_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `max_streams_bidi_val` . f10 a 100 )
        = fails + fails ( check_int `max_streams_bidi_flag` . f10 b 1 )
        : *QuicFrame f11 ( quic_frame_parse out . f10 next )
        ? == # i f11 0 { ( nurl_print `max_streams_uni_parse: FAIL\n` ) = fails + fails 1 } {
            = fails + fails ( check_int `max_streams_uni_flag` . f11 b 0 )
            ( quic_frame_free f11 )
        }
        ( quic_frame_free f10 )
    }
    ( vec_clear [u] out )

    // ── PADDING run, PATH_CHALLENGE, HANDSHAKE_DONE ──────────────
    ( quic_push_padding out 5 )
    : ( Vec u ) eight ( hx `0001020304050607` )
    ( quic_push_path_challenge out eight )
    ( quic_push_handshake_done out )
    = fails + fails ( check_hex `misc_encode` out `00000000001a00010203040506071e` )
    : *QuicFrame f12 ( quic_frame_parse out 0 )
    ? == # i f12 0 { ( nurl_print `padding_parse: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `padding_type` . f12 ftype 0 )
        = fails + fails ( check_int `padding_run_next` . f12 next 5 )
        : *QuicFrame f13 ( quic_frame_parse out . f12 next )
        ? == # i f13 0 { ( nurl_print `path_challenge_parse: FAIL\n` ) = fails + fails 1 } {
            = fails + fails ( check_int `path_challenge_type` . f13 ftype 26 )
            = fails + fails ( check_hex `path_challenge_data` . f13 bytes `0001020304050607` )
            : *QuicFrame f14 ( quic_frame_parse out . f13 next )
            ? == # i f14 0 { ( nurl_print `hsdone_parse: FAIL\n` ) = fails + fails 1 } {
                = fails + fails ( check_int `hsdone_type` . f14 ftype 30 )
                ( quic_frame_free f14 )
            }
            ( quic_frame_free f13 )
        }
        ( quic_frame_free f12 )
    }
    ( vec_clear [u] out )
    // PATH_CHALLENGE short of its 8 bytes
    : ( Vec u ) badpc ( hx `1a0001` )
    = fails + fails ( expect_bad `path_challenge_short` badpc )

    // ── unknown types ────────────────────────────────────────────
    : ( Vec u ) unk ( hx `1f` )
    = fails + fails ( expect_bad `unknown_0x1f` unk )
    : ( Vec u ) unk2 ( hx `30054142434445` )
    = fails + fails ( expect_bad `datagram_not_negotiated` unk2 )
    : ( Vec u ) unk3 ( hx `4021` )
    = fails + fails ( expect_bad `unknown_2byte_type` unk3 )
    : ( Vec u ) nothing ( vec_new [u] )
    = fails + fails ( expect_bad `empty_buffer` nothing )

    // ── allow list (§12.4) ───────────────────────────────────────
    = fails + fails ( check_int `allow_initial_crypto` ? ( quic_frame_allowed 6 0 ) 1 0 1 )
    = fails + fails ( check_int `allow_initial_stream` ? ( quic_frame_allowed 8 0 ) 1 0 0 )
    = fails + fails ( check_int `allow_handshake_path_challenge` ? ( quic_frame_allowed 26 2 ) 1 0 0 )
    = fails + fails ( check_int `allow_handshake_app_close` ? ( quic_frame_allowed 29 2 ) 1 0 0 )
    = fails + fails ( check_int `allow_handshake_close` ? ( quic_frame_allowed 28 2 ) 1 0 1 )
    = fails + fails ( check_int `allow_0rtt_crypto` ? ( quic_frame_allowed 6 1 ) 1 0 0 )
    = fails + fails ( check_int `allow_0rtt_stream` ? ( quic_frame_allowed 8 1 ) 1 0 1 )
    = fails + fails ( check_int `allow_1rtt_hsdone` ? ( quic_frame_allowed 30 4 ) 1 0 1 )
    = fails + fails ( check_int `ack_eliciting_ping` ? ( quic_frame_is_ack_eliciting 1 ) 1 0 1 )
    = fails + fails ( check_int `ack_eliciting_ack` ? ( quic_frame_is_ack_eliciting 2 ) 1 0 0 )
    = fails + fails ( check_int `ack_eliciting_close` ? ( quic_frame_is_ack_eliciting 28 ) 1 0 0 )
    = fails + fails ( check_int `stream_overhead` ( quic_stream_frame_overhead 4 1000 5 ) 5 )

    ( vec_free [u] nothing )
    ( vec_free [u] unk3 )
    ( vec_free [u] unk2 )
    ( vec_free [u] unk )
    ( vec_free [u] badpc )
    ( vec_free [u] eight )
    ( vec_free [u] reason )
    ( vec_free [u] badncid2 )
    ( vec_free [u] badncid )
    ( vec_free [u] token )
    ( vec_free [u] cid )
    ( vec_free [u] badcrypto )
    ( vec_free [u] badack2 )
    ( vec_free [u] badack )
    ( vec_free [u] nolen )
    ( vec_free [u] data )
    ( vec_free [u] out )

    ? == fails 0 { ( nurl_print `quic_frame: all PASS\n` ) } { ( nurl_print `quic_frame: FAILURES\n` ) }
    ^ fails
}
