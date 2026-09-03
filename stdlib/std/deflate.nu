// stdlib/std/deflate.nu — pure-NURL DEFLATE (RFC 1951) codec + the
// CRC-32 / Adler-32 checksums used by gzip (RFC 1952) and zlib (RFC 1950).
//
// No libz. The decoder is a port of Mark Adler's puff.c reference
// inflater (stored / fixed-Huffman / dynamic-Huffman blocks); the encoder
// emits fixed-Huffman blocks with greedy LZ77 matching (a valid DEFLATE
// stream any inflater reads — including zlib's). The gzip/zlib framing
// wrappers live in stdlib/std/gzip.nu over this core.
//
// Surface:
//   ( inflate ( Vec u ) src )            → !( Vec u ) DeflateErr   raw DEFLATE → bytes
//   ( deflate ( Vec u ) src )            → ( Vec u )               bytes → raw DEFLATE
//   ( crc32   ( Vec u ) data )           → i                       RFC 1952 CRC-32
//   ( crc32_update i crc ( Vec u ) data ) → i                      incremental
//   ( adler32 ( Vec u ) data )           → i                       RFC 1950 Adler-32

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

: | DeflateErr {
    DeflateBadBlock
    DeflateBadCode
    DeflateBadLength
    DeflateBadDist
    DeflateTruncated
    DeflateOther
}

@ deflate_err_name DeflateErr e → s {
    ^ ?? e {
        DeflateBadBlock → `DeflateBadBlock`
        DeflateBadCode → `DeflateBadCode`
        DeflateBadLength → `DeflateBadLength`
        DeflateBadDist → `DeflateBadDist`
        DeflateTruncated → `DeflateTruncated`
        DeflateOther → `DeflateOther`
    }
}

// ── checksums ───────────────────────────────────────────────────────

// Sarwate's byte table: entry b is the CRC of the single byte b, which
// is exactly the 8-iteration inner loop run once per possible byte. 256
// entries × 8 shifts = 2048 steps to build, after which a byte costs one
// lookup instead of eight shift-mask-xor rounds.
@ __crc32_table → ( Vec i ) {
    : ( Vec i ) t ( vec_with_cap [i] 256 )
    : b _l ( vec_set_len [i] t 256 )
    : *i tp ( vec_data [i] t )
    : ~ i b 0
    ~ < b 256 {
        : ~ i c b
        : ~ i k 0
        ~ < k 8 {
            : i mask - 0 & c 1  // -(c & 1) → all-ones when low bit set
            = c ^^ >> c 1 & 3988292384 mask  // 0xEDB88320
            = k + k 1
        }
        = . tp b c
        = b + b 1
    }
    ^ t
}

// CRC-32 (IEEE, reflected, poly 0xEDB88320).
//
// Two implementations of the same function, chosen by input size. The
// bitwise loop runs eight shift-mask-xor rounds per byte and needs no
// setup; the table-driven loop costs 2048 steps to build its table and
// then one lookup per byte. They break even around 300 bytes, so
// anything from 512 up takes the table — and that is where the callers
// that matter live: a gzip member, a tar payload, a PNG chunk, a
// database block. Measured on a 4 KiB block, the table is 7.8x faster
// (2048 + 4096 steps against 32768), and it took an LSM store's point
// reads — 66 % of their cycles were inside this function — down with it.
//
// The small path is kept rather than always building the table because a
// short input (a gzip header, a 4-byte trailer) would otherwise pay
// 2048 steps to checksum 8 bytes. Both paths are the same algorithm and
// produce identical output for every input; std/deflate's own tests and
// tools/crc32_gate.sh check that against an independent implementation.
@ crc32_update i crc0 ( Vec u ) data → i {
    : ~ i crc ^^ crc0 4294967295  // crc ^ 0xFFFFFFFF
    : i n ( vec_len [u] data )
    : *u d ( vec_data [u] data )
    ? < n 512 {
        : ~ i i 0
        ~ < i n {
            = crc ^^ crc # i . d i
            : ~ i k 0
            ~ < k 8 {
                : i mask - 0 & crc 1  // -(crc & 1) → all-ones when low bit set
                = crc ^^ >> crc 1 & 3988292384 mask  // 0xEDB88320
                = k + k 1
            }
            = i + i 1
        }
    } {
        : ( Vec i ) t ( __crc32_table )
        : *i tp ( vec_data [i] t )
        : ~ i i 0
        ~ < i n {
            : i idx & 255 ^^ crc # i . d i
            : i tv . tp idx
            = crc ^^ tv >> crc 8
            = i + i 1
        }
        ( vec_free [i] t )
    }
    ^ & ^^ crc 4294967295 4294967295  // (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
}

