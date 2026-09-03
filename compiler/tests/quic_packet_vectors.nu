// quic_packet_vectors.nu — RFC 9001 Appendix A known-answer tests for
// stdlib/std/quic_packet.nu (Initial secrets, AES-128-GCM and
// ChaCha20-Poly1305 packet protection, header protection, Retry
// integrity tag), plus quic_varint / packet-number codec checks.
//
// Every hex string below is copied from the RFC text (A.1–A.5).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_packet.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

@ check s label ( Vec u ) got s want → i {
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

// The A.2 client Initial payload: the CRYPTO frame from the RFC, padded
// with zero bytes (PADDING frames) to 1162 bytes.
@ client_initial_payload → ( Vec u ) {
    : ( Vec u ) p ( hx `060040f1010000ed0303ebf8fa56f12939b9584a3896472ec40bb863cfd3e86804fe3a47f06a2b69484c00000413011302010000c000000010000e00000b6578616d706c652e636f6dff01000100000a00080006001d0017001800100007000504616c706e000500050100000000003300260024001d00209370b2c9caa47fbabaf4559fedba753de171fa71f50f1ce15d43e994ec74d748002b0003020304000d0010000e0403050306030203080408050806002d00020101001c00024001003900320408ffffffffffffffff05048000ffff07048000ffff0801100104800075300901100f088394c8f03e51570806048000ffff` )
    ~ < ( vec_len [u] p ) 1162 { ( vec_push [u] p # u 0 ) }
    ^ p
}

@ main → i {
    : ~ i fails 0

    // ── A.1 keys ────────────────────────────────────────────────
    : ( Vec u ) dcid ( hx `8394c8f03e515708` )
    : ( Vec u ) initial ( quic_initial_secret dcid )
    = fails + fails ( check `initial_secret` initial `7db5df06e7a69e432496adedb00851923595221596ae2ae9fb8115c1e9ed0a44` )
    : *QuicKeys ck ( quic_initial_keys dcid T )
    = fails + fails ( check `client_initial_secret` . ck secret `c00cf151ca5be075ed0ebfb5c80323c42d6b7db67881289af4008f1f6c357aea` )
    = fails + fails ( check `client_key` . ck key `1f369613dd76d5467730efcbe3b1a22d` )
    = fails + fails ( check `client_iv` . ck iv `fa044b2f42a3fd3b46fb255c` )
    = fails + fails ( check `client_hp` . ck hp `9f50449e04a0e810283a1e9933adedd2` )
    : *QuicKeys sk ( quic_initial_keys dcid F )
    = fails + fails ( check `server_initial_secret` . sk secret `3c199828fd139efd216c155ad844cc81fb82fa8d7446fa7d78be803acdda951b` )
    = fails + fails ( check `server_key` . sk key `cf3a5331653c364c88f0f379b6067e37` )
    = fails + fails ( check `server_iv` . sk iv `0ac1493ca1905853b0bba03e` )
    = fails + fails ( check `server_hp` . sk hp `c206b8d9b9f0f37644430b490eeaa314` )

    // ── A.2 client Initial: protect ──────────────────────────────
    : ( Vec u ) payload ( client_initial_payload )
    = fails + fails ( check_int `client_payload_len` ( vec_len [u] payload ) 1162 )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) chdr ( quic_long_hdr_build 0 dcid empty empty 1182 2 4 )
    = fails + fails ( check `client_header` chdr `c300000001088394c8f03e5157080000449e00000002` )
    : ( Vec u ) cpkt ( quic_packet_protect ck chdr 2 4 payload )
    = fails + fails ( check_int `client_packet_len` ( vec_len [u] cpkt ) 1200 )
    : ( Vec u ) cpkt_head ( bytes_slice cpkt 0 38 )
    = fails + fails ( check `client_packet_head` cpkt_head `c000000001088394c8f03e5157080000449e7b9aec34d1b1c98dd7689fb8ec11d242b123dc9b` )
    : ( Vec u ) cpkt_tail ( bytes_slice cpkt 1184 1200 )
    = fails + fails ( check `client_packet_tail` cpkt_tail `e221af44860018ab0856972e194cd934` )

    // ── A.2 client Initial: unprotect (server side) ──────────────
    : *QuicHdr ph ( quic_hdr_parse cpkt 0 0 )
    ? == # i ph 0 { ( nurl_print `client_parse: FAIL (null)\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `client_parse_type` . ph ptype 0 )
        = fails + fails ( check_int `client_parse_version` . ph version 1 )
        = fails + fails ( check_int `client_parse_dcid_len` . ph dcid_len 8 )
        = fails + fails ( check_int `client_parse_length` . ph length 1182 )
        = fails + fails ( check_int `client_parse_pn_off` . ph pn_off 18 )
        = fails + fails ( check_int `client_parse_end` . ph end 1200 )
        : ( Vec u ) pdcid ( quic_hdr_dcid ph cpkt )
        = fails + fails ( check `client_parse_dcid` pdcid `8394c8f03e515708` )
        : *QuicKeys srk ( quic_initial_keys pdcid T )
        : i pn_len ( quic_hp_remove srk cpkt . ph pn_off )
        = fails + fails ( check_int `client_unprotect_pn_len` pn_len 4 )
        : i pn ( quic_pn_decode ( quic_pn_read cpkt . ph pn_off pn_len ) pn_len -1 )
        = fails + fails ( check_int `client_unprotect_pn` pn 2 )
        : ( Vec u ) hdr ( bytes_slice cpkt 0 + . ph pn_off pn_len )
        = fails + fails ( check `client_unprotect_header` hdr `c300000001088394c8f03e5157080000449e00000002` )
        : ( Vec u ) body ( bytes_slice cpkt + . ph pn_off pn_len . ph end )
        ?? ( quic_open srk pn hdr body ) {
            T pt → {
                = fails + fails ( check_int `client_open_len` ( vec_len [u] pt ) 1162 )
                : ( Vec u ) head ( bytes_slice pt 0 16 )
                = fails + fails ( check `client_open_head` head `060040f1010000ed0303ebf8fa56f129` )
                ( vec_free [u] head )
                ( vec_free [u] pt )
            }
            F → { ( nurl_print `client_open: FAIL (tag)\n` ) = fails + fails 1 }
        }
        ( vec_free [u] body )
        ( vec_free [u] hdr )
        ( quic_keys_free srk )
        ( vec_free [u] pdcid )
        ( quic_hdr_free ph )
    }

    // ── A.3 server Initial ───────────────────────────────────────
    : ( Vec u ) spayload ( hx `02000000000600405a020000560303eefce7f7b37ba1d1632e96677825ddf73988cfc79825df566dc5430b9a045a1200130100002e00330024001d00209d3c940d89690b84d08a60993c144eca684d1081287c834d5311bcf32bb9da1a002b00020304` )
    : ( Vec u ) sdcid ( hx `f067a5502a4262b5` )
    : ( Vec u ) shdr ( quic_long_hdr_build 0 empty sdcid empty 117 1 2 )
    = fails + fails ( check `server_header` shdr `c1000000010008f067a5502a4262b50040750001` )
    : ( Vec u ) spkt ( quic_packet_protect sk shdr 1 2 spayload )
    = fails + fails ( check `server_packet` spkt `cf000000010008f067a5502a4262b5004075c0d95a482cd0991cd25b0aac406a5816b6394100f37a1c69797554780bb38cc5a99f5ede4cf73c3ec2493a1839b3dbcba3f6ea46c5b7684df3548e7ddeb9c3bf9c73cc3f3bded74b562bfb19fb84022f8ef4cdd93795d77d06edbb7aaf2f58891850abbdca3d20398c276456cbc42158407dd074ee` )

    // ── A.4 Retry ────────────────────────────────────────────────
    : ( Vec u ) rdcid ( vec_new [u] )
    : ( Vec u ) rscid ( hx `f067a5502a4262b5` )
    : ( Vec u ) rtoken ( hx `746f6b656e` )
    : ( Vec u ) retry ( quic_retry_build rdcid rscid dcid rtoken )
    = fails + fails ( check `retry_packet` retry `ff000000010008f067a5502a4262b5746f6b656e04a265ba2eff4d829058fb3f0f2496ba` )
    : *QuicHdr rh ( quic_hdr_parse retry 0 0 )
    ? == # i rh 0 { ( nurl_print `retry_parse: FAIL (null)\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `retry_parse_type` . rh ptype 3 )
        : ( Vec u ) tok ( quic_hdr_token rh retry )
        = fails + fails ( check `retry_parse_token` tok `746f6b656e` )
        ( vec_free [u] tok )
        ( quic_hdr_free rh )
    }

    // ── A.5 ChaCha20-Poly1305 short header ───────────────────────
    : ( Vec u ) csecret ( hx `9ac312a7f877468ebe69422748ad00a15443f18203a07d6060f688f30f21632b` )
    : *QuicKeys cc ( quic_keys_derive 2 csecret )
    = fails + fails ( check `chacha_key` . cc key `c6d98ff3441c3fe1b2182094f69caa2ed4b716b65488960a7a984979fb23e1c8` )
    = fails + fails ( check `chacha_iv` . cc iv `e0459b3474bdd0e44a41c144` )
    = fails + fails ( check `chacha_hp` . cc hp `25a282b9e82f06f21f488917a4fc8f1b73573685608597d0efcb076b0ab7a7a4` )
    : *QuicKeys ccu ( quic_keys_update cc )
    = fails + fails ( check `chacha_ku` . ccu secret `1223504755036d556342ee9361d253421a826c9ecdf3c7148684b36b714881f9` )
    : ( Vec u ) nonce ( quic_nonce . cc iv 654360564 )
    = fails + fails ( check `chacha_nonce` nonce `e0459b3474bdd0e46d417eb0` )
    : ( Vec u ) shortHdr ( quic_short_hdr_build empty 0 654360564 3 )
    = fails + fails ( check `chacha_header` shortHdr `4200bff4` )
    : ( Vec u ) ping ( hx `01` )
    : ( Vec u ) spk ( quic_packet_protect cc shortHdr 654360564 3 ping )
    = fails + fails ( check `chacha_packet` spk `4cfe4189655e5cd55c41f69080575d7999c25a5bfb` )
    // and back
    : *QuicHdr sh ( quic_hdr_parse spk 0 0 )
    ? == # i sh 0 { ( nurl_print `chacha_parse: FAIL (null)\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `chacha_parse_type` . sh ptype 4 )
        : i pl ( quic_hp_remove cc spk . sh pn_off )
        = fails + fails ( check_int `chacha_unprotect_pn_len` pl 3 )
        : i tpn ( quic_pn_read spk . sh pn_off pl )
        = fails + fails ( check_int `chacha_truncated_pn` tpn 49140 )
        : i fpn ( quic_pn_decode tpn pl 654360563 )
        = fails + fails ( check_int `chacha_full_pn` fpn 654360564 )
        : ( Vec u ) h2 ( bytes_slice spk 0 + . sh pn_off pl )
        : ( Vec u ) b2 ( bytes_slice spk + . sh pn_off pl . sh end )
        ?? ( quic_open cc fpn h2 b2 ) {
            T pt → { = fails + fails ( check `chacha_open` pt `01` ) ( vec_free [u] pt ) }
            F → { ( nurl_print `chacha_open: FAIL (tag)\n` ) = fails + fails 1 }
        }
        ( vec_free [u] b2 )
        ( vec_free [u] h2 )
        ( quic_hdr_free sh )
    }

    // ── varint + packet number codec (RFC 9000 §16 / App. A) ─────
    : ( Vec u ) vb ( vec_new [u] )
    ( quic_varint_push vb 151288809941952652 )
    ( quic_varint_push vb 494878333 )
    ( quic_varint_push vb 15293 )
    ( quic_varint_push vb 37 )
    = fails + fails ( check `varint_encode` vb `c2197c5eff14e88c9d7f3e7d7bbd25` )
    = fails + fails ( check_int `varint_read_8` ( quic_varint_read vb 0 ) 151288809941952652 )
    = fails + fails ( check_int `varint_read_4` ( quic_varint_read vb 8 ) 494878333 )
    = fails + fails ( check_int `varint_read_2` ( quic_varint_read vb 12 ) 15293 )
    = fails + fails ( check_int `varint_read_1` ( quic_varint_read vb 14 ) 37 )
    = fails + fails ( check_int `varint_truncated` ( quic_varint_read vb 15 ) -1 )
    : ( Vec u ) vt ( hx `c2197c` )
    = fails + fails ( check_int `varint_truncated_mid` ( quic_varint_read vt 0 ) -1 )
    = fails + fails ( check_int `varint_size_max` ( quic_varint_size ( quic_varint_max ) ) 8 )
    = fails + fails ( check_int `varint_size_over` ( quic_varint_size + ( quic_varint_max ) 1 ) 0 )
    = fails + fails ( check_int `pn_decode_a3` ( quic_pn_decode 39730 2 2822459642 ) 2822478642 )
    = fails + fails ( check_int `pn_encode_len_a2` ( quic_pn_encode_len 11295746 11266227 ) 2 )
    = fails + fails ( check_int `pn_encode_len_a2b` ( quic_pn_encode_len 11331838 11266227 ) 3 )
    = fails + fails ( check_int `pn_encode_len_first` ( quic_pn_encode_len 0 -1 ) 1 )
    = fails + fails ( check_int `pn_encode_len_big` ( quic_pn_encode_len 70000 0 ) 3 )

    ( vec_free [u] vt )
    ( vec_free [u] vb )
    ( vec_free [u] spk )
    ( vec_free [u] ping )
    ( vec_free [u] shortHdr )
    ( vec_free [u] nonce )
    ( quic_keys_free ccu )
    ( quic_keys_free cc )
    ( vec_free [u] csecret )
    ( vec_free [u] retry )
    ( vec_free [u] rtoken )
    ( vec_free [u] rscid )
    ( vec_free [u] rdcid )
    ( vec_free [u] spkt )
    ( vec_free [u] shdr )
    ( vec_free [u] sdcid )
    ( vec_free [u] spayload )
    ( vec_free [u] cpkt_tail )
    ( vec_free [u] cpkt_head )
    ( vec_free [u] cpkt )
    ( vec_free [u] chdr )
    ( vec_free [u] empty )
    ( vec_free [u] payload )
    ( quic_keys_free sk )
    ( quic_keys_free ck )
    ( vec_free [u] initial )
    ( vec_free [u] dcid )

    ? == fails 0 { ( nurl_print `quic_packet: all vectors PASS\n` ) } { ( nurl_print `quic_packet: FAILURES\n` ) }
    ^ fails
}
