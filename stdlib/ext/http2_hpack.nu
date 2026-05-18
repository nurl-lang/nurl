// stdlib/ext/http2_hpack.nu — RFC 7541 HPACK header compression for HTTP/2.
//
// Server-side codec covering the full HPACK semantic surface:
//
//   - 61-entry static table (RFC 7541 Appendix A)
//   - Dynamic table with size-based FIFO eviction (§4.1, §4.2, §4.3)
//   - N-bit prefix-encoded integers (§5.1)
//   - String literals — raw OR Huffman-encoded (§5.2)
//   - All six header-field representations (§6):
//       6.1 indexed
//       6.2.1 literal with incremental indexing (name indexed | new name)
//       6.2.2 literal without indexing
//       6.2.3 literal never indexed
//       6.3 dynamic table size update
//   - Huffman decoder (RFC 7541 Appendix B) — required because most
//     real clients (curl, Chrome, Firefox) Huffman-encode by default.
//   - Encoder operates without Huffman (literal strings) — simpler
//     and the size difference for the small server-emitted headers
//     (status + content-type + content-length + a handful of cookies)
//     is well under the SETTINGS_MAX_HEADER_LIST_SIZE budget.
//
// Memory model: Header pairs use the existing `Header` type from
// stdlib/ext/http.nu (String name, String value, both OWNED). Caller
// frees the returned ( Vec Header ) via `headers_free`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`

// ── Errors ────────────────────────────────────────────────────────────

: | HpackErr {
    HpackIntegerOverflow       // §5.1 — encoded integer wouldn't fit i64
    HpackTruncated             // input ended mid-field
    HpackBadIndex              // static/dynamic table lookup out of range
    HpackBadHuffman            // invalid Huffman code OR EOS within data
    HpackTableSizeExceeded     // dynamic table size update > peer limit
    HpackOther
}

@ hpack_err_name HpackErr e → s {
    ^ ?? e {
        HpackIntegerOverflow   → `HpackIntegerOverflow`
        HpackTruncated         → `HpackTruncated`
        HpackBadIndex          → `HpackBadIndex`
        HpackBadHuffman        → `HpackBadHuffman`
        HpackTableSizeExceeded → `HpackTableSizeExceeded`
        HpackOther             → `HpackOther`
    }
}

// ── Static table (RFC 7541 Appendix A) ───────────────────────────────
//
// NURL's `??` doesn't accept integer literals as arm patterns, so the
// 61-entry table is unrolled into an if-else cascade. Tedious but
// deterministic; one O(idx) walk per lookup is fine for header decoding
// where the indices being looked up cluster in the low range anyway
// (:method, :path, :scheme, :status, common request headers).

@ hpack_static_table_size → i { ^ 61 }

@ hpack_static_name i idx → s {
    ? == idx 1  { ^ `:authority` } {}
    ? == idx 2  { ^ `:method` } {}
    ? == idx 3  { ^ `:method` } {}
    ? == idx 4  { ^ `:path` } {}
    ? == idx 5  { ^ `:path` } {}
    ? == idx 6  { ^ `:scheme` } {}
    ? == idx 7  { ^ `:scheme` } {}
    ? == idx 8  { ^ `:status` } {}
    ? == idx 9  { ^ `:status` } {}
    ? == idx 10 { ^ `:status` } {}
    ? == idx 11 { ^ `:status` } {}
    ? == idx 12 { ^ `:status` } {}
    ? == idx 13 { ^ `:status` } {}
    ? == idx 14 { ^ `:status` } {}
    ? == idx 15 { ^ `accept-charset` } {}
    ? == idx 16 { ^ `accept-encoding` } {}
    ? == idx 17 { ^ `accept-language` } {}
    ? == idx 18 { ^ `accept-ranges` } {}
    ? == idx 19 { ^ `accept` } {}
    ? == idx 20 { ^ `access-control-allow-origin` } {}
    ? == idx 21 { ^ `age` } {}
    ? == idx 22 { ^ `allow` } {}
    ? == idx 23 { ^ `authorization` } {}
    ? == idx 24 { ^ `cache-control` } {}
    ? == idx 25 { ^ `content-disposition` } {}
    ? == idx 26 { ^ `content-encoding` } {}
    ? == idx 27 { ^ `content-language` } {}
    ? == idx 28 { ^ `content-length` } {}
    ? == idx 29 { ^ `content-location` } {}
    ? == idx 30 { ^ `content-range` } {}
    ? == idx 31 { ^ `content-type` } {}
    ? == idx 32 { ^ `cookie` } {}
    ? == idx 33 { ^ `date` } {}
    ? == idx 34 { ^ `etag` } {}
    ? == idx 35 { ^ `expect` } {}
    ? == idx 36 { ^ `expires` } {}
    ? == idx 37 { ^ `from` } {}
    ? == idx 38 { ^ `host` } {}
    ? == idx 39 { ^ `if-match` } {}
    ? == idx 40 { ^ `if-modified-since` } {}
    ? == idx 41 { ^ `if-none-match` } {}
    ? == idx 42 { ^ `if-range` } {}
    ? == idx 43 { ^ `if-unmodified-since` } {}
    ? == idx 44 { ^ `last-modified` } {}
    ? == idx 45 { ^ `link` } {}
    ? == idx 46 { ^ `location` } {}
    ? == idx 47 { ^ `max-forwards` } {}
    ? == idx 48 { ^ `proxy-authenticate` } {}
    ? == idx 49 { ^ `proxy-authorization` } {}
    ? == idx 50 { ^ `range` } {}
    ? == idx 51 { ^ `referer` } {}
    ? == idx 52 { ^ `refresh` } {}
    ? == idx 53 { ^ `retry-after` } {}
    ? == idx 54 { ^ `server` } {}
    ? == idx 55 { ^ `set-cookie` } {}
    ? == idx 56 { ^ `strict-transport-security` } {}
    ? == idx 57 { ^ `transfer-encoding` } {}
    ? == idx 58 { ^ `user-agent` } {}
    ? == idx 59 { ^ `vary` } {}
    ? == idx 60 { ^ `via` } {}
    ? == idx 61 { ^ `www-authenticate` } {}
    ^ ``
}

