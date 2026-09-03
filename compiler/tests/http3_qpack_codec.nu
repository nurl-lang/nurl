// http3_qpack_codec.nu — stdlib/ext/http3_qpack.nu and http3_frame.nu:
// the static table, field-section decode (indexed, name-reference and
// literal representations, Huffman values), encode round-trip, the
// refusals a server owes (invalid static index, dynamic-table
// references with a zero-capacity table, encoder/decoder stream
// instructions), and HTTP/3 frame + SETTINGS codecs.
//
// The two field sections are the ones h3spec sends for its
// "mandatory pseudo-header absent" and "prohibited pseudo-header" cases.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http3_frame.nu`
$ `stdlib/ext/http3_qpack.nu`

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

@ check_str s label s got s want → i {
    ? ( nurl_str_eq got want ) {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got '` )
        ( nurl_print got ) ( nurl_print `' want '` )
        ( nurl_print want ) ( nurl_print `'\n` )
        ^ 1
    }
}

@ hdr_name ( Vec Header ) hs i k → s {
    : *Header hp ( vec_data [Header] hs )
    : Header h . hp k
    ^ ( string_data . h name )
}

@ hdr_value ( Vec Header ) hs i k → s {
    : *Header hp ( vec_data [Header] hs )
    : Header h . hp k
    ^ ( string_data . h value )
}

@ free_hs ( Vec Header ) hs → v {
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
}

@ expect_decode_err s label s hex i want → i {
    : ( Vec u ) b ( hx hex )
    : ~ i r 0
    ?? ( qpack_decode_section b ) {
        T hs → { ( free_hs hs ) = r ( check_int label 0 want ) }
        F code → { = r ( check_int label code want ) }
    }
    ( vec_free [u] b )
    ^ r
}

