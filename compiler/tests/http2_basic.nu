// http2_basic.nu — HTTP/2 frame + HPACK regression covering the
// RFC 9113 §4 framing vectors and the RFC 7541 Appendix C HPACK
// integer / static-table / round-trip vectors.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_hpack.nu`

@ print_label s tag s value → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ print_bool s tag b v → v {
    ( print_label tag ? v `T` `F` )
}

// ── §A frame round-trips ─────────────────────────────────────────────

@ section_a → v {
    ( nurl_print `--- A frame round-trips ---\n` )

    // RFC 9113 §6.5.3 — SETTINGS ACK: empty payload, type=4, flags=ACK
    : H2Frame f1 @ H2Frame { 4 1 0 ( vec_new [u] ) }
    : ! ( Vec u ) H2FrameErr s1 ( h2_serialize_frame f1 16384 )
    ?? s1 {
        T w → {
            : i n ( vec_len [u] w )
            : *u p ( vec_data [u] w )
            : b shape & & & & & & & & == n 9
                                  == # i . p 0 0
                                  == # i . p 1 0
                                  == # i . p 2 0
                                  == # i . p 3 4
                                  == # i . p 4 1
                                  == # i . p 5 0
                                  == # i . p 6 0
                                  == # i . p 7 0
                                  == # i . p 8 0
            ( print_bool `settings_ack_wire` shape )
            ( vec_free [u] w )
        }
        F e → ( print_label `settings_ack_err` ( h2_frame_err_name e ) )
    }
    ( h2_frame_free f1 )

    // PING (8 bytes opaque, type=6, no flags, stream 0)
    : ( Vec u ) opaque ( vec_new [u] )
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] opaque # u + 16 k )  = k + k 1 }
    : H2Frame f2 @ H2Frame { 6 0 0 opaque }
    : ! ( Vec u ) H2FrameErr s2 ( h2_serialize_frame f2 16384 )
    ?? s2 {
        T w → {
            : ! H2ParsedFrame H2FrameErr pr ( h2_parse_frame w 0 )
            ?? pr {
                T pp → {
                    : H2Frame ff . pp frame
                    : b ok & & & == . ff frame_type 6 == . ff flags 0
                                  == . ff stream_id 0
                                  == ( vec_len [u] . ff payload ) 8
                    ( print_bool `ping_roundtrip` ok )
                    ( h2_parsed_frame_free pp )
                }
                F e → ( print_label `ping_parse_err` ( h2_frame_err_name e ) )
            }
            ( vec_free [u] w )
        }
        F _ → ( nurl_print `ping_ser_err\n` )
    }
    ( h2_frame_free f2 )

    // DATA on stream 5 with END_STREAM, payload "abc"
    : ( Vec u ) body ( bytes_from_str `abc` )
    : H2Frame f3 @ H2Frame { 0 1 5 body }
    : ! ( Vec u ) H2FrameErr s3 ( h2_serialize_frame f3 16384 )
    ?? s3 {
        T w → {
            : *u wp ( vec_data [u] w )
            : i sid_byte # i . wp 8
            : b ok & & & & & & == ( vec_len [u] w ) 12
                              == # i . wp 0 0
                              == # i . wp 1 0
                              == # i . wp 2 3
                              == # i . wp 3 0
                              == # i . wp 4 1
                              == sid_byte 5
            ( print_bool `data_wire` ok )
            ( vec_free [u] w )
        }
        F _ → ( nurl_print `data_ser_err\n` )
    }
    ( h2_frame_free f3 )

    // 24-bit length encoding sanity: payload of 16384 bytes (boundary
    // between default MAX_FRAME_SIZE and oversize).
    : ( Vec u ) big ( vec_with_cap [u] 16384 )
    : ~ i bk 0
    ~ < bk 16384 { ( vec_push [u] big # u 0 ) = bk + bk 1 }
    : H2Frame f4 @ H2Frame { 0 0 7 big }
    : ! ( Vec u ) H2FrameErr s4 ( h2_serialize_frame f4 16384 )
    ?? s4 {
        T w → {
            : *u wp ( vec_data [u] w )
            : b ok & & == # i . wp 0 0 == # i . wp 1 64 == # i . wp 2 0
            ( print_bool `data_16k_length_encoding` ok )
            ( vec_free [u] w )
        }
        F _ → ( nurl_print `data_16k_ser_err\n` )
    }
    ( h2_frame_free f4 )

    // Oversize rejection: payload > max_frame_size
    : ( Vec u ) huge ( vec_with_cap [u] 17000 )
    : ~ i hk 0
    ~ < hk 17000 { ( vec_push [u] huge # u 0 ) = hk + hk 1 }
    : H2Frame f5 @ H2Frame { 0 0 9 huge }
    : ! ( Vec u ) H2FrameErr s5 ( h2_serialize_frame f5 16384 )
    ?? s5 {
        T w → { ( nurl_print `unexpected_oversize_ok\n` ) ( vec_free [u] w ) }
        F e → ( print_label `oversize_err` ( h2_frame_err_name e ) )
    }
    ( h2_frame_free f5 )
}

// ── §B HPACK vectors ─────────────────────────────────────────────────

@ section_b → v {
    ( nurl_print `--- B HPACK vectors ---\n` )

    // RFC 7541 C.1.1: encode 10 with 5-bit prefix → 10
    : ( Vec u ) o1 ( vec_new [u] )
    ( hpack_encode_int o1 5 0 10 )
    : *u p1 ( vec_data [u] o1 )
    ( print_bool `c1_1_match` & == ( vec_len [u] o1 ) 1 == # i . p1 0 10 )
    ( vec_free [u] o1 )

    // RFC 7541 C.1.2: encode 1337 with 5-bit prefix → 1F 9A 0A
    : ( Vec u ) o2 ( vec_new [u] )
    ( hpack_encode_int o2 5 0 1337 )
    : *u p2 ( vec_data [u] o2 )
    : b m12 & & & == ( vec_len [u] o2 ) 3
                  == # i . p2 0 31
                  == # i . p2 1 154
                  == # i . p2 2 10
    ( print_bool `c1_2_match` m12 )
    // Round-trip decode
    : ! HpackInt HpackErr di ( hpack_decode_int o2 0 5 )
    ?? di {
        T iv → ( print_bool `c1_2_decode` & == . iv value 1337 == . iv consumed 3 )
        F _ → ( nurl_print `c1_2_decode_err\n` )
    }
    ( vec_free [u] o2 )

    // RFC 7541 C.1.3: encode 42 with 8-bit prefix → 42
    : ( Vec u ) o3 ( vec_new [u] )
    ( hpack_encode_int o3 8 0 42 )
    : *u p3 ( vec_data [u] o3 )
    ( print_bool `c1_3_match` & == ( vec_len [u] o3 ) 1 == # i . p3 0 42 )
    ( vec_free [u] o3 )

    // Static-table spot-check
    ( print_label `static_2` ( hpack_static_name 2 ) )
    ( print_label `static_2_value` ( hpack_static_value 2 ) )
    ( print_label `static_8_value` ( hpack_static_value 8 ) )
    ( print_label `static_28` ( hpack_static_name 28 ) )
    ( print_label `static_61` ( hpack_static_name 61 ) )

    // Round-trip a 2-header set through encode → decode
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `:status` `200` ) )
    ( vec_push [Header] hs ( header_new `content-type` `text/plain` ) )
    : ( Vec u ) blob ( hpack_encode_headers hs )
    : i blen ( vec_len [u] blob )
    ( print_label `roundtrip_blob_len` ( nurl_str_int blen ) )

    : HpackDynTable dt ( hpack_dyn_new 4096 )
    : ! HpackDecoded HpackErr dr ( hpack_decode_block blob dt )
    ?? dr {
        T dd → {
            : i hn ( vec_len [Header] . dd headers )
            : *Header hp ( vec_data [Header] . dd headers )
            : Header h0 . hp 0
            : Header h1 . hp 1
            : b ok & & == hn 2
                       != 0 ( nurl_str_eq ( string_data . h0 name ) `:status` )
                       != 0 ( nurl_str_eq ( string_data . h1 value ) `text/plain` )
            ( print_bool `roundtrip_ok` ok )
            ( hpack_decoded_free dd )
        }
        F e → ( print_label `roundtrip_err` ( hpack_err_name e ) )
    }
    ( vec_free [u] blob )
    ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
}

// ── §C HPACK Huffman ─────────────────────────────────────────────────

@ section_c → v {
    ( nurl_print `--- C HPACK Huffman ---\n` )

    // RFC 7541 C.4.1: ":method GET" Huffman-encoded literal block
    // Header field representation: 130 (= indexed entry 2, which is
    // :method: GET in the static table). No Huffman involved — this
    // is the trivial happy path.
    : ( Vec u ) idx ( vec_new [u] )
    ( vec_push [u] idx # u 130 )
    : HpackDynTable dt ( hpack_dyn_new 4096 )
    : ! HpackDecoded HpackErr ir ( hpack_decode_block idx dt )
    ?? ir {
        T dd → {
            : *Header hp ( vec_data [Header] . dd headers )
            : Header h . hp 0
            : b ok & != 0 ( nurl_str_eq ( string_data . h name ) `:method` )
                   != 0 ( nurl_str_eq ( string_data . h value ) `GET` )
            ( print_bool `c4_1_indexed` ok )
            ( hpack_decoded_free dd )
        }
        F _ → {
            ( nurl_print `c4_1_decode_err\n` )
            ( hpack_dyn_free dt )
        }
    }
    ( vec_free [u] idx )

    // Huffman decode of "www.example.com" (RFC 7541 C.4.1 partial):
    //   f1 e3 c2 e5 f2 3a 6b a0 ab 90 f4 ff
    : ( Vec u ) huf ( vec_new [u] )
    ( vec_push [u] huf # u 241 )
    ( vec_push [u] huf # u 227 )
    ( vec_push [u] huf # u 194 )
    ( vec_push [u] huf # u 229 )
    ( vec_push [u] huf # u 242 )
    ( vec_push [u] huf # u 58 )
    ( vec_push [u] huf # u 107 )
    ( vec_push [u] huf # u 160 )
    ( vec_push [u] huf # u 171 )
    ( vec_push [u] huf # u 144 )
    ( vec_push [u] huf # u 244 )
    ( vec_push [u] huf # u 255 )
    : ! String HpackErr hr ( __hpack_huffman_decode huf 0 12 )
    ?? hr {
        T s → {
            ( print_label `huffman_www_example` ( string_data s ) )
            ( string_free s )
        }
        F e → ( print_label `huffman_err` ( hpack_err_name e ) )
    }
    ( vec_free [u] huf )
}

@ main → i {
    ( section_a )
    ( section_b )
    ( section_c )
    ^ 0
}