@ crc32 ( Vec u ) data → i {
    ^ ( crc32_update 0 data )
}

// ── reusable CRC-32 context ─────────────────────────────────────────
//
// crc32_update above rebuilds its table on every call that is big enough
// to want one. That is the right trade for a caller that checksums one
// payload, and the wrong one for a caller that checksums thousands: a
// database verifying a 4 KiB block per read spends a third of the
// checksum on building the same 256 entries again.
//
// So hold the table: build it once, hand it to every call.
//
//   : Crc32 c ( crc32_ctx )
//   : i sum ( crc32_ctx_hash c block )     // per block, no setup cost
//   ( crc32_ctx_free c )
//
// Same algorithm, same values as crc32 / crc32_update — the context is
// purely about where the table lives.

: Crc32 { ( Vec i ) tbl }

@ crc32_ctx → Crc32 { ^ @ Crc32 { ( __crc32_table ) } }

@ crc32_ctx_free Crc32 c → v { ( vec_free [i] . c tbl ) }

@ crc32_ctx_update Crc32 c i crc0 ( Vec u ) data → i {
    : ~ i crc ^^ crc0 4294967295
    : i n ( vec_len [u] data )
    : *u d ( vec_data [u] data )
    : *i tp ( vec_data [i] . c tbl )
    : ~ i i 0
    ~ < i n {
        : i idx & 255 ^^ crc # i . d i
        : i tv . tp idx
        = crc ^^ tv >> crc 8
        = i + i 1
    }
    ^ & ^^ crc 4294967295 4294967295
}

@ crc32_ctx_hash Crc32 c ( Vec u ) data → i {
    ^ ( crc32_ctx_update c 0 data )
}

@ adler32 ( Vec u ) data → i {
    : ~ i a 1
    : ~ i b 0
    : i n ( vec_len [u] data )
    : *u d ( vec_data [u] data )
    : ~ i i 0
    ~ < i n {
        = a % + a # i . d i 65521
        = b % + b a 65521
        = i + i 1
    }
    ^ | << b 16 a
}

// ── small Vec[i] helpers (Huffman tables) ───────────────────────────

@ __df_zeros i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

@ __df_get ( Vec i ) v i idx → i {
    : *i p ( vec_data [i] v )
    ^ # i . p idx
}

@ __df_set ( Vec i ) v i idx i val → v {
    : *i p ( vec_data [i] v )
    = . p idx val
}

// ── inflate ─────────────────────────────────────────────────────────

: InflState {
    * u data
    i len
    i pos
    i bitbuf
    i bitcnt
    ( Vec u ) out
    i err
    i max_out  // stop (err 6) once `out` grows past this; 0 = unlimited
}

// The decompression-bomb guard, checked after every emitted byte run:
// 1 KB of DEFLATE can expand to ~1 MB, so a cap enforced only after the
// fact is no cap at all — the memory is already gone.
@ __infl_over_cap * InflState st → b {
    ? <= . st max_out 0 { ^ F } {}
    ? > ( vec_len [u] . st out ) . st max_out { = . st err 6 ^ T } {}
    ^ F
}

: Huff {
    ( Vec i ) count  // count[len] = number of codes of that length (0..15)
    ( Vec i ) symbol  // symbols sorted by (length, value)
}

