// stdlib/ext/http3_qpack.nu — QPACK field compression (RFC 9204) as
// HTTP/3 uses it here: the static table, field-section decoding and
// encoding, and the encoder / decoder stream instruction parsers.
//
// This endpoint advertises QPACK_MAX_TABLE_CAPACITY = 0 and
// QPACK_BLOCKED_STREAMS = 0, so a peer may never reference or fill a
// dynamic table (RFC 9204 §3.2.3 / §4.1.3); every field line is a
// static-table reference or a literal, and any dynamic-table
// instruction on the encoder stream is QPACK_ENCODER_STREAM_ERROR.
// Huffman-coded strings decode through HPACK's decoder — the code is
// the same (RFC 9204 §4.1.2 / RFC 7541 Appendix B).
//
//   ( qpack_static_name idx ) · ( qpack_static_value idx )     → s   ("" past 98)
//   ( qpack_decode_section block )      → !( Vec Header ) i    fields, or an HTTP/3 error code
//   ( qpack_encode_section headers )    → ( Vec u )            static index / name reference / literal
//   ( qpack_encoder_instruction buf off ) → i                  -1 need more · -2 error (QPACK_ENCODER_STREAM_ERROR)
//                                                               · else bytes consumed (never: nothing is allowed)
//   ( qpack_decoder_instruction buf off ) → i                  -1 need more · -2 error (QPACK_DECODER_STREAM_ERROR)
//                                                               · else bytes consumed
//
// Error codes (RFC 9204 §8.3): 0x200 QPACK_DECOMPRESSION_FAILED,
// 0x201 QPACK_ENCODER_STREAM_ERROR, 0x202 QPACK_DECODER_STREAM_ERROR.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http2_hpack.nu`
$ `stdlib/std/quic_varint.nu`

@ qpack_err_decompression_failed → i { ^ 512 }

@ qpack_err_encoder_stream → i { ^ 513 }

@ qpack_err_decoder_stream → i { ^ 514 }

@ qpack_static_table_size → i { ^ 99 }