@ hpack_static_value i idx → s {
    ? == idx 2  { ^ `GET` } {}
    ? == idx 3  { ^ `POST` } {}
    ? == idx 4  { ^ `/` } {}
    ? == idx 5  { ^ `/index.html` } {}
    ? == idx 6  { ^ `http` } {}
    ? == idx 7  { ^ `https` } {}
    ? == idx 8  { ^ `200` } {}
    ? == idx 9  { ^ `204` } {}
    ? == idx 10 { ^ `206` } {}
    ? == idx 11 { ^ `304` } {}
    ? == idx 12 { ^ `400` } {}
    ? == idx 13 { ^ `404` } {}
    ? == idx 14 { ^ `500` } {}
    ? == idx 16 { ^ `gzip, deflate` } {}
    ^ ``
}

// ── Dynamic table (RFC 7541 §2.3.2, §4) ──────────────────────────────
//
// FIFO ring of header pairs. Each entry's "size" per §4.1 is
//    name_len + value_len + 32
// Eviction (§4.4): when an insertion would push the cumulative size
// above max_size, evict from the back (oldest end) until it fits OR
// the table is empty. An entry larger than max_size by itself causes
// the whole table to drain — that's spec-mandated.
//
// Indexing (§2.3.3): the combined index space is
//    1..static_size                      → static table (1-indexed)
//    static_size+1..static_size+dyn_len  → dynamic table, newest first
// so a newly-added dynamic entry takes index 62 (= static_size+1) and
// pushes existing dynamic entries one slot higher.

: HpackDynTable {
    ( Vec Header ) entries     // OWNED; index 0 = newest
    i current_size             // sum of (name_len + value_len + 32)
    i max_size                 // peer-set via SETTINGS_HEADER_TABLE_SIZE
}

@ hpack_dyn_new i max_size → HpackDynTable {
    ^ @ HpackDynTable { ( vec_new [Header] ) 0 max_size }
}

@ hpack_dyn_free HpackDynTable t → v {
    ( vec_free_with [Header] . t entries \ Header h → v { ( header_free h ) } )
}

@ hpack_dyn_len HpackDynTable t → i { ^ ( vec_len [Header] . t entries ) }

@ __hpack_entry_size Header h → i {
    ^ + ( string_len . h name ) + ( string_len . h value ) 32
}

// Evict from the back until current_size + incoming ≤ max_size.
@ __hpack_dyn_evict HpackDynTable t i incoming → HpackDynTable {
    : ~ HpackDynTable cur t
    : ~ b done F
    ~ ! done {
        : i n ( vec_len [Header] . cur entries )
        ? == n 0 { = done T } {
            ? <= + . cur current_size incoming . cur max_size
            { = done T } {
                : ? Header tail ( vec_pop [Header] . cur entries )
                ?? tail {
                    T th → {
                        : i sz ( __hpack_entry_size th )
                        = . cur current_size - . cur current_size sz
                        ( header_free th )
                    }
                    F _ → { = done T }
                }
            }
        }
    }
    ^ cur
}

// Insert a header at the FRONT of the dynamic table. Owns name + value
// (caller transfers ownership). If the entry alone is larger than
// max_size, the table is fully drained per §4.4.
@ hpack_dyn_insert HpackDynTable t s name s value → HpackDynTable {
    : Header h ( header_new name value )
    : i sz ( __hpack_entry_size h )
    : ~ HpackDynTable cur ( __hpack_dyn_evict t sz )
    ? > sz . cur max_size {
        ( header_free h )
        ^ cur
    } {}
    ( vec_insert [Header] . cur entries 0 h )
    = . cur current_size + . cur current_size sz
    ^ cur
}

// Resize: typically called when peer sends a "dynamic table size update"
// header field (§6.3) lowering our max. Evicts to fit the new ceiling.
@ hpack_dyn_set_max HpackDynTable t i new_max → HpackDynTable {
    : ~ HpackDynTable cur t
    = . cur max_size new_max
    ^ ( __hpack_dyn_evict cur 0 )
}