// Read `need` bits LSB-first. Sets st.err on input underflow.
@ __infl_bits * InflState st i need → i {
    : ~ i val . st bitbuf
    : ~ i cnt . st bitcnt
    ~ < cnt need {
        ? >= . st pos . st len { = . st err 5 ^ 0 } {}
        : *u d . st data
        = val | val << # i . d . st pos cnt
        = . st pos + . st pos 1
        = cnt + cnt 8
    }
    = . st bitbuf >> val need
    = . st bitcnt - cnt need
    ^ & val - << 1 need 1
}

// Decode one symbol with Huffman table h (puff.c algorithm).
@ __infl_decode * InflState st Huff h → i {
    : ~ i code 0
    : ~ i first 0
    : ~ i index 0
    : ~ i len 1
    : ~ i ret -1
    : ~ b done F
    : *i cnt ( vec_data [i] . h count )
    : *i sym ( vec_data [i] . h symbol )
    ~ & ! done <= len 15 {
        = code | code ( __infl_bits st 1 )
        : i count # i . cnt len
        ? < - code count first {
            = ret # i . sym + index - code first
            = done T
        } {
            = index + index count
            = first + first count
            = first << first 1
            = code << code 1
            = len + len 1
        }
    }
    ^ ret
}

// Build a Huffman table from a list of code lengths.
@ __infl_construct ( Vec i ) lengths i n → Huff {
    : ( Vec i ) count ( __df_zeros 16 )
    : ~ i s 0
    ~ < s n {
        : i L ( __df_get lengths s )
        ( __df_set count L + ( __df_get count L ) 1 )
        = s + s 1
    }
    : ( Vec i ) offs ( __df_zeros 16 )
    : ~ i L 1
    ~ < L 15 {
        ( __df_set offs + L 1 + ( __df_get offs L ) ( __df_get count L ) )
        = L + L 1
    }
    : ( Vec i ) symbol ( __df_zeros ? > n 1 n 1 )
    = s 0
    ~ < s n {
        : i ln ( __df_get lengths s )
        ? != ln 0 {
            ( __df_set symbol ( __df_get offs ln ) s )
            ( __df_set offs ln + ( __df_get offs ln ) 1 )
        } {}
        = s + s 1
    }
    ( vec_free [i] offs )
    ^ @ Huff { count symbol }
}

// length base + extra-bit tables for codes 257..285 (index 0..28).
@ __infl_lenbase → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( __df_push_list v 3 4 5 6 7 8 9 10 11 13 )
    ( __df_push_list v 15 17 19 23 27 31 35 43 51 59 )
    ( __df_push_list v 67 83 99 115 131 163 195 227 258 0 )
    ^ v
}

@ __infl_lenext → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( __df_push_list v 0 0 0 0 0 0 0 0 1 1 )
    ( __df_push_list v 1 1 2 2 2 2 3 3 3 3 )
    ( __df_push_list v 4 4 4 4 5 5 5 5 0 0 )
    ^ v
}

@ __infl_distbase → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( __df_push_list v 1 2 3 4 5 7 9 13 17 25 )
    ( __df_push_list v 33 49 65 97 129 193 257 385 513 769 )
    ( __df_push_list v 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577 )
    ^ v
}

@ __infl_distext → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( __df_push_list v 0 0 0 0 1 1 2 2 3 3 )
    ( __df_push_list v 4 4 5 5 6 6 7 7 8 8 )
    ( __df_push_list v 9 9 10 10 11 11 12 12 13 13 )
    ^ v
}

@ __df_push_list ( Vec i ) v i a i b i c i d i e i f i g i h i ii i j → v {
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ( vec_push [i] v e ) ( vec_push [i] v f ) ( vec_push [i] v g ) ( vec_push [i] v h )
    ( vec_push [i] v ii ) ( vec_push [i] v j )
}