@ qpack_static_name i idx → s {
    ? == idx 0 { ^ `:authority` } {}
    ? == idx 1 { ^ `:path` } {}
    ? == idx 2 { ^ `age` } {}
    ? == idx 3 { ^ `content-disposition` } {}
    ? == idx 4 { ^ `content-length` } {}
    ? == idx 5 { ^ `cookie` } {}
    ? == idx 6 { ^ `date` } {}
    ? == idx 7 { ^ `etag` } {}
    ? == idx 8 { ^ `if-modified-since` } {}
    ? == idx 9 { ^ `if-none-match` } {}
    ? == idx 10 { ^ `last-modified` } {}
    ? == idx 11 { ^ `link` } {}
    ? == idx 12 { ^ `location` } {}
    ? == idx 13 { ^ `referer` } {}
    ? == idx 14 { ^ `set-cookie` } {}
    ? == idx 15 { ^ `:method` } {}
    ? == idx 16 { ^ `:method` } {}
    ? == idx 17 { ^ `:method` } {}
    ? == idx 18 { ^ `:method` } {}
    ? == idx 19 { ^ `:method` } {}
    ? == idx 20 { ^ `:method` } {}
    ? == idx 21 { ^ `:method` } {}
    ? == idx 22 { ^ `:scheme` } {}
    ? == idx 23 { ^ `:scheme` } {}
    ? == idx 24 { ^ `:status` } {}
    ? == idx 25 { ^ `:status` } {}
    ? == idx 26 { ^ `:status` } {}
    ? == idx 27 { ^ `:status` } {}
    ? == idx 28 { ^ `:status` } {}
    ? == idx 29 { ^ `accept` } {}
    ? == idx 30 { ^ `accept` } {}
    ? == idx 31 { ^ `accept-encoding` } {}
    ? == idx 32 { ^ `accept-ranges` } {}
    ? == idx 33 { ^ `access-control-allow-headers` } {}
    ? == idx 34 { ^ `access-control-allow-headers` } {}
    ? == idx 35 { ^ `access-control-allow-origin` } {}
    ? == idx 36 { ^ `cache-control` } {}
    ? == idx 37 { ^ `cache-control` } {}
    ? == idx 38 { ^ `cache-control` } {}
    ? == idx 39 { ^ `cache-control` } {}
    ? == idx 40 { ^ `cache-control` } {}
    ? == idx 41 { ^ `cache-control` } {}
    ? == idx 42 { ^ `content-encoding` } {}
    ? == idx 43 { ^ `content-encoding` } {}
    ? == idx 44 { ^ `content-type` } {}
    ? == idx 45 { ^ `content-type` } {}
    ? == idx 46 { ^ `content-type` } {}
    ? == idx 47 { ^ `content-type` } {}
    ? == idx 48 { ^ `content-type` } {}
    ? == idx 49 { ^ `content-type` } {}
    ? == idx 50 { ^ `content-type` } {}
    ? == idx 51 { ^ `content-type` } {}
    ? == idx 52 { ^ `content-type` } {}
    ? == idx 53 { ^ `content-type` } {}
    ? == idx 54 { ^ `content-type` } {}
    ? == idx 55 { ^ `range` } {}
    ? == idx 56 { ^ `strict-transport-security` } {}
    ? == idx 57 { ^ `strict-transport-security` } {}
    ? == idx 58 { ^ `strict-transport-security` } {}
    ? == idx 59 { ^ `vary` } {}
    ? == idx 60 { ^ `vary` } {}
    ? == idx 61 { ^ `x-content-type-options` } {}
    ? == idx 62 { ^ `x-xss-protection` } {}
    ? == idx 63 { ^ `:status` } {}
    ? == idx 64 { ^ `:status` } {}
    ? == idx 65 { ^ `:status` } {}
    ? == idx 66 { ^ `:status` } {}
    ? == idx 67 { ^ `:status` } {}
    ? == idx 68 { ^ `:status` } {}
    ? == idx 69 { ^ `:status` } {}
    ? == idx 70 { ^ `:status` } {}
    ? == idx 71 { ^ `:status` } {}
    ? == idx 72 { ^ `accept-language` } {}
    ? == idx 73 { ^ `access-control-allow-credentials` } {}
    ? == idx 74 { ^ `access-control-allow-credentials` } {}
    ? == idx 75 { ^ `access-control-allow-headers` } {}
    ? == idx 76 { ^ `access-control-allow-methods` } {}
    ? == idx 77 { ^ `access-control-allow-methods` } {}
    ? == idx 78 { ^ `access-control-allow-methods` } {}
    ? == idx 79 { ^ `access-control-expose-headers` } {}
    ? == idx 80 { ^ `access-control-request-headers` } {}
    ? == idx 81 { ^ `access-control-request-method` } {}
    ? == idx 82 { ^ `access-control-request-method` } {}
    ? == idx 83 { ^ `alt-svc` } {}
    ? == idx 84 { ^ `authorization` } {}
    ? == idx 85 { ^ `content-security-policy` } {}
    ? == idx 86 { ^ `early-data` } {}
    ? == idx 87 { ^ `expect-ct` } {}
    ? == idx 88 { ^ `forwarded` } {}
    ? == idx 89 { ^ `if-range` } {}
    ? == idx 90 { ^ `origin` } {}
    ? == idx 91 { ^ `purpose` } {}
    ? == idx 92 { ^ `server` } {}
    ? == idx 93 { ^ `timing-allow-origin` } {}
    ? == idx 94 { ^ `upgrade-insecure-requests` } {}
    ? == idx 95 { ^ `user-agent` } {}
    ? == idx 96 { ^ `x-forwarded-for` } {}
    ? == idx 97 { ^ `x-frame-options` } {}
    ? == idx 98 { ^ `x-frame-options` } {}
    ^ ``
}

