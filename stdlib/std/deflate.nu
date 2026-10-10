// stdlib/std/deflate.nu — pure-NURL DEFLATE (RFC 1951) codec + the
// CRC-32 / Adler-32 checksums used by gzip (RFC 1952) and zlib (RFC 1950).
//
// No libz. The decoder follows Mark Adler's puff.c reference inflater
// (stored / fixed-Huffman / dynamic-Huffman blocks), except that a code
// of up to 9 bits decodes with one table lookup; puff.c's bit-at-a-time
// canonical walk remains for longer codes. The encoder emits fixed-Huffman
// blocks with greedy LZ77 matching (a valid DEFLATE stream any inflater
// reads — including zlib's). The gzip/zlib framing wrappers live in
// stdlib/ext/compress.nu over this core.
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
    DeflateLimit
}

@ deflate_err_name DeflateErr e → s {
    ^ ?? e {
        DeflateBadBlock → `DeflateBadBlock`
        DeflateBadCode → `DeflateBadCode`
        DeflateBadLength → `DeflateBadLength`
        DeflateBadDist → `DeflateBadDist`
        DeflateTruncated → `DeflateTruncated`
        DeflateOther → `DeflateOther`
        DeflateLimit → `DeflateLimit`
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

// Slicing-by-8 (Kounavis & Berry): T0 is Sarwate's table above and
// Tk[b] = (Tk-1[b] >> 8) ^ T0[Tk-1[b] & 255] — the CRC of byte b followed by
// k zero bytes — so eight input bytes fold into the CRC through eight
// independent lookups instead of eight dependent ones. 8 × 256 u32 entries,
// 8 KiB, built once per process and shared (publish-once slot 7, the
// registry is in stdlib/std/tls_server.nu).
: ~ i g_crc32_tab8 0

& `c` @ nurl_once_slot i id i candidate → i

@ __crc32_tab8_build → ( Vec u32 ) {
    : ( Vec i ) t0 ( __crc32_table )
    : *i t0p ( vec_data [i] t0 )
    : ( Vec u32 ) t ( vec_with_cap [u32] 2048 )
    : b _l ( vec_set_len [u32] t 2048 )
    : *u32 tp ( vec_data [u32] t )
    : ~ i j 0
    ~ < j 256 { = . tp j # u32 . t0p j = j + j 1 }
    ~ < j 2048 {
        : i prev # i . tp - j 256
        = . tp j # u32 ^^ >> prev 8 . t0p & prev 255
        = j + j 1
    }
    ^ t
}

@ __crc32_tab8 → ( Vec u32 ) {
    ? == g_crc32_tab8 0 {
        : ( Vec u32 ) t ( __crc32_tab8_build )
        : i won ( nurl_once_slot 7 # i . t ctl )
        // The winner lives for the rest of the program, through the global.
        ? == won # i . t ctl { ( mem_forget t ) } {}
        = g_crc32_tab8 won
    } {}
    ^ @ ( Vec u32 ) { # s g_crc32_tab8 }
}

// CRC-32 (IEEE, reflected, poly 0xEDB88320).
//
// Two implementations of the same function, chosen by input size. The
// bitwise loop runs eight shift-mask-xor rounds per byte and needs no
// table; slicing-by-8 then takes eight bytes per step through the shared
// tables. The tables are built once per process, so the cut-over only
// keeps a short input (a gzip header, a 4-byte trailer) from touching
// 8 KiB of table for a few bytes. Both paths are the same function and
// produce identical output for every input; std/deflate's own tests and
// tools/crc32_gate.sh check that against an independent implementation.
@ crc32_update i crc0 ( Vec u ) data → i {
    : ~ i crc ^^ crc0 4294967295  // crc ^ 0xFFFFFFFF
    : i n ( vec_len [u] data )
    : *u d ( vec_data [u] data )
    : ~ i i 0
    ? >= n 64 {
        : ( Vec u32 ) tab ( __crc32_tab8 )
        : *u32 t ( vec_data [u32] tab )
        ~ <= + i 8 n {
            // The low word folds the running CRC in; the high word rides
            // along. Byte k of the eight is followed by 7 − k more, so it
            // goes through T(7 − k).
            : i lo ^^ crc | | | # i . d i << # i . d + i 1 8 << # i . d + i 2 16 << # i . d + i 3 24
            : i hi | | | # i . d + i 4 << # i . d + i 5 8 << # i . d + i 6 16 << # i . d + i 7 24
            : i x0 ^^ # i . t + 1792 & lo 255 # i . t + 1536 & >> lo 8 255
            : i x1 ^^ # i . t + 1280 & >> lo 16 255 # i . t + 1024 >> lo 24
            : i x2 ^^ # i . t + 768 & hi 255 # i . t + 512 & >> hi 8 255
            : i x3 ^^ # i . t + 256 & >> hi 16 255 # i . t >> hi 24
            = crc ^^ ^^ x0 x1 ^^ x2 x3
            = i + i 8
        }
        ~ < i n {
            = crc ^^ # i . t & 255 ^^ crc # i . d i >> crc 8
            = i + i 1
        }
    } {
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
    }
    ^ & ^^ crc 4294967295 4294967295  // (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
}

@ crc32 ( Vec u ) data → i {
    ^ ( crc32_update 0 data )
}

// ── reusable CRC-32 context ─────────────────────────────────────────
//
// Kept for its callers: a context once carried the byte table a caller
// checksumming thousands of blocks did not want rebuilt per call. The
// tables are process-wide now (__crc32_tab8), so a context holds nothing
// a call needs and an update is crc32_update.
//
// The table goes with `c` (a struct holding a Vec, dropped by its owner).

: Crc32 { ( Vec i ) tbl }

@ crc32_ctx → Crc32 { ^ @ Crc32 { ( vec_new [i] ) } }

@ crc32_ctx_update Crc32 c i crc0 ( Vec u ) data → i {
    ^ ( crc32_update crc0 data )
}

@ crc32_ctx_hash Crc32 c ( Vec u ) data → i {
    ^ ( crc32_ctx_update c 0 data )
}

// Adler-32 (RFC 1950 §8.2). The two sums are reduced mod 65521 once per
// MiB rather than once per byte: from below 65521, a MiB of 255s takes b
// to at most 65520·(2^20 + 1) + 255·2^20·(2^20 + 1)/2 < 2^48, nowhere near
// an i64's 2^63 — so the inner loop is two adds a byte.
@ adler32 ( Vec u ) data → i {
    : ~ i a 1
    : ~ i b 0
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i end ? < - n off 1048576 n + off 1048576
        : ~ i i off
        ~ < i end {
            = a + a # i ( vec_at [u] data i )
            = b + b a
            = i + i 1
        }
        = a % a 65521
        = b % b 65521
        = off end
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
    i err
    i max_out  // exact bound; -1 = unlimited
    i window  // maximum allowed back-reference distance
}

// Check before allocation/emission, including whole stored blocks and
// match runs. Subtraction avoids overflowing on a very large caller cap.
@ __infl_room inout InflState st ( Vec u ) out i amount → b {
    ? < . st max_out 0 { ^ T } {}
    ? > amount - . st max_out ( vec_len [u] out ) {
        = . st err 6
        ^ F
    } {}
    ^ T
}

: Huff {
    ( Vec i ) count  // count[len] = number of codes of that length (0..15)
    ( Vec i ) symbol  // symbols sorted by (length, value)
    ( Vec i ) fast  // 2^9 entries by the next 9 input bits: sym·16 + length, 0 = a longer code
}

// Codes up to this many bits decode with one lookup in Huff.fast; a longer
// one (rare — the encoder gives them to rare symbols) takes the canonical
// bit-at-a-time walk. 9 covers every fixed-Huffman code.
@ __INFL_FAST_BITS → i { ^ 9 }

// Top the bit buffer up from the input, a byte at a time, while it has
// room: at most 56 live bits, so bit 63 stays clear and the arithmetic
// `>>` that consumes bits never drags a sign in. 48+ bits is a whole
// length/distance pair (15 + 5 + 15 + 13).
@ __infl_fill inout InflState st → v {
    : ~ i val . st bitbuf
    : ~ i cnt . st bitcnt
    : ~ i pos . st pos
    : i len . st len
    : *u d . st data
    ~ & <= cnt 48 < pos len {
        = val | val << # i . d pos cnt
        = pos + pos 1
        = cnt + cnt 8
    }
    = . st bitbuf val
    = . st bitcnt cnt
    = . st pos pos
}

// Read `need` bits LSB-first. Sets st.err on input underflow.
@ __infl_bits inout InflState st i need → i {
    ? != . st err 0 { ^ 0 } {}
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

// Decode one symbol with Huffman table h: one lookup in h.fast when the
// next code is at most __INFL_FAST_BITS long and its bits are all in, else
// the canonical walk below (puff.c's algorithm), which also reports a
// truncated or invalid code exactly as it always did.
@ __infl_decode inout InflState st Huff h → i {
    ? != . st err 0 { ^ -1 } {}
    ? < . st bitcnt 15 { ( __infl_fill st ) } {}
    : *i fp ( vec_data [i] . h fast )
    : i e . fp & . st bitbuf 511
    : i el & e 15
    ? & != el 0 <= el . st bitcnt {
        = . st bitbuf >> . st bitbuf el
        = . st bitcnt - . st bitcnt el
        ^ >> e 4
    } {}
    ^ ( __infl_decode_slow st h )
}

@ __infl_decode_slow inout InflState st Huff h → i {
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
        ? != . st err 0 { ^ -1 } {}
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
    // The fast table. Canonical codes are handed out in (length, symbol)
    // order, which is `symbol`'s order; DEFLATE sends a code's bits
    // most-significant first into an LSB-first stream, so a code of length
    // L reversed is the low L bits of the buffer, and it owns every entry
    // whose low L bits match — every 2^L-th from there. An oversubscribed
    // length list writes past its own codes; __infl_huff_valid rejects
    // such a table before any symbol is decoded with it.
    : ( Vec i ) fast ( __df_zeros 512 )
    : *i fp ( vec_data [i] fast )
    : *i cp ( vec_data [i] count )
    : *i sp ( vec_data [i] symbol )
    : ~ i code 0
    : ~ i idx 0
    : ~ i bits 1
    ~ <= bits ( __INFL_FAST_BITS ) {
        : i cnt . cp bits
        : ~ i j 0
        ~ < j cnt {
            : ~ i rev 0
            : ~ i b 0
            ~ < b bits { = rev | << rev 1 & >> code b 1 = b + b 1 }
            ? < rev 512 {
                : i e | << . sp idx 4 bits
                : ~ i f rev
                ~ < f 512 { = . fp f e = f + f << 1 bits }
            } {}
            = code + code 1
            = idx + idx 1
            = j + j 1
        }
        = code << code 1
        = bits + bits 1
    }
    ^ @ Huff { count symbol fast }
}

// A complete tree fills every code slot. Literal/distance alphabets may
// instead contain one one-bit code; an unused distance alphabet may be empty.
// Oversubscribed trees and every other incomplete tree are malformed.
@ __infl_huff_valid Huff h b single b empty → b {
    : ~ i left 1
    : ~ i symbols 0
    : ~ i bits 1
    ~ <= bits 15 {
        : i count ( __df_get . h count bits )
        = left - << left 1 count
        ? < left 0 { ^ F } {}
        = symbols + symbols count
        = bits + bits 1
    }
    ^ | == left 0 | & empty == symbols 0
    & single & == symbols 1 == ( __df_get . h count 1 ) 1
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
//
// The hot loop keeps the bit reader in locals — the state's fields would
// otherwise be reloaded after every byte written through the output
// pointer, which may alias them as far as the optimiser can tell — and
// decodes a symbol, and its extra bits, straight from the buffer when they
// are all in it and the code is in the fast table. Everything else (a long
// code, the input running out, an invalid code) goes through the
// state-based helpers above with the locals written back first and read
// back after, so every error is the one, at the place, it always was.
@ __infl_codes inout InflState st ( Vec u ) out Huff lencode Huff distcode
( Vec i ) lenbase ( Vec i ) lenext ( Vec i ) distbase ( Vec i ) distext → v {
    : *u d . st data
    : i len . st len
    : *i lfast ( vec_data [i] . lencode fast )
    : *i dfast ( vec_data [i] . distcode fast )
    : *i lb ( vec_data [i] lenbase )
    : *i lx ( vec_data [i] lenext )
    : *i db ( vec_data [i] distbase )
    : *i dx ( vec_data [i] distext )
    : ~ i bb . st bitbuf
    : ~ i bc . st bitcnt
    : ~ i pos . st pos
    : ~ b done F
    ~ ! done {
        ~ & <= bc 48 < pos len { = bb | bb << # i . d pos bc = pos + pos 1 = bc + bc 8 }
        : ~ i sym -1
        : i e . lfast & bb 511
        : i el & e 15
        ? & != el 0 <= el bc {
            = bb >> bb el
            = bc - bc el
            = sym >> e 4
        } {
            = . st bitbuf bb = . st bitcnt bc = . st pos pos
            = sym ( __infl_decode_slow st lencode )
            = bb . st bitbuf = bc . st bitcnt = pos . st pos
        }
        ? != . st err 0 { = done T } {
            ? < sym 0 { = . st err 2 = done T } {
                ? < sym 256 {
                    ? ( __infl_room st out 1 ) { ( vec_push [u] out # u sym ) } { = done T }
                } {
                    ? == sym 256 { = done T } {
                        // length/distance back-reference
                        : i li - sym 257
                        ? >= li 29 { = . st err 2 = done T } {
                            : i lext . lx li
                            : ~ i length . lb li
                            ? <= lext bc {
                                = length + length & bb - << 1 lext 1
                                = bb >> bb lext
                                = bc - bc lext
                            } {
                                = . st bitbuf bb = . st bitcnt bc = . st pos pos
                                = length + length ( __infl_bits st lext )
                                = bb . st bitbuf = bc . st bitcnt = pos . st pos
                            }
                            ? != . st err 0 { = done T } {
                                ~ & <= bc 48 < pos len { = bb | bb << # i . d pos bc = pos + pos 1 = bc + bc 8 }
                                : ~ i dsym -1
                                : i de . dfast & bb 511
                                : i del & de 15
                                ? & != del 0 <= del bc {
                                    = bb >> bb del
                                    = bc - bc del
                                    = dsym >> de 4
                                } {
                                    = . st bitbuf bb = . st bitcnt bc = . st pos pos
                                    = dsym ( __infl_decode_slow st distcode )
                                    = bb . st bitbuf = bc . st bitcnt = pos . st pos
                                }
                                ? != . st err 0 { = done T } {
                                    ? | < dsym 0 >= dsym 30 { = . st err 4 = done T } {
                                        : i dext . dx dsym
                                        : ~ i dist . db dsym
                                        ? <= dext bc {
                                            = dist + dist & bb - << 1 dext 1
                                            = bb >> bb dext
                                            = bc - bc dext
                                        } {
                                            = . st bitbuf bb = . st bitcnt bc = . st pos pos
                                            = dist + dist ( __infl_bits st dext )
                                            = bb . st bitbuf = bc . st bitcnt = pos . st pos
                                        }
                                        : i outlen ( vec_len [u] out )
                                        ? != . st err 0 { = done T } {
                                            ? | > dist outlen > dist . st window { = . st err 4 = done T } {
                                                ? ! ( __infl_room st out length ) { = done T } {
                                                    // Room first, then copy inside the
                                                    // buffer: one memcpy when source and
                                                    // destination do not overlap, else
                                                    // byte by byte forward, so a run reads
                                                    // the bytes it just wrote.
                                                    ( vec_reserve [u] out length )
                                                    : *u op ( vec_data [u] out )
                                                    : i src - outlen dist
                                                    ? >= dist length {
                                                        ( nurl_memcpy # s + # i op outlen # s + # i op src length )
                                                    } {
                                                        : ~ i k 0
                                                        ~ < k length { = . op + outlen k . op + src k = k + k 1 }
                                                    }
                                                    : b _n ( vec_set_len [u] out + outlen length )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    = . st bitbuf bb
    = . st bitcnt bc
    = . st pos pos
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
    ^ h
}

@ __infl_fixed_dist → Huff {
    : ( Vec i ) lengths ( vec_with_cap [i] 32 )
    : ~ i k 0
    ~ < k 32 { ( vec_push [i] lengths 5 ) = k + k 1 }
    : Huff h ( __infl_construct lengths 32 )
    ^ h
}

// Dynamic Huffman: read the two tables, then decode the block body.
@ __infl_dynamic inout InflState st ( Vec u ) out
( Vec i ) lenbase ( Vec i ) lenext ( Vec i ) distbase ( Vec i ) distext → v {
    : i hlit + 257 ( __infl_bits st 5 )
    : i hdist + 1 ( __infl_bits st 5 )
    : i hclen + 4 ( __infl_bits st 4 )
    ? != . st err 0 { ^ v } {}

    ? | > hlit 286 > hdist 30 { = . st err 2 ^ v } {}

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
    ? ! ( __infl_huff_valid clcode F F ) { = . st err 2 } {}

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
                ? > rep - total idx { = . st err 2 } {}
                : ~ i r 0
                ~ & == . st err 0 < r rep {
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
        ? | == ( __df_get litlen 256 ) 0
        | ! ( __infl_huff_valid lencode T F ) ! ( __infl_huff_valid distcode T T ) {
            = . st err 2
        } { ( __infl_codes st out lencode distcode lenbase lenext distbase distext ) }
    } {}

}

// Drive the block loop over st (data preset), appending to `out`. `partial` != 0 stops
// cleanly when the input is exhausted at a block boundary (streaming /
// sync-flush mode) instead of erroring on the missing BFINAL bit.
@ __inflate_run inout InflState st ( Vec u ) out i partial → v {
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
                    // Stored: align to byte, read LEN/NLEN, copy. The
                    // buffer may hold whole bytes read ahead of the
                    // partial one (__infl_fill): those go back to the input.
                    = . st pos - . st pos >> . st bitcnt 3
                    = . st bitbuf 0
                    = . st bitcnt 0
                    ? > + . st pos 4 . st len { = . st err 5 } {
                        : *u d . st data
                        : i lo # i . d . st pos
                        : i hi # i . d + . st pos 1
                        : i blen | lo << hi 8
                        : i complement | # i . d + . st pos 2 << # i . d + . st pos 3 8
                        = . st pos + . st pos 4
                        ? != ^^ blen complement 65535 { = . st err 3 } {}
                        ? > blen - . st len . st pos { = . st err 5 } {}
                        ? & == . st err 0 ( __infl_room st out blen ) {
                            ( bytes_extend_raw out # s + # i d . st pos blen )
                            = . st pos + . st pos blen
                        } {}
                    }
                } {
                    ? == btype 1 {
                        : Huff lc ( __infl_fixed_lit )
                        : Huff dc ( __infl_fixed_dist )
                        ( __infl_codes st out lc dc lenbase lenext distbase distext )
                    } {
                        ? == btype 2 {
                            ( __infl_dynamic st out lenbase lenext distbase distext )
                        } {
                            = . st err 1
                        } } } }
        }
    }

}

// Inflate a complete raw DEFLATE stream into bytes.
@ inflate ( Vec u ) src → !( Vec u ) DeflateErr {
    ^ ( inflate_max src 0 )
}

// A decoded prefix owns its bytes; consumed includes the final partially
// used byte. Framing codecs use it to locate their trailer and next member.
: Inflated { ( Vec u ) bytes i consumed }

// Prefix decoder with exact internal cap (-1 = unlimited) and window bound.
@ _inflate_prefix_window ( Vec u ) src i start i max_out i window → !Inflated DeflateErr {
    ? | < start 0 > start ( vec_len [u] src ) {
        ^ @ !Inflated DeflateErr { F DeflateBadLength }
    } {}
    : *u data # *u + # i ( vec_data [u] src ) start
    : ~ InflState st @ InflState { data - ( vec_len [u] src ) start 0 0 0 0 max_out window }
    : ( Vec u ) out ( vec_new [u] )
    ( __inflate_run st out 0 )
    ? != . st err 0 {
        ^ @ !Inflated DeflateErr { F ( __df_err . st err ) }
    } {}
    // Whole bytes still in the bit buffer were read ahead, not consumed.
    ^ @ !Inflated DeflateErr { T @ Inflated { out - . st pos >> . st bitcnt 3 } }
}

// Decode one stream from src[start..], leaving trailers to the caller.
// Public caps use 0 = unlimited. DeflateLimit distinguishes output limits
// from malformed block lengths (DeflateBadLength).
@ inflate_prefix_max ( Vec u ) src i start i max_out → !Inflated DeflateErr {
    ^ ( _inflate_prefix_window src start ? > max_out 0 max_out -1 32768 )
}

@ inflate_max ( Vec u ) src i max_out → !( Vec u ) DeflateErr {
    ?? ( inflate_prefix_max src 0 max_out ) {
        F error → ^ @ !( Vec u ) DeflateErr { F error }
        T decoded → {
            ? != . decoded consumed ( vec_len [u] src ) {
                ^ @ !( Vec u ) DeflateErr { F DeflateBadLength }
            } {}
            ^ @ !( Vec u ) DeflateErr { T . decoded bytes }
        }
    }
}

// Streaming inflate for permessage-deflate (RFC 7692) context-takeover:
// decode `input` (a sync-flush-terminated block) with `history` as the
// LZ77 window, appending decoded bytes onto `history` in place. Returns a
// fresh Vec of just the newly-decoded suffix. `history` is trimmed to the
// last 32 KiB (the maximum back-reference distance) so a long-lived
// connection stays bounded. max_out (>0) caps the per-message output.
@ inflate_stream ( Vec u ) history ( Vec u ) input i max_out → !( Vec u ) DeflateErr {
    : i oldlen ( vec_len [u] history )
    : i cap ? & > max_out 0 <= max_out - 9223372036854775807 oldlen + oldlen max_out -1
    : ~ InflState st @ InflState { ( vec_data [u] input ) ( vec_len [u] input ) 0 0 0 0 cap 32768 }

    // Decoded bytes go straight onto the caller's history (the window).
    ( __inflate_run st history 1 )

    : i err . st err
    ? != err 0 {
        : b restored ( vec_set_len [u] history oldlen )
        ^ @ !( Vec u ) DeflateErr { F ( __df_err err ) }
    } {}

    : i newlen ( vec_len [u] history )
    : i produced - newlen oldlen
    ? & > max_out 0 > produced max_out {
        ^ @ !( Vec u ) DeflateErr { F DeflateLimit }
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
    ? == e 3 { ^ # DeflateErr DeflateBadLength } {}
    ? == e 4 { ^ # DeflateErr DeflateBadDist } {}
    ? == e 5 { ^ # DeflateErr DeflateTruncated } {}
    ? == e 6 { ^ # DeflateErr DeflateLimit } {}
    ^ # DeflateErr DeflateOther
}

// ── deflate (encoder: fixed Huffman + greedy LZ77) ──────────────────

: BitW {
    ( Vec u ) out
    i bitbuf
    i bitcnt
}

// Emit `n` bits of `val` LSB-first (used for header fields + extra bits).
@ __df_bits inout BitW w i val i n → v {
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
@ __df_huff inout BitW w i code i n → v {
    : ~ i rev 0
    : ~ i k 0
    ~ < k n { = rev | << rev 1 & >> code k 1 = k + k 1 }
    ( __df_bits w rev n )
}

@ __df_flush inout BitW w → v {
    ? > . w bitcnt 0 {
        ( vec_push [u] . w out # u & . w bitbuf 255 )
        = . w bitbuf 0
        = . w bitcnt 0
    } {}
}

// Emit a literal byte or a fixed-Huffman lit/len symbol (incl. EOB 256).
@ __df_emit_sym inout BitW w i sym → v {
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

// The little-endian u64 at d[o .. o+8]; the eight byte loads fold into one
// unaligned load.
@ __df_ld64 * u d i o → i {
    : i lo | | | # i . d o << # i . d + o 1 8 << # i . d + o 2 16 << # i . d + o 3 24
    : i hi | | | # i . d + o 4 << # i . d + o 5 8 << # i . d + o 6 16 << # i . d + o 7 24
    ^ | lo << hi 32
}

// Length of the common run of d[pos..] and d[cur..], at most `maxlen`:
// eight bytes a step while eight remain, the first differing byte found by
// the lowest set bit of their difference, then a byte at a time.
@ __df_matchlen * u d i pos i cur i maxlen → i {
    : ~ i l 0
    ~ <= + l 8 maxlen {
        : i x ^^ ( __df_ld64 d + cur l ) ( __df_ld64 d + pos l )
        ? != x 0 { ^ + l >> # i ( nurl_ctz # u64 x ) 3 } {}
        = l + l 8
    }
    ~ & < l maxlen == # i . d + cur l # i . d + pos l { = l + l 1 }
    ^ l
}

// Find the length symbol index (0..28) for a match length 3..258: the last
// base not above it. Bases are ascending, so a binary search finds the
// same index the linear scan did.
@ __df_len_sym ( Vec i ) lenbase i length → i {
    : *i bp ( vec_data [i] lenbase )
    ? >= length 258 { ^ 28 } {}
    : ~ i lo 0
    : ~ i hi 27  // the answer is in [lo, hi]
    ~ < lo hi {
        : i mid >> + + lo hi 1 1
        ? <= . bp mid length { = lo mid } { = hi - mid 1 }
    }
    ^ lo
}

@ __df_dist_sym ( Vec i ) distbase i dist → i {
    : *i bp ( vec_data [i] distbase )
    : ~ i lo 0
    : ~ i hi 29
    ~ < lo hi {
        : i mid >> + + lo hi 1 1
        ? <= . bp mid dist { = lo mid } { = hi - mid 1 }
    }
    ^ lo
}

@ __df_emit_match inout BitW w i length i dist
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
@ __df_lz77_block inout BitW w ( Vec u ) src i bfinal i start → v {
    : i n ( vec_len [u] src )
    : *u d ( vec_data [u] src )

    : ( Vec i ) lenbase ( __infl_lenbase )
    : ( Vec i ) lenext ( __infl_lenext )
    : ( Vec i ) distbase ( __infl_distbase )
    : ( Vec i ) distext ( __infl_distext )

    ( __df_bits w bfinal 1 )
    ( __df_bits w 1 2 )  // BTYPE=01 (fixed Huffman)

    : ( Vec i ) head ( __df_fill -1 32768 )
    // The chain links of the last 32 KiB of positions, by position mod
    // 32768: the chain never follows a link more than 32768 back (the
    // distance check below), and the slot of position c is next written
    // at c + 32768 — after every walk that may still read it. A table
    // over the whole input gave the same links from a footprint eight
    // bytes a position wide, where every chain step missed the cache.
    : ( Vec i ) prev ( __df_fill -1 32768 )

    // Seed the dictionary region [0, start) into the hash chains.
    : ~ i si 0
    ~ < si start {
        ? <= si - n 3 {
            : i sh ( __df_hash d si )
            ( __df_set prev & si 32767 ( __df_get head sh ) )
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
            : i maxlen ? < - n i 258 - n i 258
            // A candidate can only beat `bestlen` if it also matches at
            // offset `bestlen`: one byte compare skips the rest, and once
            // `bestlen` is the longest possible no candidate can — the
            // chain picks the same match a full comparison of every
            // candidate would.
            ~ & & >= c 0 < chain 128 < bestlen maxlen {
                : i dist - i c
                ? > dist 32768 { = c -1 } {
                    ? == # i . d + c bestlen # i . d + i bestlen {
                        : i ml ( __df_matchlen d i c maxlen )
                        ? > ml bestlen { = bestlen ml = bestdist dist } {}
                    } {}
                    = c ( __df_get prev & c 32767 )
                    = chain + chain 1
                }
            }
            ( __df_set prev & i 32767 cand )
            ( __df_set head h i )
            ? >= bestlen 3 {
                ( __df_emit_match w bestlen bestdist lenbase lenext distbase distext )
                : ~ i k 1
                ~ & < k bestlen <= + i k - n 3 {
                    : i hk ( __df_hash d + i k )
                    ( __df_set prev & + i k 32767 ( __df_get head hk ) )
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
}

// Compress bytes into a complete raw DEFLATE stream (single final block).
@ deflate ( Vec u ) src → ( Vec u ) {
    : ~ BitW w @ BitW { ( vec_new [u] ) 0 0 }
    ( __df_lz77_block w src 1 0 )
    ( __df_flush w )
    // The output leaves the writer (moved, not copied).
    : ( Vec u ) out . w out
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

    : ~ BitW w @ BitW { ( vec_new [u] ) 0 0 }
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
    ^ out
}

@ deflate_block ( Vec u ) src → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) r ( deflate_block_dict empty src )
    ^ r
}