// Decode a Huffman-coded block body (fixed or dynamic) into st.out.
@ __infl_codes * InflState st Huff lencode Huff distcode
( Vec i ) lenbase ( Vec i ) lenext ( Vec i ) distbase ( Vec i ) distext → v {
    : ~ b done F
    ~ & ! done == . st err 0 {
        ? ( __infl_over_cap st ) { = done T } {}
        : i sym ( __infl_decode st lencode )
        ? < sym 0 { = . st err 2 } {
            ? == sym 256 { = done T } {
                ? < sym 256 {
                    ( vec_push [u] . st out # u sym )
                } {
                    // length/distance back-reference
                    : i li - sym 257
                    ? >= li 29 { = . st err 2 } {
                        : i length + ( __df_get lenbase li ) ( __infl_bits st ( __df_get lenext li ) )
                        : i dsym ( __infl_decode st distcode )
                        ? | < dsym 0 >= dsym 30 { = . st err 4 } {
                            : i dist + ( __df_get distbase dsym ) ( __infl_bits st ( __df_get distext dsym ) )
                            : i outlen ( vec_len [u] . st out )
                            ? > dist outlen { = . st err 4 } {
                                : ~ i k 0
                                ~ < k length {
                                    : i srcidx - ( vec_len [u] . st out ) dist
                                    : *u op ( vec_data [u] . st out )
                                    ( vec_push [u] . st out # u . op srcidx )
                                    = k + k 1
                                }
                            }
                        }
                    }
                } } }
    }
}

// Fixed Huffman tables (RFC 1951 §3.2.6).
@ __infl_fixed_lit → Huff {
    : ( Vec i ) lengths ( vec_with_cap [i] 288 )
    : ~ i k 0
    ~ < k 144 { ( vec_push [i] lengths 8 ) = k + k 1 }
    ~ < k 256 { ( vec_push [i] lengths 9 ) = k + k 1 }
    ~ < k 280 { ( vec_push [i] lengths 7 ) = k + k 1 }
    ~ < k 288 { ( vec_push [i] lengths 8 ) = k + k 1 }
    : Huff h ( __infl_construct lengths 288 )
    ( vec_free [i] lengths )
    ^ h
}

@ __infl_fixed_dist → Huff {
    : ( Vec i ) lengths ( vec_with_cap [i] 30 )
    : ~ i k 0
    ~ < k 30 { ( vec_push [i] lengths 5 ) = k + k 1 }
    : Huff h ( __infl_construct lengths 30 )
    ( vec_free [i] lengths )
    ^ h
}

// Dynamic Huffman: read the two tables, then decode the block body.
@ __infl_dynamic * InflState st
( Vec i ) lenbase ( Vec i ) lenext ( Vec i ) distbase ( Vec i ) distext → v {
    : i hlit + 257 ( __infl_bits st 5 )
    : i hdist + 1 ( __infl_bits st 5 )
    : i hclen + 4 ( __infl_bits st 4 )
    ? != . st err 0 { ^ v } {}

    // Code-length code lengths in the spec's permuted order.
    : ( Vec i ) order ( vec_new [i] )
    ( __df_push_list order 16 17 18 0 8 7 9 6 10 5 )
    ( __df_push_list order 11 4 12 3 13 2 14 1 15 0 )  // last 0 is padding (19 entries used)
    : ( Vec i ) cllen ( __df_zeros 19 )
    : ~ i i 0
    ~ < i hclen {
        ( __df_set cllen ( __df_get order i ) ( __infl_bits st 3 ) )
        = i + i 1
    }
    : Huff clcode ( __infl_construct cllen 19 )

    // Read hlit+hdist code lengths using the code-length Huffman table.
    : i total + hlit hdist
    : ( Vec i ) lengths ( __df_zeros total )
    : ~ i idx 0
    ~ & < idx total == . st err 0 {
        : i sym ( __infl_decode st clcode )
        ? < sym 0 { = . st err 2 } {
            ? < sym 16 {
                ( __df_set lengths idx sym )
                = idx + idx 1
            } {
                : ~ i rep 0
                : ~ i val 0
                ? == sym 16 {
                    ? == idx 0 { = . st err 2 } { = val ( __df_get lengths - idx 1 ) }
                    = rep + 3 ( __infl_bits st 2 )
                } {
                    ? == sym 17 { = rep + 3 ( __infl_bits st 3 ) } {
                        = rep + 11 ( __infl_bits st 7 )
                    } }
                : ~ i r 0
                ~ & < r rep < idx total {
                    ( __df_set lengths idx val )
                    = idx + idx 1
                    = r + r 1
                }
            } }
    }

    ? == . st err 0 {
        // Split into lit/len and dist length lists.
        : ( Vec i ) litlen ( __df_zeros hlit )
        : ( Vec i ) distlen ( __df_zeros hdist )
        = i 0
        ~ < i hlit { ( __df_set litlen i ( __df_get lengths i ) ) = i + i 1 }
        = i 0
        ~ < i hdist { ( __df_set distlen i ( __df_get lengths + i hlit ) ) = i + i 1 }
        : Huff lencode ( __infl_construct litlen hlit )
        : Huff distcode ( __infl_construct distlen hdist )
        ( __infl_codes st lencode distcode lenbase lenext distbase distext )
        ( vec_free [i] litlen ) ( vec_free [i] distlen )
        ( __df_huff_free lencode ) ( __df_huff_free distcode )
    } {}

    ( vec_free [i] order ) ( vec_free [i] cllen ) ( vec_free [i] lengths )
    ( __df_huff_free clcode )
}

@ __df_huff_free Huff h → v {
    ( vec_free [i] . h count )
    ( vec_free [i] . h symbol )
}

// Drive the block loop over st (data/out preset). `partial` != 0 stops
// cleanly when the input is exhausted at a block boundary (streaming /
// sync-flush mode) instead of erroring on the missing BFINAL bit.
@ __inflate_run * InflState st i partial → v {
    : ( Vec i ) lenbase ( __infl_lenbase )
    : ( Vec i ) lenext ( __infl_lenext )
    : ( Vec i ) distbase ( __infl_distbase )
    : ( Vec i ) distext ( __infl_distext )

    : ~ b last F
    ~ & ! last == . st err 0 {
        ? & != partial 0 & >= . st pos . st len == . st bitcnt 0 {
            = last T
        } {
            : i bfinal ( __infl_bits st 1 )
            : i btype ( __infl_bits st 2 )
            = last != bfinal 0
            ? != . st err 0 {} {
                ? == btype 0 {
                    // Stored: align to byte, read LEN/NLEN, copy.
                    = . st bitbuf 0
                    = . st bitcnt 0
                    ? > + . st pos 4 . st len { = . st err 5 } {
                        : *u d . st data
                        : i lo # i . d . st pos
                        : i hi # i . d + . st pos 1
                        : i blen | lo << hi 8
                        = . st pos + . st pos 4
                        ? > + . st pos blen . st len { = . st err 5 } {
                            : ~ i k 0
                            ~ < k blen {
                                ( vec_push [u] . st out # u . d + . st pos k )
                                = k + k 1
                            }
                            = . st pos + . st pos blen
                            : b _cap ( __infl_over_cap st )
                        }
                    }
                } {
                    ? == btype 1 {
                        : Huff lc ( __infl_fixed_lit )
                        : Huff dc ( __infl_fixed_dist )
                        ( __infl_codes st lc dc lenbase lenext distbase distext )
                        ( __df_huff_free lc ) ( __df_huff_free dc )
                    } {
                        ? == btype 2 {
                            ( __infl_dynamic st lenbase lenext distbase distext )
                        } {
                            = . st err 1
                        } } } }
        }
    }

    ( vec_free [i] lenbase ) ( vec_free [i] lenext )
    ( vec_free [i] distbase ) ( vec_free [i] distext )
}

// Inflate a complete raw DEFLATE stream into bytes.
@ inflate ( Vec u ) src → !( Vec u ) DeflateErr {
    ^ ( inflate_max src 0 )
}

// inflate with an output cap: decoding stops with DeflateBadLength as
// soon as the output would exceed `max_out` bytes (0 = unlimited) — the
// guard against a decompression bomb, enforced while decoding, not after.
@ inflate_max ( Vec u ) src i max_out → !( Vec u ) DeflateErr {
    : *InflState st ( nurl_alloc Z InflState )
    = . st data ( vec_data [u] src )
    = . st len ( vec_len [u] src )
    = . st pos 0
    = . st bitbuf 0
    = . st bitcnt 0
    = . st out ( vec_new [u] )
    = . st err 0
    = . st max_out max_out

    ( __inflate_run st 0 )

    : i err . st err
    : ( Vec u ) out . st out
    ( nurl_free # s st )

    ? != err 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) DeflateErr { F ( __df_err err ) }
    } {}
    ^ @ !( Vec u ) DeflateErr { T out }
}

// Streaming inflate for permessage-deflate (RFC 7692) context-takeover:
// decode `input` (a sync-flush-terminated block) with `history` as the
// LZ77 window, appending decoded bytes onto `history` in place. Returns a
// fresh Vec of just the newly-decoded suffix. `history` is trimmed to the
// last 32 KiB (the maximum back-reference distance) so a long-lived
// connection stays bounded. max_out (>0) caps the per-message output.
@ inflate_stream ( Vec u ) history ( Vec u ) input i max_out → !( Vec u ) DeflateErr {
    : i oldlen ( vec_len [u] history )
    : *InflState st ( nurl_alloc Z InflState )
    = . st data ( vec_data [u] input )
    = . st len ( vec_len [u] input )
    = . st pos 0
    = . st bitbuf 0
    = . st bitcnt 0
    = . st out history
    = . st err 0
    = . st max_out ? > max_out 0 + oldlen max_out 0

    ( __inflate_run st 1 )

    : i err . st err
    ( nurl_free # s st )
    ? != err 0 { ^ @ !( Vec u ) DeflateErr { F ( __df_err err ) } } {}

    : i newlen ( vec_len [u] history )
    : i produced - newlen oldlen
    ? & > max_out 0 > produced max_out {
        ^ @ !( Vec u ) DeflateErr { F DeflateBadLength }
    } {}

    : ( Vec u ) suffix ( vec_with_cap [u] ? > produced 1 produced 1 )
    ? > produced 0 {
        : *u hp ( vec_data [u] history )
        ( bytes_extend_raw suffix # s + # i hp oldlen produced )
    } {}

    // Trim the window to the last 32 KiB.
    ? > newlen 32768 {
        : *u hp ( vec_data [u] history )
        ( nurl_memmove hp # *u + # i hp - newlen 32768 32768 )
        : b _t ( vec_set_len [u] history 32768 )
    } {}

    ^ @ !( Vec u ) DeflateErr { T suffix }
}

@ __df_err i e → DeflateErr {
    ? == e 1 { ^ # DeflateErr DeflateBadBlock } {}
    ? == e 2 { ^ # DeflateErr DeflateBadCode } {}
    ? == e 4 { ^ # DeflateErr DeflateBadDist } {}
    ? == e 5 { ^ # DeflateErr DeflateTruncated } {}
    ? == e 6 { ^ # DeflateErr DeflateBadLength } {}
    ^ # DeflateErr DeflateOther
}

// ── deflate (encoder: fixed Huffman + greedy LZ77) ──────────────────

: BitW {
    ( Vec u ) out
    i bitbuf
    i bitcnt
}

// Emit `n` bits of `val` LSB-first (used for header fields + extra bits).
@ __df_bits * BitW w i val i n → v {
    = . w bitbuf | . w bitbuf << & val - << 1 n 1 . w bitcnt
    = . w bitcnt + . w bitcnt n
    ~ >= . w bitcnt 8 {
        ( vec_push [u] . w out # u & . w bitbuf 255 )
        = . w bitbuf >> . w bitbuf 8
        = . w bitcnt - . w bitcnt 8
    }
}

// Emit an `n`-bit Huffman code MSB-first (DEFLATE packs codes high-bit
// first; our bit writer is LSB-first, so reverse the code's bits).
@ __df_huff * BitW w i code i n → v {
    : ~ i rev 0
    : ~ i k 0
    ~ < k n { = rev | << rev 1 & >> code k 1 = k + k 1 }
    ( __df_bits w rev n )
}

@ __df_flush * BitW w → v {
    ? > . w bitcnt 0 {
        ( vec_push [u] . w out # u & . w bitbuf 255 )
        = . w bitbuf 0
        = . w bitcnt 0
    } {}
}

// Emit a literal byte or a fixed-Huffman lit/len symbol (incl. EOB 256).
@ __df_emit_sym * BitW w i sym → v {
    ? <= sym 143 { ( __df_huff w + 48 sym 8 ) } {
        ? <= sym 255 { ( __df_huff w + 400 - sym 144 9 ) } {
            ? <= sym 279 { ( __df_huff w - sym 256 7 ) } {
                ( __df_huff w + 192 - sym 280 8 )
            } } }
}

@ __df_fill i val i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v val ) = k + k 1 }
    ^ v
}

@ __df_hash * u d i i → i {
    ^ & ^^ ^^ << # i . d i 10 << # i . d + i 1 5 # i . d + i 2 32767
}

@ __df_matchlen * u d i pos i cur i n → i {
    : i maxlen ? < - n pos 258 - n pos 258
    : ~ i l 0
    ~ & < l maxlen == # i . d + cur l # i . d + pos l { = l + l 1 }
    ^ l
}

// Find the length symbol index (0..28) for a match length 3..258.
@ __df_len_sym ( Vec i ) lenbase i length → i {
    : ~ i li 28
    : ~ b done F
    : ~ i k 0
    ~ & ! done < k 29 {
        ? & >= length ( __df_get lenbase k ) | == k 28 < length ( __df_get lenbase + k 1 ) {
            = li k = done T
        } {}
        = k + k 1
    }
    ^ li
}

@ __df_dist_sym ( Vec i ) distbase i dist → i {
    : ~ i ds 29
    : ~ b done F
    : ~ i k 0
    ~ & ! done < k 30 {
        ? & >= dist ( __df_get distbase k ) | == k 29 < dist ( __df_get distbase + k 1 ) {
            = ds k = done T
        } {}
        = k + k 1
    }
    ^ ds
}

@ __df_emit_match * BitW w i length i dist
( Vec i ) lenbase ( Vec i ) lenext ( Vec i ) distbase ( Vec i ) distext → v {
    : i li ( __df_len_sym lenbase length )
    ( __df_emit_sym w + 257 li )
    : i le ( __df_get lenext li )
    ? > le 0 { ( __df_bits w - length ( __df_get lenbase li ) le ) } {}
    : i ds ( __df_dist_sym distbase dist )
    ( __df_huff w ds 5 )
    : i de ( __df_get distext ds )
    ? > de 0 { ( __df_bits w - dist ( __df_get distbase ds ) de ) } {}
}

// Emit one fixed-Huffman block for `src[start..]` into the bit writer
// (header with the given BFINAL, greedy-LZ77 body, end-of-block symbol).
// Positions [0, start) form a preset dictionary: their hashes are seeded
// so emitted matches may back-reference into them (permessage-deflate
// context takeover), but no symbols are emitted for them.
@ __df_lz77_block * BitW w ( Vec u ) src i bfinal i start → v {
    : i n ( vec_len [u] src )
    : *u d ( vec_data [u] src )

    : ( Vec i ) lenbase ( __infl_lenbase )
    : ( Vec i ) lenext ( __infl_lenext )
    : ( Vec i ) distbase ( __infl_distbase )
    : ( Vec i ) distext ( __infl_distext )

    ( __df_bits w bfinal 1 )
    ( __df_bits w 1 2 )  // BTYPE=01 (fixed Huffman)

    : ( Vec i ) head ( __df_fill -1 32768 )
    : ( Vec i ) prev ( __df_fill -1 ? > n 1 n 1 )

    // Seed the dictionary region [0, start) into the hash chains.
    : ~ i si 0
    ~ < si start {
        ? <= si - n 3 {
            : i sh ( __df_hash d si )
            ( __df_set prev si ( __df_get head sh ) )
            ( __df_set head sh si )
        } {}
        = si + si 1
    }

    : ~ i i start
    ~ < i n {
        ? <= i - n 3 {
            : i h ( __df_hash d i )
            : i cand ( __df_get head h )
            : ~ i bestlen 0
            : ~ i bestdist 0
            : ~ i chain 0
            : ~ i c cand
            ~ & >= c 0 < chain 128 {
                : i dist - i c
                ? > dist 32768 { = c -1 } {
                    : i ml ( __df_matchlen d i c n )
                    ? > ml bestlen { = bestlen ml = bestdist dist } {}
                    = c ( __df_get prev c )
                    = chain + chain 1
                }
            }
            ( __df_set prev i cand )
            ( __df_set head h i )
            ? >= bestlen 3 {
                ( __df_emit_match w bestlen bestdist lenbase lenext distbase distext )
                : ~ i k 1
                ~ & < k bestlen <= + i k - n 3 {
                    : i hk ( __df_hash d + i k )
                    ( __df_set prev + i k ( __df_get head hk ) )
                    ( __df_set head hk + i k )
                    = k + k 1
                }
                = i + i bestlen
            } {
                ( __df_emit_sym w # i . d i )
                = i + i 1
            }
        } {
            ( __df_emit_sym w # i . d i )
            = i + i 1
        }
    }

    ( __df_emit_sym w 256 )  // end of block
    ( vec_free [i] lenbase ) ( vec_free [i] lenext )
    ( vec_free [i] distbase ) ( vec_free [i] distext )
    ( vec_free [i] head ) ( vec_free [i] prev )
}

// Compress bytes into a complete raw DEFLATE stream (single final block).
@ deflate ( Vec u ) src → ( Vec u ) {
    : *BitW w ( nurl_alloc Z BitW )
    = . w out ( vec_new [u] )
    = . w bitbuf 0
    = . w bitcnt 0
    ( __df_lz77_block w src 1 0 )
    ( __df_flush w )
    : ( Vec u ) out . w out
    ( nurl_free # s w )
    ^ out
}

// Compress `msg` as a non-final fixed block followed by a sync-flush
// (empty stored block) — the shape RFC 7692 permessage-deflate expects;
// output ends with the 00 00 FF FF marker. `dict` is the preceding
// uncompressed window (context takeover): pass an empty Vec for an
// independent per-message window.
@ deflate_block_dict ( Vec u ) dict ( Vec u ) msg → ( Vec u ) {
    : i dlen ( vec_len [u] dict )
    : ( Vec u ) combined ( vec_new [u] )
    ? > dlen 0 { ( bytes_extend_bytes combined dict ) } {}
    ( bytes_extend_bytes combined msg )

    : *BitW w ( nurl_alloc Z BitW )
    = . w out ( vec_new [u] )
    = . w bitbuf 0
    = . w bitcnt 0
    ( __df_lz77_block w combined 0 dlen )
    // Sync flush: empty stored block (BFINAL=0, BTYPE=00), byte-align, then
    // LEN=0x0000 / NLEN=0xFFFF.
    ( __df_bits w 0 1 )
    ( __df_bits w 0 2 )
    ( __df_flush w )
    ( vec_push [u] . w out # u 0 )
    ( vec_push [u] . w out # u 0 )
    ( vec_push [u] . w out # u 255 )
    ( vec_push [u] . w out # u 255 )
    : ( Vec u ) out . w out
    ( vec_free [u] combined )
    ( nurl_free # s w )
    ^ out
}

@ deflate_block ( Vec u ) src → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) r ( deflate_block_dict empty src )
    ( vec_free [u] empty )
    ^ r
}