@ qpack_static_value i idx → s {
    ? == idx 1 { ^ `/` } {}
    ? == idx 2 { ^ `0` } {}
    ? == idx 4 { ^ `0` } {}
    ? == idx 15 { ^ `CONNECT` } {}
    ? == idx 16 { ^ `DELETE` } {}
    ? == idx 17 { ^ `GET` } {}
    ? == idx 18 { ^ `HEAD` } {}
    ? == idx 19 { ^ `OPTIONS` } {}
    ? == idx 20 { ^ `POST` } {}
    ? == idx 21 { ^ `PUT` } {}
    ? == idx 22 { ^ `http` } {}
    ? == idx 23 { ^ `https` } {}
    ? == idx 24 { ^ `103` } {}
    ? == idx 25 { ^ `200` } {}
    ? == idx 26 { ^ `304` } {}
    ? == idx 27 { ^ `404` } {}
    ? == idx 28 { ^ `503` } {}
    ? == idx 29 { ^ `*/*` } {}
    ? == idx 30 { ^ `application/dns-` } {}
    ? == idx 31 { ^ `gzip, deflate, br` } {}
    ? == idx 32 { ^ `bytes` } {}
    ? == idx 33 { ^ `cache-control` } {}
    ? == idx 34 { ^ `content-type` } {}
    ? == idx 35 { ^ `*` } {}
    ? == idx 36 { ^ `max-age=0` } {}
    ? == idx 37 { ^ `max-age=2592000` } {}
    ? == idx 38 { ^ `max-age=604800` } {}
    ? == idx 39 { ^ `no-cache` } {}
    ? == idx 40 { ^ `no-store` } {}
    ? == idx 41 { ^ `public, max-` } {}
    ? == idx 42 { ^ `br` } {}
    ? == idx 43 { ^ `gzip` } {}
    ? == idx 44 { ^ `application/dns-` } {}
    ? == idx 45 { ^ `application/` } {}
    ? == idx 46 { ^ `application/json` } {}
    ? == idx 47 { ^ `application/x-www-` } {}
    ? == idx 48 { ^ `image/gif` } {}
    ? == idx 49 { ^ `image/jpeg` } {}
    ? == idx 50 { ^ `image/png` } {}
    ? == idx 51 { ^ `text/css` } {}
    ? == idx 52 { ^ `text/html;` } {}
    ? == idx 53 { ^ `text/plain` } {}
    ? == idx 54 { ^ `text/` } {}
    ? == idx 55 { ^ `bytes=0-` } {}
    ? == idx 56 { ^ `max-age=31536000` } {}
    ? == idx 57 { ^ `max-age=31536000;` } {}
    ? == idx 58 { ^ `max-age=31536000;` } {}
    ? == idx 59 { ^ `accept-encoding` } {}
    ? == idx 60 { ^ `origin` } {}
    ? == idx 61 { ^ `nosniff` } {}
    ? == idx 62 { ^ `1; mode=block` } {}
    ? == idx 63 { ^ `100` } {}
    ? == idx 64 { ^ `204` } {}
    ? == idx 65 { ^ `206` } {}
    ? == idx 66 { ^ `302` } {}
    ? == idx 67 { ^ `400` } {}
    ? == idx 68 { ^ `403` } {}
    ? == idx 69 { ^ `421` } {}
    ? == idx 70 { ^ `425` } {}
    ? == idx 71 { ^ `500` } {}
    ? == idx 73 { ^ `FALSE` } {}
    ? == idx 74 { ^ `TRUE` } {}
    ? == idx 75 { ^ `*` } {}
    ? == idx 76 { ^ `get` } {}
    ? == idx 77 { ^ `get, post, options` } {}
    ? == idx 78 { ^ `options` } {}
    ? == idx 79 { ^ `content-length` } {}
    ? == idx 80 { ^ `content-type` } {}
    ? == idx 81 { ^ `get` } {}
    ? == idx 82 { ^ `post` } {}
    ? == idx 83 { ^ `clear` } {}
    ? == idx 85 { ^ `script-src 'none';` } {}
    ? == idx 86 { ^ `1` } {}
    ? == idx 91 { ^ `prefetch` } {}
    ? == idx 93 { ^ `*` } {}
    ? == idx 94 { ^ `1` } {}
    ? == idx 97 { ^ `deny` } {}
    ? == idx 98 { ^ `sameorigin` } {}
    ^ ``
}

@ __qpk_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// A QPACK string: `H` is bit (prefix_bits) of the first byte, the
// length is a prefix_bits-bit integer, then the bytes (Huffman when H).
: QpackStr { String value i consumed }