// Lookup by combined HPACK index (1-indexed). Static range first, then
// dynamic. Returns an OWNED Header (caller `header_free`s) or None
// when out of range.
@ hpack_dyn_lookup HpackDynTable t i hidx → ? Header {
    ? <= hidx 0 { ^ @ ? Header { F # Header 0 } } {}
    : i ss ( hpack_static_table_size )
    ? <= hidx ss {
        ^ @ ? Header {
            T ( header_new ( hpack_static_name hidx )
                            ( hpack_static_value hidx ) )
        }
    } {}
    : i didx - hidx + ss 1
    : i n ( vec_len [Header] . t entries )
    ? >= didx n { ^ @ ? Header { F # Header 0 } } {}
    : ? Header got ( vec_get [Header] . t entries didx )
    ?? got {
        T h → { ^ @ ? Header { T ( header_new ( string_data . h name )
                                                ( string_data . h value ) ) } }
        F _ → { ^ @ ? Header { F # Header 0 } }
    }
}

// ── Integer codec (RFC 7541 §5.1) ────────────────────────────────────
//
// Variable-length integer with an N-bit prefix.
//   if value < (2^N - 1):
//     emit value in the N-bit prefix
//   else:
//     fill the N-bit prefix with (2^N - 1)
//     emit (value - (2^N - 1)) in continuation bytes:
//       repeat: emit (rem & 0x7F) | (more ? 0x80 : 0), rem >>= 7

@ __pow2 i n → i {
    : ~ i r 1
    : ~ i k 0
    ~ < k n { = r * r 2  = k + k 1 }
    ^ r
}

// Encode `value` with `prefix_bits` (1..8) bit prefix. The first byte's
// high (8 - prefix_bits) bits are filled with `first_byte_or` so the
// caller can pre-stamp the representation flags.
@ hpack_encode_int ( Vec u ) out i prefix_bits i first_byte_or i value → v {
    : i max_prefix - ( __pow2 prefix_bits ) 1
    ? < value max_prefix {
        ( vec_push [u] out # u | first_byte_or value )
    } {
        ( vec_push [u] out # u | first_byte_or max_prefix )
        : ~ i rem - value max_prefix
        ~ >= rem 128 {
            ( vec_push [u] out # u | & rem 127 128 )
            = rem >> rem 7
        }
        ( vec_push [u] out # u rem )
    }
}

: HpackInt { i value  i consumed }

// Decode at offset `from`. Returns HpackTruncated if input ends
// mid-continuation; HpackIntegerOverflow if more than 10 continuation
// bytes (a malicious peer could otherwise force an unbounded shift).
@ hpack_decode_int ( Vec u ) buf i from i prefix_bits → ! HpackInt HpackErr {
    : i n ( vec_len [u] buf )
    ? >= from n {
        ^ @ ! HpackInt HpackErr { F HpackTruncated }
    } {}
    : *u p ( vec_data [u] buf )
    : i max_prefix - ( __pow2 prefix_bits ) 1
    : i first & # i . p from max_prefix
    ? < first max_prefix {
        ^ @ ! HpackInt HpackErr {
            T @ HpackInt { first 1 }
        }
    } {}
    : ~ i value max_prefix
    : ~ i shift 0
    : ~ i k + from 1
    : ~ b done F
    : ~ b ok T
    ~ & ok ! done {
        ? >= k n { = ok F = done T } {
            : i b # i . p k
            = value + value << & b 127 shift
            = shift + shift 7
            ? > shift 63 { = ok F = done T } {}
            ? == 0 & b 128 { = done T } {}
            = k + k 1
        }
    }
    ? ! ok {
        ? > shift 63 {
            ^ @ ! HpackInt HpackErr { F HpackIntegerOverflow }
        } {}
        ^ @ ! HpackInt HpackErr { F HpackTruncated }
    } {}
    ^ @ ! HpackInt HpackErr {
        T @ HpackInt { value - + k 1 from }
    }
}

// ── String codec (RFC 7541 §5.2) ─────────────────────────────────────

: HpackString { String value  i consumed }

@ hpack_string_free HpackString s → v { ( string_free . s value ) }

@ hpack_decode_string ( Vec u ) buf i from → ! HpackString HpackErr {
    : i n ( vec_len [u] buf )
    ? >= from n {
        ^ @ ! HpackString HpackErr { F HpackTruncated }
    } {}
    : *u p ( vec_data [u] buf )
    : i first # i . p from
    : b huffman != 0 & first 128
    : ! HpackInt HpackErr li ( hpack_decode_int buf from 7 )
    : ~ i length 0
    : ~ i len_consumed 0
    ?? li {
        T iv → { = length . iv value  = len_consumed . iv consumed }
        F e → { ^ @ ! HpackString HpackErr { F e } }
    }
    : i data_off + from len_consumed
    ? < - n data_off length {
        ^ @ ! HpackString HpackErr { F HpackTruncated }
    } {}
    : ~ String s ( string_new )
    ? huffman {
        ( string_free s )
        : ! String HpackErr hr ( __hpack_huffman_decode buf data_off length )
        ?? hr {
            T text → { = s text }
            F e → { ^ @ ! HpackString HpackErr { F e } }
        }
    } {
        : ~ i k 0
        ~ < k length {
            : i b # i . p + data_off k
            ( string_push_char s b )
            = k + k 1
        }
    }
    ^ @ ! HpackString HpackErr {
        T @ HpackString { s + len_consumed length }
    }
}

// Encode literal (no Huffman). Server-side default — see file header.
@ hpack_encode_string ( Vec u ) out s text → v {
    : i n ( nurl_str_len text )
    ( hpack_encode_int out 7 0 n )
    ? > n 0 { ( bytes_extend_str out text ) } {}
}

// ── Header field representations (RFC 7541 §6) ────────────────────────

: HpackDecoded {
    ( Vec Header ) headers
    HpackDynTable dyn
}

// Local copy of http_request.nu's headers_free — keeps this module
// importable on its own without pulling in the whole request stack.
@ __hpack_headers_free ( Vec Header ) hs → v {
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
}

@ hpack_decoded_free HpackDecoded d → v {
    ( __hpack_headers_free . d headers )
    ( hpack_dyn_free . d dyn )
}

: HpackLitResult {
    String name
    String value
    HpackDynTable dyn
    i consumed
}

@ hpack_decode_block ( Vec u ) buf HpackDynTable dyn → ! HpackDecoded HpackErr {
    : i n ( vec_len [u] buf )
    : ~ ( Vec Header ) hdrs ( vec_new [Header] )
    : ~ HpackDynTable cur dyn
    : ~ i off 0
    : ~ b done F
    : ~ b ok T
    : ~ HpackErr last_err HpackOther
    ~ & ok < off n {
        : *u p ( vec_data [u] buf )
        : i b0 # i . p off
        ? != 0 & b0 128 {
            // 6.1 Indexed
            : ! HpackInt HpackErr ir ( hpack_decode_int buf off 7 )
            ?? ir {
                T iv → {
                    : ? Header opt ( hpack_dyn_lookup cur . iv value )
                    ?? opt {
                        T h → { ( vec_push [Header] hdrs h ) }
                        F _ → { = last_err HpackBadIndex  = ok F }
                    }
                    = off + off . iv consumed
                }
                F e → { = last_err e  = ok F }
            }
        } {
            ? != 0 & b0 64 {
                // 6.2.1 Literal with Incremental Indexing
                : ! HpackLitResult HpackErr lr ( __hpack_decode_lit_call buf off 6 T cur )
                ?? lr {
                    T lr_ → {
                        ( vec_push [Header] hdrs ( header_new
                            ( string_data . lr_ name )
                            ( string_data . lr_ value ) ) )
                        ( string_free . lr_ name )
                        ( string_free . lr_ value )
                        = cur . lr_ dyn
                        = off + off . lr_ consumed
                    }
                    F e → { = last_err e  = ok F }
                }
            } {
                ? != 0 & b0 32 {
                    // 6.3 Dynamic Table Size Update
                    : ! HpackInt HpackErr ir ( hpack_decode_int buf off 5 )
                    ?? ir {
                        T iv → {
                            = cur ( hpack_dyn_set_max cur . iv value )
                            = off + off . iv consumed
                        }
                        F e → { = last_err e  = ok F }
                    }
                } {
                    // 6.2.2 (top 4 = 0000) or 6.2.3 (top 4 = 0001) —
                    // both are "literal, do NOT add to dyn table".
                    : ! HpackLitResult HpackErr lr ( __hpack_decode_lit_call buf off 4 F cur )
                    ?? lr {
                        T lr_ → {
                            ( vec_push [Header] hdrs ( header_new
                                ( string_data . lr_ name )
                                ( string_data . lr_ value ) ) )
                            ( string_free . lr_ name )
                            ( string_free . lr_ value )
                            = cur . lr_ dyn
                            = off + off . lr_ consumed
                        }
                        F e → { = last_err e  = ok F }
                    }
                }
            }
        }
        ? >= off n { = done T } {}
    }
    ? ! ok {
        ( vec_free_with [Header] hdrs \ Header h → v { ( header_free h ) } )
        ( hpack_dyn_free cur )
        ^ @ ! HpackDecoded HpackErr { F last_err }
    } {}
    ^ @ ! HpackDecoded HpackErr {
        T @ HpackDecoded { hdrs cur }
    }
}

// Decode a literal-field representation starting at `off`. `prefix_bits`
// is 6 for §6.2.1, 4 for §6.2.2 / §6.2.3. `indexing` says whether to
// insert the resulting field into the dynamic table.
@ __hpack_decode_lit_call ( Vec u ) buf i off i prefix_bits b indexing HpackDynTable dyn → ! HpackLitResult HpackErr {
    : ! HpackInt HpackErr ni ( hpack_decode_int buf off prefix_bits )
    : ~ i name_idx 0
    : ~ i cur_off 0
    ?? ni {
        T iv → { = name_idx . iv value  = cur_off + off . iv consumed }
        F e → { ^ @ ! HpackLitResult HpackErr { F e } }
    }
    : ~ String name ( string_new )
    ? > name_idx 0 {
        : ? Header opt ( hpack_dyn_lookup dyn name_idx )
        ?? opt {
            T h → {
                ( string_free name )
                = name ( string_from ( string_data . h name ) )
                ( header_free h )
            }
            F _ → { ^ @ ! HpackLitResult HpackErr { F HpackBadIndex } }
        }
    } {
        : ! HpackString HpackErr ns ( hpack_decode_string buf cur_off )
        ?? ns {
            T hs → {
                ( string_free name )
                = name . hs value
                = cur_off + cur_off . hs consumed
            }
            F e → { ^ @ ! HpackLitResult HpackErr { F e } }
        }
    }
    : ~ String value ( string_new )
    : ! HpackString HpackErr vs ( hpack_decode_string buf cur_off )
    ?? vs {
        T hs → {
            ( string_free value )
            = value . hs value
            = cur_off + cur_off . hs consumed
        }
        F e → {
            ( string_free name )
            ( string_free value )
            ^ @ ! HpackLitResult HpackErr { F e }
        }
    }
    : ~ HpackDynTable cur dyn
    ? indexing {
        = cur ( hpack_dyn_insert cur
                ( string_data name ) ( string_data value ) )
    } {}
    ^ @ ! HpackLitResult HpackErr {
        T @ HpackLitResult { name value cur - cur_off off }
    }
}

// ── Encoder (literal, no Huffman, no indexing) ───────────────────────
@ hpack_encode_headers ( Vec Header ) headers → ( Vec u ) {
    : i n ( vec_len [Header] headers )
    : ( Vec u ) out ( vec_with_cap [u] * n 32 )
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k n {
        : Header h . hp k
        ( vec_push [u] out # u 0 )
        ( hpack_encode_string out ( string_data . h name ) )
        ( hpack_encode_string out ( string_data . h value ) )
        = k + k 1
    }
    ^ out
}

// ── Huffman decoder (RFC 7541 Appendix B) ────────────────────────────
//
// Brute-force per-symbol match. For each input position scan known
// codes by length (5..30 bits); first match wins because the codes are
// prefix-free. EOS (symbol 256) inside data is a protocol error.

@ __hpack_huffman_decode ( Vec u ) buf i from i length → ! String HpackErr {
    : ~ String out ( string_new )
    : ~ i bit_window 0
    : ~ i bits_avail 0
    : ~ i byte_off from
    : i end + from length
    : *u p ( vec_data [u] buf )
    : ~ b ok T
    : ~ b done F
    ~ & ok ! done {
        ~ & < bits_avail 24 < byte_off end {
            : i b # i . p byte_off
            = bit_window | bit_window << b - 24 bits_avail
            = bits_avail + bits_avail 8
            = byte_off + byte_off 1
        }
        ? <= bits_avail 0 {
            = done T
        } {
            : ~ b matched F
            : ~ i sym 0
            : ~ i used 0
            : ~ i probe_len 5
            ~ & ! matched <= probe_len bits_avail {
                ? > probe_len 30 { = probe_len 31 } {
                    : i probe_bits >> bit_window - 32 probe_len
                    : i found ( __hpack_huffman_sym_for_code probe_bits probe_len )
                    ? >= found 0 {
                        = sym found
                        = used probe_len
                        = matched T
                    } {}
                    = probe_len + probe_len 1
                }
            }
            ? matched {
                ? == sym 256 {
                    = ok F
                } {
                    ( string_push_char out sym )
                    = bit_window << bit_window used
                    = bits_avail - bits_avail used
                }
            } {
                ? >= bits_avail 8 {
                    = ok F
                } {
                    : i pad_mask << - ( __pow2 bits_avail ) 1 - 32 bits_avail
                    : i expected pad_mask
                    : i got & bit_window pad_mask
                    ? != got expected {
                        = ok F
                    } { = done T }
                }
            }
        }
    }
    ? ! ok {
        ( string_free out )
        ^ @ ! String HpackErr { F HpackBadHuffman }
    } {}
    ^ @ ! String HpackErr { T out }
}

// Length-by-length sym lookup. Returns -1 on no match. NURL's `??`
// doesn't accept integer literals so each length-bucket unrolls into
// an if-else cascade. Tedious but deterministic.
@ __hpack_huffman_sym_for_code i code i len → i {
    ? == len 5  { ^ ( __hpack_huffman_l5  code ) } {}
    ? == len 6  { ^ ( __hpack_huffman_l6  code ) } {}
    ? == len 7  { ^ ( __hpack_huffman_l7  code ) } {}
    ? == len 8  { ^ ( __hpack_huffman_l8  code ) } {}
    ? == len 10 { ^ ( __hpack_huffman_l10 code ) } {}
    ? == len 11 { ^ ( __hpack_huffman_l11 code ) } {}
    ? == len 12 { ^ ( __hpack_huffman_l12 code ) } {}
    ? == len 13 { ^ ( __hpack_huffman_l13 code ) } {}
    ? == len 14 { ^ ( __hpack_huffman_l14 code ) } {}
    ? == len 15 { ^ ( __hpack_huffman_l15 code ) } {}
    ? == len 19 { ^ ( __hpack_huffman_l19 code ) } {}
    ? == len 20 { ^ ( __hpack_huffman_l20 code ) } {}
    ? == len 21 { ^ ( __hpack_huffman_l21 code ) } {}
    ? == len 22 { ^ ( __hpack_huffman_l22 code ) } {}
    ? == len 23 { ^ ( __hpack_huffman_l23 code ) } {}
    ? == len 24 { ^ ( __hpack_huffman_l24 code ) } {}
    ? == len 25 { ^ ( __hpack_huffman_l25 code ) } {}
    ? == len 26 { ^ ( __hpack_huffman_l26 code ) } {}
    ? == len 27 { ^ ( __hpack_huffman_l27 code ) } {}
    ? == len 28 { ^ ( __hpack_huffman_l28 code ) } {}
    ? == len 30 { ^ ( __hpack_huffman_l30 code ) } {}
    ^ -1
}

// 5-bit codes: 10 symbols.
@ __hpack_huffman_l5 i c → i {
    ? == c 0  { ^ 48 } {}
    ? == c 1  { ^ 49 } {}
    ? == c 2  { ^ 50 } {}
    ? == c 3  { ^ 97 } {}
    ? == c 4  { ^ 99 } {}
    ? == c 5  { ^ 101 } {}
    ? == c 6  { ^ 105 } {}
    ? == c 7  { ^ 111 } {}
    ? == c 8  { ^ 115 } {}
    ? == c 9  { ^ 116 } {}
    ^ -1
}

// 6-bit codes.
@ __hpack_huffman_l6 i c → i {
    ? == c 20 { ^ 32 } {}
    ? == c 21 { ^ 37 } {}
    ? == c 22 { ^ 45 } {}
    ? == c 23 { ^ 46 } {}
    ? == c 24 { ^ 47 } {}
    ? == c 25 { ^ 51 } {}
    ? == c 26 { ^ 52 } {}
    ? == c 27 { ^ 53 } {}
    ? == c 28 { ^ 54 } {}
    ? == c 29 { ^ 55 } {}
    ? == c 30 { ^ 56 } {}
    ? == c 31 { ^ 57 } {}
    ? == c 32 { ^ 61 } {}
    ? == c 33 { ^ 65 } {}
    ? == c 34 { ^ 95 } {}
    ? == c 35 { ^ 98 } {}
    ? == c 36 { ^ 100 } {}
    ? == c 37 { ^ 102 } {}
    ? == c 38 { ^ 103 } {}
    ? == c 39 { ^ 104 } {}
    ? == c 40 { ^ 108 } {}
    ? == c 41 { ^ 109 } {}
    ? == c 42 { ^ 110 } {}
    ? == c 43 { ^ 112 } {}
    ? == c 44 { ^ 114 } {}
    ? == c 45 { ^ 117 } {}
    ^ -1
}

// 7-bit codes (32 entries: ':', uppercase letters except a few, jkqvwxyz).
@ __hpack_huffman_l7 i c → i {
    ? == c 92  { ^ 58 } {}
    ? == c 93  { ^ 66 } {}
    ? == c 94  { ^ 67 } {}
    ? == c 95  { ^ 68 } {}
    ? == c 96  { ^ 69 } {}
    ? == c 97  { ^ 70 } {}
    ? == c 98  { ^ 71 } {}
    ? == c 99  { ^ 72 } {}
    ? == c 100 { ^ 73 } {}
    ? == c 101 { ^ 74 } {}
    ? == c 102 { ^ 75 } {}
    ? == c 103 { ^ 76 } {}
    ? == c 104 { ^ 77 } {}
    ? == c 105 { ^ 78 } {}
    ? == c 106 { ^ 79 } {}
    ? == c 107 { ^ 80 } {}
    ? == c 108 { ^ 81 } {}
    ? == c 109 { ^ 82 } {}
    ? == c 110 { ^ 83 } {}
    ? == c 111 { ^ 84 } {}
    ? == c 112 { ^ 85 } {}
    ? == c 113 { ^ 86 } {}
    ? == c 114 { ^ 87 } {}
    ? == c 115 { ^ 89 } {}
    ? == c 116 { ^ 106 } {}
    ? == c 117 { ^ 107 } {}
    ? == c 118 { ^ 113 } {}
    ? == c 119 { ^ 118 } {}
    ? == c 120 { ^ 119 } {}
    ? == c 121 { ^ 120 } {}
    ? == c 122 { ^ 121 } {}
    ? == c 123 { ^ 122 } {}
    ^ -1
}

// 8-bit codes.
@ __hpack_huffman_l8 i c → i {
    ? == c 248 { ^ 38 } {}
    ? == c 249 { ^ 42 } {}
    ? == c 250 { ^ 44 } {}
    ? == c 251 { ^ 59 } {}
    ? == c 252 { ^ 88 } {}
    ? == c 253 { ^ 90 } {}
    ^ -1
}

// 10-bit codes.
@ __hpack_huffman_l10 i c → i {
    ? == c 1016 { ^ 33 } {}
    ? == c 1017 { ^ 34 } {}
    ? == c 1018 { ^ 40 } {}
    ? == c 1019 { ^ 41 } {}
    ? == c 1020 { ^ 63 } {}
    ^ -1
}

// 11-bit codes.
@ __hpack_huffman_l11 i c → i {
    ? == c 2042 { ^ 39 } {}
    ? == c 2043 { ^ 43 } {}
    ? == c 2044 { ^ 124 } {}
    ^ -1
}

// 12-bit codes.
@ __hpack_huffman_l12 i c → i {
    ? == c 4090 { ^ 35 } {}
    ? == c 4091 { ^ 62 } {}
    ^ -1
}

// 13-bit codes.
@ __hpack_huffman_l13 i c → i {
    ? == c 8184 { ^ 0 } {}
    ? == c 8185 { ^ 36 } {}
    ? == c 8186 { ^ 64 } {}
    ? == c 8187 { ^ 91 } {}
    ? == c 8188 { ^ 93 } {}
    ? == c 8189 { ^ 126 } {}
    ^ -1
}

// 14-bit codes.
@ __hpack_huffman_l14 i c → i {
    ? == c 16380 { ^ 94 } {}
    ? == c 16381 { ^ 125 } {}
    ^ -1
}

// 15-bit codes.
@ __hpack_huffman_l15 i c → i {
    ? == c 32764 { ^ 60 } {}
    ? == c 32765 { ^ 96 } {}
    ? == c 32766 { ^ 123 } {}
    ^ -1
}

// 19-bit codes.
@ __hpack_huffman_l19 i c → i {
    ? == c 524272 { ^ 92 } {}
    ? == c 524273 { ^ 195 } {}
    ? == c 524274 { ^ 208 } {}
    ^ -1
}

// 20-bit codes.
@ __hpack_huffman_l20 i c → i {
    ? == c 1048550 { ^ 128 } {}
    ? == c 1048551 { ^ 130 } {}
    ? == c 1048552 { ^ 131 } {}
    ? == c 1048553 { ^ 162 } {}
    ? == c 1048554 { ^ 184 } {}
    ? == c 1048555 { ^ 194 } {}
    ? == c 1048556 { ^ 224 } {}
    ? == c 1048557 { ^ 226 } {}
    ^ -1
}

// 21-bit codes.
@ __hpack_huffman_l21 i c → i {
    ? == c 2097116 { ^ 153 } {}
    ? == c 2097117 { ^ 161 } {}
    ? == c 2097118 { ^ 167 } {}
    ? == c 2097119 { ^ 172 } {}
    ? == c 2097120 { ^ 176 } {}
    ? == c 2097121 { ^ 177 } {}
    ? == c 2097122 { ^ 179 } {}
    ? == c 2097123 { ^ 209 } {}
    ? == c 2097124 { ^ 216 } {}
    ? == c 2097125 { ^ 217 } {}
    ? == c 2097126 { ^ 227 } {}
    ? == c 2097127 { ^ 229 } {}
    ? == c 2097128 { ^ 230 } {}
    ^ -1
}

// 22-bit codes (26 entries).
@ __hpack_huffman_l22 i c → i {
    ? == c 4194258 { ^ 129 } {}
    ? == c 4194259 { ^ 132 } {}
    ? == c 4194260 { ^ 133 } {}
    ? == c 4194261 { ^ 134 } {}
    ? == c 4194262 { ^ 136 } {}
    ? == c 4194263 { ^ 146 } {}
    ? == c 4194264 { ^ 154 } {}
    ? == c 4194265 { ^ 156 } {}
    ? == c 4194266 { ^ 160 } {}
    ? == c 4194267 { ^ 163 } {}
    ? == c 4194268 { ^ 164 } {}
    ? == c 4194269 { ^ 169 } {}
    ? == c 4194270 { ^ 170 } {}
    ? == c 4194271 { ^ 173 } {}
    ? == c 4194272 { ^ 178 } {}
    ? == c 4194273 { ^ 181 } {}
    ? == c 4194274 { ^ 185 } {}
    ? == c 4194275 { ^ 186 } {}
    ? == c 4194276 { ^ 187 } {}
    ? == c 4194277 { ^ 189 } {}
    ? == c 4194278 { ^ 190 } {}
    ? == c 4194279 { ^ 196 } {}
    ? == c 4194280 { ^ 198 } {}
    ? == c 4194281 { ^ 228 } {}
    ? == c 4194282 { ^ 232 } {}
    ? == c 4194283 { ^ 233 } {}
    ^ -1
}

// 23-bit codes (29 entries).
@ __hpack_huffman_l23 i c → i {
    ? == c 8388568 { ^ 1 } {}
    ? == c 8388569 { ^ 135 } {}
    ? == c 8388570 { ^ 137 } {}
    ? == c 8388571 { ^ 138 } {}
    ? == c 8388572 { ^ 139 } {}
    ? == c 8388573 { ^ 140 } {}
    ? == c 8388574 { ^ 141 } {}
    ? == c 8388575 { ^ 143 } {}
    ? == c 8388576 { ^ 147 } {}
    ? == c 8388577 { ^ 149 } {}
    ? == c 8388578 { ^ 150 } {}
    ? == c 8388579 { ^ 151 } {}
    ? == c 8388580 { ^ 152 } {}
    ? == c 8388581 { ^ 155 } {}
    ? == c 8388582 { ^ 157 } {}
    ? == c 8388583 { ^ 158 } {}
    ? == c 8388584 { ^ 165 } {}
    ? == c 8388585 { ^ 166 } {}
    ? == c 8388586 { ^ 168 } {}
    ? == c 8388587 { ^ 174 } {}
    ? == c 8388588 { ^ 175 } {}
    ? == c 8388589 { ^ 180 } {}
    ? == c 8388590 { ^ 182 } {}
    ? == c 8388591 { ^ 183 } {}
    ? == c 8388592 { ^ 188 } {}
    ? == c 8388593 { ^ 191 } {}
    ? == c 8388594 { ^ 197 } {}
    ? == c 8388595 { ^ 231 } {}
    ? == c 8388596 { ^ 239 } {}
    ^ -1
}

// 24-bit codes.
@ __hpack_huffman_l24 i c → i {
    ? == c 16777194 { ^ 9 } {}
    ? == c 16777195 { ^ 142 } {}
    ? == c 16777196 { ^ 144 } {}
    ? == c 16777197 { ^ 145 } {}
    ? == c 16777198 { ^ 148 } {}
    ? == c 16777199 { ^ 159 } {}
    ? == c 16777200 { ^ 171 } {}
    ? == c 16777201 { ^ 206 } {}
    ? == c 16777202 { ^ 215 } {}
    ? == c 16777203 { ^ 225 } {}
    ? == c 16777204 { ^ 236 } {}
    ? == c 16777205 { ^ 237 } {}
    ^ -1
}

// 25-bit codes.
@ __hpack_huffman_l25 i c → i {
    ? == c 33554412 { ^ 199 } {}
    ? == c 33554413 { ^ 207 } {}
    ? == c 33554414 { ^ 234 } {}
    ? == c 33554415 { ^ 235 } {}
    ^ -1
}

// 26-bit codes.
@ __hpack_huffman_l26 i c → i {
    ? == c 67108832 { ^ 192 } {}
    ? == c 67108833 { ^ 193 } {}
    ? == c 67108834 { ^ 200 } {}
    ? == c 67108835 { ^ 201 } {}
    ? == c 67108836 { ^ 202 } {}
    ? == c 67108837 { ^ 205 } {}
    ? == c 67108838 { ^ 210 } {}
    ? == c 67108839 { ^ 213 } {}
    ? == c 67108840 { ^ 218 } {}
    ? == c 67108841 { ^ 219 } {}
    ? == c 67108842 { ^ 238 } {}
    ? == c 67108843 { ^ 240 } {}
    ? == c 67108844 { ^ 242 } {}
    ? == c 67108845 { ^ 243 } {}
    ? == c 67108846 { ^ 255 } {}
    ^ -1
}

// 27-bit codes.
@ __hpack_huffman_l27 i c → i {
    ? == c 134217694 { ^ 203 } {}
    ? == c 134217695 { ^ 204 } {}
    ? == c 134217696 { ^ 211 } {}
    ? == c 134217697 { ^ 212 } {}
    ? == c 134217698 { ^ 214 } {}
    ? == c 134217699 { ^ 221 } {}
    ? == c 134217700 { ^ 222 } {}
    ? == c 134217701 { ^ 223 } {}
    ? == c 134217702 { ^ 241 } {}
    ? == c 134217703 { ^ 244 } {}
    ? == c 134217704 { ^ 245 } {}
    ? == c 134217705 { ^ 246 } {}
    ? == c 134217706 { ^ 247 } {}
    ? == c 134217707 { ^ 248 } {}
    ? == c 134217708 { ^ 250 } {}
    ? == c 134217709 { ^ 251 } {}
    ? == c 134217710 { ^ 252 } {}
    ? == c 134217711 { ^ 253 } {}
    ? == c 134217712 { ^ 254 } {}
    ^ -1
}

// 28-bit codes (29 entries — control-character escapes).
@ __hpack_huffman_l28 i c → i {
    ? == c 268435426 { ^ 2 } {}
    ? == c 268435427 { ^ 3 } {}
    ? == c 268435428 { ^ 4 } {}
    ? == c 268435429 { ^ 5 } {}
    ? == c 268435430 { ^ 6 } {}
    ? == c 268435431 { ^ 7 } {}
    ? == c 268435432 { ^ 8 } {}
    ? == c 268435433 { ^ 11 } {}
    ? == c 268435434 { ^ 12 } {}
    ? == c 268435435 { ^ 14 } {}
    ? == c 268435436 { ^ 15 } {}
    ? == c 268435437 { ^ 16 } {}
    ? == c 268435438 { ^ 17 } {}
    ? == c 268435439 { ^ 18 } {}
    ? == c 268435440 { ^ 19 } {}
    ? == c 268435441 { ^ 20 } {}
    ? == c 268435442 { ^ 21 } {}
    ? == c 268435443 { ^ 23 } {}
    ? == c 268435444 { ^ 24 } {}
    ? == c 268435445 { ^ 25 } {}
    ? == c 268435446 { ^ 26 } {}
    ? == c 268435447 { ^ 27 } {}
    ? == c 268435448 { ^ 28 } {}
    ? == c 268435449 { ^ 29 } {}
    ? == c 268435450 { ^ 30 } {}
    ? == c 268435451 { ^ 31 } {}
    ? == c 268435452 { ^ 127 } {}
    ? == c 268435453 { ^ 220 } {}
    ? == c 268435454 { ^ 249 } {}
    ^ -1
}

// 30-bit codes: \n, \r, DEL, EOS.
@ __hpack_huffman_l30 i c → i {
    ? == c 1073741820 { ^ 10 } {}
    ? == c 1073741821 { ^ 13 } {}
    ? == c 1073741822 { ^ 22 } {}
    ? == c 1073741823 { ^ 256 } {}
    ^ -1
}