@ main → i {
    : ~ i fails 0

    // ── static table ─────────────────────────────────────────────
    = fails + fails ( check_str `static_0` ( qpack_static_name 0 ) `:authority` )
    = fails + fails ( check_str `static_17_name` ( qpack_static_name 17 ) `:method` )
    = fails + fails ( check_str `static_17_value` ( qpack_static_value 17 ) `GET` )
    = fails + fails ( check_str `static_23_value` ( qpack_static_value 23 ) `https` )
    = fails + fails ( check_str `static_25_value` ( qpack_static_value 25 ) `200` )
    = fails + fails ( check_str `static_98` ( qpack_static_name 98 ) `x-frame-options` )
    = fails + fails ( check_str `static_98_value` ( qpack_static_value 98 ) `sameorigin` )
    = fails + fails ( check_str `static_99_absent` ( qpack_static_name 99 ) `` )

    // ── h3spec's ":method GET :scheme https :path /" section ─────
    : ( Vec u ) s0 ( hx `0000d1d7c1` )
    ?? ( qpack_decode_section s0 ) {
        T hs → {
            = fails + fails ( check_int `s0_count` ( vec_len [Header] hs ) 3 )
            = fails + fails ( check_str `s0_0` ( hdr_name hs 0 ) `:method` )
            = fails + fails ( check_str `s0_0v` ( hdr_value hs 0 ) `GET` )
            = fails + fails ( check_str `s0_1v` ( hdr_value hs 1 ) `https` )
            = fails + fails ( check_str `s0_2` ( hdr_name hs 2 ) `:path` )
            = fails + fails ( check_str `s0_2v` ( hdr_value hs 2 ) `/` )
            ( free_hs hs )
        }
        F code → { = fails + fails ( check_int `s0_decode` code 0 ) }
    }
    ( vec_free [u] s0 )

    // ── name reference + literal name (":authority 127.0.0.1", ":foo bar") ──
    : ( Vec u ) s1 ( hx `0000d1d750093132372e302e302e31c1243a666f6f03626172` )
    ?? ( qpack_decode_section s1 ) {
        T hs → {
            = fails + fails ( check_int `s1_count` ( vec_len [Header] hs ) 5 )
            = fails + fails ( check_str `s1_authority` ( hdr_name hs 2 ) `:authority` )
            = fails + fails ( check_str `s1_authority_v` ( hdr_value hs 2 ) `127.0.0.1` )
            = fails + fails ( check_str `s1_foo` ( hdr_name hs 4 ) `:foo` )
            = fails + fails ( check_str `s1_foo_v` ( hdr_value hs 4 ) `bar` )
            ( free_hs hs )
        }
        F code → { = fails + fails ( check_int `s1_decode` code 0 ) }
    }
    ( vec_free [u] s1 )

    // ── literal name + value, both Huffman-coded (RFC 7541 C.4.3 strings:
    //    "custom-key" = 25a849e95ba97d7f, "custom-value" = 25a849e95bb8e8b4bf) ──
    //    001 N=0 H=1 len=7+1 · name · H=1 len=9 · value
    : ( Vec u ) s2 ( hx `00002f0125a849e95ba97d7f8925a849e95bb8e8b4bf` )
    ?? ( qpack_decode_section s2 ) {
        T hs → {
            = fails + fails ( check_int `s2_count` ( vec_len [Header] hs ) 1 )
            = fails + fails ( check_str `s2_name_huffman` ( hdr_name hs 0 ) `custom-key` )
            = fails + fails ( check_str `s2_value_huffman` ( hdr_value hs 0 ) `custom-value` )
            ( free_hs hs )
        }
        F code → { = fails + fails ( check_int `s2_decode` code 0 ) }
    }
    ( vec_free [u] s2 )

    // ── encode round-trip: index hits, name-only hits, literals ──
    : ( Vec Header ) out ( vec_new [Header] )
    ( vec_push [Header] out ( header_new `:status` `200` ) )
    ( vec_push [Header] out ( header_new `content-type` `text/plain` ) )
    ( vec_push [Header] out ( header_new `x-custom` `v1` ) )
    : ( Vec u ) enc ( qpack_encode_section out )
    ( free_hs out )
    = fails + fails ( check_int `enc_prefix_0` ( __qpk_bget_pub enc 0 ) 0 )
    = fails + fails ( check_int `enc_prefix_1` ( __qpk_bget_pub enc 1 ) 0 )
    = fails + fails ( check_int `enc_status_indexed` ( __qpk_bget_pub enc 2 ) 217 )
    ?? ( qpack_decode_section enc ) {
        T hs → {
            = fails + fails ( check_int `rt_count` ( vec_len [Header] hs ) 3 )
            = fails + fails ( check_str `rt_0` ( hdr_value hs 0 ) `200` )
            = fails + fails ( check_str `rt_1n` ( hdr_name hs 1 ) `content-type` )
            = fails + fails ( check_str `rt_1v` ( hdr_value hs 1 ) `text/plain` )
            = fails + fails ( check_str `rt_2n` ( hdr_name hs 2 ) `x-custom` )
            = fails + fails ( check_str `rt_2v` ( hdr_value hs 2 ) `v1` )
            ( free_hs hs )
        }
        F code → { = fails + fails ( check_int `rt_decode` code 0 ) }
    }
    ( vec_free [u] enc )

    // ── name-only static hits: the name is in the table, the value is
    // not — `:authority` is index 0, which a "-(k+2)" encoding must keep
    // apart from "no hit"; `date` (6) and `accept` (29) sit where an
    // off-by-two lands on `age` and `:status` (this was a real bug: the
    // HTTP/3 client's :authority reached the server as `age`) ──
    : ( Vec Header ) nm ( vec_new [Header] )
    ( vec_push [Header] nm ( header_new `:authority` `localhost` ) )
    ( vec_push [Header] nm ( header_new `:path` `/x` ) )
    ( vec_push [Header] nm ( header_new `date` `Tue, 01 Jan 2030 00:00:00 GMT` ) )
    ( vec_push [Header] nm ( header_new `accept` `text/plain` ) )
    : ( Vec u ) enc2 ( qpack_encode_section nm )
    ( free_hs nm )
    // 0x50 | index with a 4-bit prefix: :authority → 0x50, :path → 0x51
    = fails + fails ( check_int `nameref_authority_byte` ( __qpk_bget_pub enc2 2 ) 80 )
    ?? ( qpack_decode_section enc2 ) {
        T hs → {
            = fails + fails ( check_int `nm_count` ( vec_len [Header] hs ) 4 )
            = fails + fails ( check_str `nm_0n` ( hdr_name hs 0 ) `:authority` )
            = fails + fails ( check_str `nm_0v` ( hdr_value hs 0 ) `localhost` )
            = fails + fails ( check_str `nm_1n` ( hdr_name hs 1 ) `:path` )
            = fails + fails ( check_str `nm_1v` ( hdr_value hs 1 ) `/x` )
            = fails + fails ( check_str `nm_2n` ( hdr_name hs 2 ) `date` )
            = fails + fails ( check_str `nm_3n` ( hdr_name hs 3 ) `accept` )
            = fails + fails ( check_str `nm_3v` ( hdr_value hs 3 ) `text/plain` )
            ( free_hs hs )
        }
        F code → { = fails + fails ( check_int `nm_decode` code 0 ) }
    }
    ( vec_free [u] enc2 )

    // ── refusals (h3spec QPACK cases) ────────────────────────────
    = fails + fails ( expect_decode_err `invalid_static_index` `0000ff24` 512 )
    = fails + fails ( expect_decode_err `dynamic_indexed` `000080` 512 )
    = fails + fails ( expect_decode_err `post_base_indexed` `000010` 512 )
    = fails + fails ( expect_decode_err `name_ref_dynamic` `00004000` 512 )
    = fails + fails ( expect_decode_err `required_insert_count_nonzero` `0100c1` 512 )
    = fails + fails ( expect_decode_err `truncated_value` `0000510561` 512 )
    = fails + fails ( expect_decode_err `empty_block` `` 512 )

    // encoder stream: capacity 0 fine, capacity 1 error, insert error
    : ( Vec u ) e0 ( hx `20` )
    = fails + fails ( check_int `enc_capacity_0` ( qpack_encoder_instruction e0 0 ) 1 )
    : ( Vec u ) e1 ( hx `3fe11f` )
    = fails + fails ( check_int `enc_capacity_4096` ( qpack_encoder_instruction e1 0 ) -2 )
    : ( Vec u ) e2 ( hx `c0` )
    = fails + fails ( check_int `enc_insert_name_ref` ( qpack_encoder_instruction e2 0 ) -2 )
    : ( Vec u ) e3 ( vec_new [u] )
    = fails + fails ( check_int `enc_empty_waits` ( qpack_encoder_instruction e3 0 ) -1 )
    // decoder stream: stream cancellation ok, increment 0 error, ack error
    : ( Vec u ) d0 ( hx `40` )
    = fails + fails ( check_int `dec_cancel_ok` ( qpack_decoder_instruction d0 0 ) 1 )
    : ( Vec u ) d1 ( hx `00` )
    = fails + fails ( check_int `dec_increment_0` ( qpack_decoder_instruction d1 0 ) -2 )
    : ( Vec u ) d2 ( hx `80` )
    = fails + fails ( check_int `dec_section_ack` ( qpack_decoder_instruction d2 0 ) -2 )
    ( vec_free [u] d2 ) ( vec_free [u] d1 ) ( vec_free [u] d0 )
    ( vec_free [u] e3 ) ( vec_free [u] e2 ) ( vec_free [u] e1 ) ( vec_free [u] e0 )

    // ── HTTP/3 frames + SETTINGS ─────────────────────────────────
    : ( Vec u ) fr ( vec_new [u] )
    ( h3_push_settings fr 65536 )
    : *H3FrameHead fh ( h3_frame_peek fr 0 )
    ? == # i fh 0 { ( nurl_print `settings_peek: FAIL\n` ) = fails + fails 1 } {
        = fails + fails ( check_int `settings_type` . fh ftype 4 )
        = fails + fails ( check_int `settings_head_len` . fh head_len 2 )
        : ( Vec u ) pay ( bytes_slice fr . fh head_len + . fh head_len . fh length )
        = fails + fails ( check_int `settings_parse_ok` ( h3_settings_parse pay ) 0 )
        = fails + fails ( check_int `settings_qpack_cap` ( h3_settings_get pay 1 ) 0 )
        = fails + fails ( check_int `settings_mfs` ( h3_settings_get pay 6 ) 65536 )
        = fails + fails ( check_int `settings_absent` ( h3_settings_get pay 9 ) -1 )
        ( vec_free [u] pay )
        ( h3_frame_head_free fh )
    }
    ( vec_free [u] fr )
    : ( Vec u ) h2s ( hx `0201` )
    = fails + fails ( check_int `settings_h2_id_rejected` ( h3_settings_parse h2s ) 265 )
    : ( Vec u ) dup ( hx `06010601` )
    = fails + fails ( check_int `settings_dup_rejected` ( h3_settings_parse dup ) 265 )
    : ( Vec u ) trunc ( hx `06` )
    = fails + fails ( check_int `settings_truncated_rejected` ( h3_settings_parse trunc ) 265 )
    ( vec_free [u] trunc ) ( vec_free [u] dup ) ( vec_free [u] h2s )
    : ( Vec u ) partial ( hx `01` )
    : *H3FrameHead ph ( h3_frame_peek partial 0 )
    = fails + fails ( check_int `frame_head_incomplete` # i ph 0 )
    ( vec_free [u] partial )
    = fails + fails ( check_int `reserved_0x21` ? ( h3_type_is_reserved 33 ) 1 0 1 )
    = fails + fails ( check_int `reserved_0x40` ? ( h3_type_is_reserved 64 ) 1 0 1 )
    = fails + fails ( check_int `not_reserved_0x22` ? ( h3_type_is_reserved 34 ) 1 0 0 )

    ? == fails 0 { ( nurl_print `http3_qpack: all PASS\n` ) } { ( nurl_print `http3_qpack: FAILURES\n` ) }
    ^ fails
}

@ __qpk_bget_pub ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}