@ __qpack_read_string ( Vec u ) buf i off i prefix_bits → !QpackStr i {
    : i n ( vec_len [u] buf )
    ? >= off n { ^ @ !QpackStr i { F ( qpack_err_decompression_failed ) } } {}
    : i hbit << 1 prefix_bits
    : b huffman != 0 & ( __qpk_bget buf off ) hbit
    : ~ i length 0
    : ~ i lc 0
    ?? ( hpack_decode_int buf off prefix_bits ) {
        T iv → { = length . iv value = lc . iv consumed }
        F _ → { ^ @ !QpackStr i { F ( qpack_err_decompression_failed ) } }
    }
    : i data_off + off lc
    ? | < length 0 < - n data_off length { ^ @ !QpackStr i { F ( qpack_err_decompression_failed ) } } {}
    ? > length 65536 { ^ @ !QpackStr i { F ( qpack_err_decompression_failed ) } } {}
    ? huffman {
        ?? ( _hpack_huffman_decode buf data_off length ) {
            T text → { ^ @ !QpackStr i { T @ QpackStr { text + lc length } } }
            F _ → { ^ @ !QpackStr i { F ( qpack_err_decompression_failed ) } }
        }
    } {}
    : String s ( string_with_cap length )
    : *u p ( vec_data [u] buf )
    ( string_push_bytes s # *u + # i p data_off length )
    ^ @ !QpackStr i { T @ QpackStr { s + lc length } }
}

@ __qpack_fail ( Vec Header ) hs i code → !( Vec Header ) i {
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    ^ @ !( Vec Header ) i { F code }
}

// Decode one encoded field section (RFC 9204 §4.5).
@ qpack_decode_section ( Vec u ) block → !( Vec Header ) i {
    : ( Vec Header ) hs ( vec_new [Header] )
    : i n ( vec_len [u] block )
    // prefix: Required Insert Count (8-bit prefix), then S + Delta Base (7-bit)
    : ~ i off 0
    ?? ( hpack_decode_int block 0 8 ) {
        T iv → {
            // with no dynamic table the encoded count must be 0
            ? != . iv value 0 { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) } {}
            = off . iv consumed
        }
        F _ → { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) }
    }
    ?? ( hpack_decode_int block off 7 ) {
        T iv → { = off + off . iv consumed }
        F _ → { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) }
    }
    ~ < off n {
        : i b ( __qpk_bget block off )
        ? != & b 128 0 {
            // Indexed Field Line: 1 T index(6+)
            ? == & b 64 0 { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) } {}
            : ~ i idx 0
            ?? ( hpack_decode_int block off 6 ) {
                T iv → { = idx . iv value = off + off . iv consumed }
                F _ → { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) }
            }
            ? >= idx ( qpack_static_table_size ) { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) } {}
            ( vec_push [Header] hs ( header_new ( qpack_static_name idx ) ( qpack_static_value idx ) ) )
        } {
            ? != & b 64 0 {
                // Literal Field Line with Name Reference: 01 N T index(4+), value
                ? == & b 16 0 { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) } {}
                : ~ i idx 0
                ?? ( hpack_decode_int block off 4 ) {
                    T iv → { = idx . iv value = off + off . iv consumed }
                    F _ → { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) }
                }
                ? >= idx ( qpack_static_table_size ) { ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) ) } {}
                ?? ( __qpack_read_string block off 7 ) {
                    T vs → {
                        ( vec_push [Header] hs ( header_new ( qpack_static_name idx ) ( string_data . vs value ) ) )
                        ( string_free . vs value )
                        = off + off . vs consumed
                    }
                    F e → { ^ ( __qpack_fail hs e ) }
                }
            } {
                ? != & b 32 0 {
                    // Literal Field Line with Literal Name: 001 N H name_len(3+) name, value
                    ?? ( __qpack_read_string block off 3 ) {
                        T ns → {
                            = off + off . ns consumed
                            ?? ( __qpack_read_string block off 7 ) {
                                T vs → {
                                    ( vec_push [Header] hs ( header_new ( string_data . ns value ) ( string_data . vs value ) ) )
                                    ( string_free . vs value )
                                    = off + off . vs consumed
                                }
                                F e → { ( string_free . ns value ) ^ ( __qpack_fail hs e ) }
                            }
                            ( string_free . ns value )
                        }
                        F e → { ^ ( __qpack_fail hs e ) }
                    }
                } {
                    // 0001 post-base index / 0000 post-base name reference:
                    // both need a dynamic table this endpoint never has.
                    ^ ( __qpack_fail hs ( qpack_err_decompression_failed ) )
                }
            }
        }
    }
    ^ @ !( Vec Header ) i { T hs }
}

