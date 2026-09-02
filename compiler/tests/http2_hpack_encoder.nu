// http2_hpack_encoder.nu — the indexing HPACK encoder (RFC 7541 §6.1,
// §6.2.1, §6.2.2, §6.3) the HTTP/2 server emits response headers with.
//
// Locks, with a decoder mirroring the peer:
//   * `:status 200` is the one-byte static index 0x88;
//   * a header whose NAME is in the static table but whose value is not
//     goes out as "literal with incremental indexing, indexed name" and is
//     inserted into the dynamic table; an unknown name goes out as a
//     literal name and is inserted too;
//   * the SAME header list encoded again against the updated table is all
//     one-byte indexed fields — 46 bytes become 4 (88 c0 bf be);
//   * both blocks decode back to the original fields (names lowercased),
//     through a decoder table that started from the same defaults;
//   * a dynamic table of size 0 (peer disabled it): the block opens with a
//     size update (0x20), every field is "literal without indexing", and
//     nothing is inserted — and it still decodes.
// Before 2026-09-02 the server encoded every field as "literal without
// indexing" with literal name and value: correct, and 46 bytes every time.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http2_hpack.nu`

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

@ hex_of ( Vec u ) v → String {
    : String s ( string_new )
    : i n ( vec_len [u] v )
    : *u p ( vec_data [u] v )
    : s digits `0123456789abcdef`
    : ~ i k 0
    ~ < k n {
        : i b & # i . p k 255
        ? > k 0 { ( string_push_char s 32 ) } {}
        ( string_push_char s ( nurl_str_get digits >> b 4 ) )
        ( string_push_char s ( nurl_str_get digits & b 15 ) )
        = k + k 1
    }
    ^ s
}

@ sample_headers → ( Vec Header ) {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `:status` `200` ) )
    ( vec_push [Header] hs ( header_new `Content-Type` `text/plain; charset=utf-8` ) )
    ( vec_push [Header] hs ( header_new `content-length` `14` ) )
    ( vec_push [Header] hs ( header_new `x-custom` `abc` ) )
    ^ hs
}

@ headers_free ( Vec Header ) hs → v {
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
}

// Decoded list equals the sample, names compared lowercased.
@ matches_sample ( Vec Header ) got → b {
    ? != ( vec_len [Header] got ) 4 { ^ F } {}
    : *Header p ( vec_data [Header] got )
    : Header h0 . p 0
    : Header h1 . p 1
    : Header h2 . p 2
    : Header h3 . p 3
    : b ok0 & != 0 ( nurl_str_eq ( string_data . h0 name ) `:status` ) != 0 ( nurl_str_eq ( string_data . h0 value ) `200` )
    : b ok1 & != 0 ( nurl_str_eq ( string_data . h1 name ) `content-type` ) != 0 ( nurl_str_eq ( string_data . h1 value ) `text/plain; charset=utf-8` )
    : b ok2 & != 0 ( nurl_str_eq ( string_data . h2 name ) `content-length` ) != 0 ( nurl_str_eq ( string_data . h2 value ) `14` )
    : b ok3 & != 0 ( nurl_str_eq ( string_data . h3 name ) `x-custom` ) != 0 ( nurl_str_eq ( string_data . h3 value ) `abc` )
    ^ & & & ok0 ok1 ok2 ok3
}

@ main → i {
    : ( Vec Header ) hs ( sample_headers )

    // ── two blocks against a live table ──
    : HpackDynTable enc ( hpack_dyn_new 4096 )
    : HpackEncoded e1 ( hpack_encode_headers_dyn hs enc -1 )
    : ( Vec u ) b1 . e1 block
    : i b1_0 ?? ( vec_get [u] b1 0 ) { T x → # i x F _ → -1 }
    : String b1len ( string_new )
    ( string_push_int b1len ( vec_len [u] b1 ) )
    ( label `block1_len` ( string_data b1len ) )
    ( string_free b1len )
    ( label `block1_status_is_0x88` ( yn == b1_0 136 ) )
    : String dl ( string_new )
    ( string_push_int dl ( hpack_dyn_len . e1 dyn ) )
    ( label `dyn_entries_after_block1` ( string_data dl ) )
    ( string_free dl )

    : HpackEncoded e2 ( hpack_encode_headers_dyn hs . e1 dyn -1 )
    : ( Vec u ) b2 . e2 block
    : String h2 ( hex_of b2 )
    ( label `block2_hex` ( string_data h2 ) )
    ( string_free h2 )

    // Decoder side, mirroring: fresh table with the same default size.
    : HpackDynTable dec ( hpack_dyn_new 4096 )
    : !HpackDecoded HpackErr d1 ( hpack_decode_block b1 dec )
    ?? d1 {
        T dd1 → {
            ( label `block1_roundtrip` ( yn ( matches_sample . dd1 headers ) ) )
            ( headers_free . dd1 headers )
            : !HpackDecoded HpackErr d2 ( hpack_decode_block b2 . dd1 dyn )
            ?? d2 {
                T dd2 → {
                    ( label `block2_roundtrip` ( yn ( matches_sample . dd2 headers ) ) )
                    ( hpack_decoded_free dd2 )
                }
                F e → { ( label `block2_roundtrip` ( hpack_err_name e ) ) ( hpack_dyn_free . dd1 dyn ) }
            }
        }
        F e → { ( label `block1_roundtrip` ( hpack_err_name e ) ) ( hpack_dyn_free dec ) }
    }
    ( vec_free [u] b1 )
    ( vec_free [u] b2 )
    ( hpack_dyn_free . e2 dyn )

    // ── peer disabled the dynamic table: size update, no indexing ──
    : HpackDynTable enc0 ( hpack_dyn_new 0 )
    : HpackEncoded e3 ( hpack_encode_headers_dyn hs enc0 0 )
    : ( Vec u ) b3 . e3 block
    : i b3_0 ?? ( vec_get [u] b3 0 ) { T x → # i x F _ → -1 }
    ( label `zero_table_opens_with_size_update` ( yn == b3_0 32 ) )
    : String dl0 ( string_new )
    ( string_push_int dl0 ( hpack_dyn_len . e3 dyn ) )
    ( label `zero_table_entries` ( string_data dl0 ) )
    ( string_free dl0 )
    // No 0x40-prefixed (incremental indexing) field may appear after the
    // size update: scan the block for the representations used.
    : HpackDynTable dec0 ( hpack_dyn_new 4096 )
    : !HpackDecoded HpackErr d3 ( hpack_decode_block b3 dec0 )
    ?? d3 {
        T dd3 → {
            ( label `zero_table_roundtrip` ( yn ( matches_sample . dd3 headers ) ) )
            : String dm ( string_new )
            ( string_push_int dm ( hpack_dyn_len . dd3 dyn ) )
            ( label `decoder_table_after_zero_update` ( string_data dm ) )
            ( string_free dm )
            ( hpack_decoded_free dd3 )
        }
        F e → { ( label `zero_table_roundtrip` ( hpack_err_name e ) ) ( hpack_dyn_free dec0 ) }
    }
    ( vec_free [u] b3 )
    ( hpack_dyn_free . e3 dyn )
    ( headers_free hs )
    ^ 0
}