// Exact static match → index; name-only match → name reference; else
// literal. Values as-is (no Huffman). The prefix is 0x00 0x00 (Required
// Insert Count 0, Base 0).
@ __qpack_static_find s name s value → i {
    : ~ i best -1
    : ~ i k 0
    ~ < k ( qpack_static_table_size ) {
        ? ( nurl_str_eq ( qpack_static_name k ) name ) {
            ? ( nurl_str_eq ( qpack_static_value k ) value ) { ^ k } {}
            // -(k+2), so that k = 0 (:authority) is told apart from "no hit"
            ? < best 0 { = best - - 0 k 2 } {}
        } {}
        = k + k 1
    }
    // a name-only hit is returned as -(k+2)
    ^ best
}

@ __qpack_push_string ( Vec u ) out i prefix_bits i first_or s text → v {
    : i n ( nurl_str_len text )
    ( hpack_encode_int out prefix_bits first_or n )
    ? > n 0 { ( bytes_extend_str out text ) } {}
}

@ qpack_encode_section ( Vec Header ) headers → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 0 )
    ( vec_push [u] out # u 0 )
    : i nh ( vec_len [Header] headers )
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k nh {
        : Header h . hp k
        : s nm ( string_data . h name )
        : s vl ( string_data . h value )
        : i f ( __qpack_static_find nm vl )
        ? >= f 0 {
            ( hpack_encode_int out 6 192 f )
        } {
            ? <= f -2 {
                : i idx - - 0 f 2
                ( hpack_encode_int out 4 80 idx )
                ( __qpack_push_string out 7 0 vl )
            } {
                ( __qpack_push_string out 3 32 nm )
                ( __qpack_push_string out 7 0 vl )
            }
        }
        = k + k 1
    }
    ^ out
}

// Encoder stream (RFC 9204 §4.3), read by the decoder side (us). With
// a zero dynamic-table capacity every instruction is a violation
// except Set Dynamic Table Capacity 0.
@ qpack_encoder_instruction ( Vec u ) buf i off → i {
    : i n ( vec_len [u] buf )
    ? >= off n { ^ -1 } {}
    : i b ( __qpk_bget buf off )
    ? != & b 128 0 { ^ -2 } {}
    ? != & b 64 0 { ^ -2 } {}
    ? != & b 32 0 {
        // Set Dynamic Table Capacity: 001 capacity(5+)
        ?? ( hpack_decode_int buf off 5 ) {
            T iv → { ? > . iv value 0 { ^ -2 } {} ^ . iv consumed }
            F e → { ^ ? ( __qpack_truncated e ) -1 -2 }
        }
    } {}
    // Duplicate: 000 index(5+)
    ^ -2
}

@ __qpack_truncated HpackErr e → b {
    ^ ?? e { HpackTruncated → T _ → F }
}

// Decoder stream (RFC 9204 §4.4), read by the encoder side (us).
@ qpack_decoder_instruction ( Vec u ) buf i off → i {
    : i n ( vec_len [u] buf )
    ? >= off n { ^ -1 } {}
    : i b ( __qpk_bget buf off )
    ? != & b 128 0 {
        // Section Acknowledgment: 1 stream id(7+) — we never send a
        // section that needs one, so any ack is unexpected (§4.4.1)
        ?? ( hpack_decode_int buf off 7 ) {
            T iv → { ^ -2 }
            F e → { ^ ? ( __qpack_truncated e ) -1 -2 }
        }
    } {}
    ? != & b 64 0 {
        // Stream Cancellation: 01 stream id(6+)
        ?? ( hpack_decode_int buf off 6 ) {
            T iv → { ^ . iv consumed }
            F e → { ^ ? ( __qpack_truncated e ) -1 -2 }
        }
    } {}
    // Insert Count Increment: 00 increment(6+); 0 is an error (§4.4.3)
    ?? ( hpack_decode_int buf off 6 ) {
        T iv → { ? == . iv value 0 { ^ -2 } {} ^ -2 }
        F e → { ^ ? ( __qpack_truncated e ) -1 -2 }
    }
}
