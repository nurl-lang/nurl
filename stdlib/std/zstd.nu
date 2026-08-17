// stdlib/std/zstd.nu — Zstandard (RFC 8878) in pure NURL.
//
// This is the real format, not a subset: frames with or without a
// declared content size, raw / RLE / compressed blocks, Huffman-coded
// literals in one or four bitstreams (with a tree that is itself FSE-
// compressed, or repeated from the previous block), FSE-coded sequences
// in all four table modes, the three repeat offsets with their
// literals-length-zero exception, skippable frames, multi-frame
// concatenation, and the XXH64 content checksum. Output of `zstd -1`
// through `zstd -19 --ultra` decodes here byte for byte.
//
// Why in the stdlib rather than behind an FFI: `ext/compress.nu` used to
// reach libzstd, which made zstd unavailable wherever that library is
// not — a freestanding build, a unikernel, wasm, or any machine without
// libzstd-dev — and made the *whole* module fail to compile there. A
// format is not a dependency.
//
//   ( zstd_decode       ( Vec u ) src )            → !( Vec u ) ZstdErr
//   ( zstd_decode_limit ( Vec u ) src i max_out )  → !( Vec u ) ZstdErr
//   ( zstd_content_size ( Vec u ) src )            → ?i
//   ( zstd_err_name     ZstdErr e )                → s
//
// `zstd_decode` decodes every frame in `src` and concatenates the
// results, which is what the `zstd` CLI does with a concatenated file.
// `zstd_decode_limit` refuses at `max_out` bytes — use it on input you
// did not produce, because a 100 kB frame can legally declare gigabytes.
// `zstd_content_size` reads the first frame's declared size without
// decoding anything; it is absent when the producer streamed the frame.
//
// Inputs are BORROWED. The returned Vec is OWNED — free with
// `vec_free [u]`.
//
// Not supported: dictionaries (`ZstdUnsupported` — a frame that names a
// dictionary ID cannot be decoded without it, and silently producing
// wrong bytes is worse than refusing).
//
// The compressor lives in the same module (see `zstd_encode`), so a
// round trip needs nothing else.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_xxh64.nu`

: | ZstdErr {
    ZstdMagic  // not a Zstandard frame
    ZstdCorrupt  // malformed or self-inconsistent data
    ZstdTruncated  // input ended inside a frame
    ZstdChecksum  // content checksum mismatch
    ZstdUnsupported  // valid zstd this decoder cannot do (dictionaries)
    ZstdTooLarge  // output would exceed the caller's limit
}

@ zstd_err_name ZstdErr e → s {
    ^ ?? e {
        ZstdMagic → `ZstdMagic`
        ZstdCorrupt → `ZstdCorrupt`
        ZstdTruncated → `ZstdTruncated`
        ZstdChecksum → `ZstdChecksum`
        ZstdUnsupported → `ZstdUnsupported`
        ZstdTooLarge → `ZstdTooLarge`
    }
}

// Internal error codes, mapped to ZstdErr on the way out.
: i ZSE_CORRUPT 1
: i ZSE_TRUNC 2
: i ZSE_CKSUM 3
: i ZSE_UNSUP 4
: i ZSE_LARGE 5
: i ZSE_MAGIC 6

: i ZS_MAGIC 0xFD2FB528
: i ZS_SKIP_LO 0x184D2A50
: i ZS_SKIP_HI 0x184D2A5F
: i ZS_MAX_HUF_BITS 11  // Huffman codes are at most 11 bits
: i ZS_MAX_SYMS 256

@ __zs_err i code → ZstdErr {
    ^ ? == code ZSE_TRUNC # ZstdErr ZstdTruncated
    ? == code ZSE_CKSUM # ZstdErr ZstdChecksum
    ? == code ZSE_UNSUP # ZstdErr ZstdUnsupported
    ? == code ZSE_LARGE # ZstdErr ZstdTooLarge
    ? == code ZSE_MAGIC # ZstdErr ZstdMagic
    # ZstdErr ZstdCorrupt
}

// Index of the highest set bit, -1 for zero. floor(log2 x) for x > 0.
@ __zs_hbit i x → i {
    ? <= x 0 { ^ -1 } {}
    ^ - 63 # i ( nurl_clz # u64 x )
}

@ __zs_zeros i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

// ── Decoder state ───────────────────────────────────────────────────
//
// One heap struct so helpers can write to it (NURL structs pass by
// value; a field assigned through a `*T` is the caller's field).
//
// The entropy tables are allocated once at their maximum size and
// rewritten in place: FSE accuracy is at most 9 bits (512 entries) and
// a Huffman table at most 11 (2048), so a block that repeats the
// previous tables costs no allocation at all.

: ZsDec {
    * u src  // input bytes (borrowed)
    i srclen
    i pos  // byte cursor into src
    ( Vec u ) out  // output buffer, len kept at 0 until the end
    * u op  // out's data pointer, refreshed on every grow
    i olen  // bytes written so far
    i ocap
    i limit
    i framestart  // olen at the start of the current frame
    ( Vec u ) lit  // literals of the current block
    i litlen
    i litcap
    i litpos  // read cursor while executing sequences
    ( Vec i ) huf  // packed Huffman entries: sym | nbits<<8
    i hufbits  // 0 = no table decoded yet
    ( Vec i ) llt  // packed FSE entries: sym | nbits<<8 | newstate<<16
    i lllog  // -1 = no table
    ( Vec i ) oft
    i oflog
    ( Vec i ) mlt
    i mllog
    ( Vec i ) sc1  // scratch: normalized counts / weights
    ( Vec i ) sc2  // scratch: per-symbol state descriptor / code lengths
    ( Vec i ) sc3  // scratch: Huffman weight FSE table
    i rep0
    i rep1
    i rep2
    i window
    i err
}

// A forward, little-endian bit reader — headers and FSE distributions.
: ZsFwd {
    * u src
    i len
    i bit  // bit cursor from the start of src
    i err
}

// A backward bit reader — every FSE and Huffman payload. `off` is a bit
// cursor that walks down to zero and is allowed to go negative: the
// last few bits of a stream are defined to read as zeros.
: ZsBk {
    * u src
    i len
    i off
}

// Read `n` bits little-endian starting at bit `off`. The caller
// guarantees the range is inside the buffer.
@ __zs_rd_le * u src i n i off → i {
    : ~ i bytepos >> off 3
    : ~ i bitoff & off 7
    : ~ i res 0
    : ~ i shift 0
    : ~ i left n
    ~ > left 0 {
        : i mask ? >= left 8 255 - << 1 left 1
        : i byte # i . src bytepos
        = res + res << & >> byte bitoff mask shift
        = shift + shift - 8 bitoff
        = left - left - 8 bitoff
        = bitoff 0
        = bytepos + bytepos 1
    }
    ^ res
}

@ __zs_fw_take * ZsFwd f i n → i {
    ? == n 0 { ^ 0 } {}
    ? > + . f bit n * . f len 8 { = . f err 1 ^ 0 } {}
    : i v ( __zs_rd_le . f src n . f bit )
    = . f bit + . f bit n
    ^ v
}

@ __zs_fw_rewind * ZsFwd f i n → v { = . f bit - . f bit n }

@ __zs_fw_align * ZsFwd f → v { = . f bit << >> + . f bit 7 3 3 }

@ __zs_fw_bytepos * ZsFwd f → i { ^ >> . f bit 3 }

// Read `n` bits from the end of a backward stream. Bits before the
// start of the buffer read as zero, as the format requires.
// The same read as `__zs_bk_take`, but WITHOUT the cursor struct: the
// caller keeps `off` in a local and passes it in. That is the whole
// optimisation — a `* ZsBk` field is memory the compiler must reload
// after every call, and this bit cursor is touched six to eight times
// per sequence. `off` may be negative; the bits before the start of the
// stream read as zero, as the format requires.
// The rare halves of `__zs_bits`, moved out of it: the last few bytes
// of a stream, where an eight-byte load would run off the end, and the
// bits before its start, which the format defines as zeros. Splitting
// them out keeps the hot function small enough to be inlined, which is
// worth more than either branch costs.
@ __zs_bits_edge * u src i len i off i n → i {
    ? >= off 0 { ^ ( __zs_rd_le src n off ) } {}
    : i have + n off
    : ~ i r 0
    ? > have 0 { = r ( __zs_rd_le src have 0 ) } {}
    : i sh - 0 off
    ^ ? >= sh 64 0 << r sh
}

// The same read as `__zs_bk_take`, but WITHOUT the cursor struct: the
// caller keeps `off` in a local and passes it in. That is the whole
// optimisation — a `* ZsBk` field is memory the compiler must reload
// after every call, and this bit cursor is touched six to eight times
// per sequence. `off` may be negative; the bits before the start of the
// stream read as zero, as the format requires.
//
// Eight consecutive byte loads with constant shifts is a pattern LLVM
// folds into ONE unaligned 64-bit load — the instruction this wants,
// and one the language has no way to spell directly. Reads are at most
// 32 bits, so 64 bits minus a 7-bit misalignment always covers them.
@ __zs_bits * u src i len i off i n → i {
    : i bytepos >> off 3
    ? & >= off 0 <= + bytepos 8 len {
        : i lo | | | # i . src bytepos
        << # i . src + bytepos 1 8
        << # i . src + bytepos 2 16
        << # i . src + bytepos 3 24
        : i hi | | | # i . src + bytepos 4
        << # i . src + bytepos 5 8
        << # i . src + bytepos 6 16
        << # i . src + bytepos 7 24
        : i word | lo << hi 32
        ^ & >> # u64 word & off 7 - << 1 n 1
    } {}
    ? == n 0 { ^ 0 } {}
    ^ ( __zs_bits_edge src len off n )
}

// The cursor-carrying form, for the paths where a struct is clearer
// than threading an offset through: the Huffman streams and the weight
// decoder, which read far fewer bits per call than the sequence loop.
@ __zs_bk_take * ZsBk b i n → i {
    ? == n 0 { ^ 0 } {}
    = . b off - . b off n
    ^ ( __zs_bits . b src . b len . b off n )
}

// Position a backward reader at the last information bit: the final
// byte carries a 1 bit marking the end, above 0..7 bits of padding.
// A final byte of zero is therefore malformed.
@ __zs_bk_start * ZsBk b → i {
    ? <= . b len 0 { ^ ZSE_CORRUPT } {}
    : *u sp . b src
    : i last # i . sp - . b len 1
    ? == last 0 { ^ ZSE_CORRUPT } {}
    : i padding - 8 ( __zs_hbit last )
    = . b off - * . b len 8 padding
    ^ 0
}

// ── FSE ─────────────────────────────────────────────────────────────

// Read a normalized distribution. Returns the number of symbols, or -1.
// The counts land in `freq`; a count of -1 means "less than one", a
// symbol that still gets a cell.
@ __zs_fse_header * ZsFwd f ( Vec i ) freq i maxlog → i {
    : i log + 5 ( __zs_fw_take f 4 )
    ? > log maxlog { ^ -1 } {}
    : *i fp ( vec_data [i] freq )
    : ~ i remaining << 1 log
    : ~ i symb 0
    ~ & > remaining 0 < symb ZS_MAX_SYMS {
        // The field is only as wide as the probability space left.
        : i bits + 1 ( __zs_hbit + remaining 1 )
        : i val ( __zs_fw_take f bits )
        : i lower_mask - << 1 - bits 1 1
        : i threshold - - << 1 bits 1 + remaining 1
        : ~ i v val
        ? < & val lower_mask threshold {
            // Small values spend one bit less; give the top bit back.
            ( __zs_fw_rewind f 1 )
            = v & val lower_mask
        } { ? > val lower_mask { = v - val threshold } {} }
        : i proba - v 1
        = remaining - remaining ? < proba 0 - 0 proba proba
        = . fp symb proba
        = symb + symb 1
        ? == proba 0 {
            // A zero count is followed by a 2-bit run length, chained
            // while it reads 3.
            : ~ i repeat ( __zs_fw_take f 2 )
            : ~ b more T
            ~ more {
                : ~ i k 0
                ~ & < k repeat < symb ZS_MAX_SYMS {
                    = . fp symb 0
                    = symb + symb 1
                    = k + k 1
                }
                ? == repeat 3 { = repeat ( __zs_fw_take f 2 ) } { = more F }
            }
        } {}
    }
    ( __zs_fw_align f )
    ? != . f err 0 { ^ -1 } {}
    ? != remaining 0 { ^ -1 } {}
    ? >= symb ZS_MAX_SYMS { ^ -1 } {}
    ^ | symb << log 16
}

// Turn a normalized distribution into a decoding table. `tab` holds
// 1<<log packed entries. Returns 0, or ZSE_CORRUPT.
@ __zs_fse_build ( Vec i ) tab ( Vec i ) freq ( Vec i ) sd0 i nsym i log → i {
    : i size << 1 log
    : *i tp ( vec_data [i] tab )
    : *i fp ( vec_data [i] freq )
    : *i sd ( vec_data [i] sd0 )
    // "Less than one" symbols take one cell each from the top.
    : ~ i high size
    : ~ i s 0
    ~ < s nsym {
        ? == # i . fp s -1 {
            = high - high 1
            = . tp high s
            = . sd s 1
        } {}
        = s + s 1
    }
    ? < high 0 { ^ ZSE_CORRUPT } {}
    // Everything else is spread with a step coprime to the table size,
    // skipping the cells already taken.
    : i step + + >> size 1 >> size 3 3
    : i mask - size 1
    : ~ i pos 0
    = s 0
    ~ < s nsym {
        : i c # i . fp s
        ? > c 0 {
            = . sd s c
            : ~ i k 0
            ~ < k c {
                = . tp pos s
                = pos & + pos step mask
                ~ >= pos high { = pos & + pos step mask }
                = k + k 1
            }
        } {}
        = s + s 1
    }
    // The walk visits every cell exactly once, so it must come home.
    ? != pos 0 { ^ ZSE_CORRUPT } {}
    : ~ i u 0
    ~ < u size {
        : i sym # i . tp u
        : i nx # i . sd sym
        = . sd sym + nx 1
        : i nb - log ( __zs_hbit nx )
        : i ns - << nx nb size
        = . tp u | | sym << nb 8 << ns 16
        = u + u 1
    }
    ^ 0
}

// A table that always decodes one symbol and never reads a bit.
@ __zs_fse_rle ( Vec i ) tab i sym → v {
    : *i tp ( vec_data [i] tab )
    = . tp 0 sym
}

// ── Huffman ─────────────────────────────────────────────────────────

// Build a decoding table from per-symbol code lengths. Entries are
// indexed by the next `max_bits` bits of the stream.
@ __zs_huf_build ( Vec i ) tab ( Vec i ) bits0 i nsym → i {
    : *i bp ( vec_data [i] bits0 )
    : ~ i maxb 0
    : ~ i s 0
    // rank_count in a fixed 12-slot window; code lengths cannot exceed 11.
    : ( Vec i ) rc ( __zs_zeros 16 )
    : *i rcp ( vec_data [i] rc )
    ~ < s nsym {
        : i b # i . bp s
        ? > b ZS_MAX_HUF_BITS { ( vec_free [i] rc ) ^ -1 } {}
        ? > b maxb { = maxb b } {}
        = . rcp b + # i . rcp b 1
        = s + s 1
    }
    ? == maxb 0 { ( vec_free [i] rc ) ^ -1 } {}
    : i size << 1 maxb
    // Codes are handed out shortest-last: the longest codes (weight 1)
    // sit at the bottom of the table.
    : ( Vec i ) ri ( __zs_zeros 16 )
    : *i rip ( vec_data [i] ri )
    = . rip maxb 0
    : ~ i i maxb
    ~ >= i 1 {
        = . rip - i 1 + # i . rip i * # i . rcp i << 1 - maxb i
        = i - i 1
    }
    : b full == # i . rip 0 size
    ( vec_free [i] rc )
    ? ! full { ( vec_free [i] ri ) ^ -1 } {}
    : *i tp ( vec_data [i] tab )
    = s 0
    ~ < s nsym {
        : i b # i . bp s
        ? != b 0 {
            : i code # i . rip b
            : i len << 1 - maxb b
            : i packed | s << b 8
            : ~ i k 0
            ~ < k len { = . tp + code k packed = k + k 1 }
            = . rip b + code len
        } {}
        = s + s 1
    }
    ( vec_free [i] ri )
    ^ maxb
}

// Weights → code lengths → table. The last symbol's weight is not
// transmitted: it is whatever completes the next power of two.
@ __zs_huf_from_weights ( Vec i ) tab ( Vec i ) wts ( Vec i ) bits0 i nsym → i {
    : *i wp ( vec_data [i] wts )
    : *i bp ( vec_data [i] bits0 )
    : ~ i sum 0
    : ~ i s 0
    ~ < s nsym {
        : i w # i . wp s
        ? > w ZS_MAX_HUF_BITS { ^ -1 } {}
        ? > w 0 { = sum + sum << 1 - w 1 } {}
        = s + s 1
    }
    ? <= sum 0 { ^ -1 } {}
    : i maxb + ( __zs_hbit sum ) 1
    ? > maxb ZS_MAX_HUF_BITS { ^ -1 } {}
    : i left - << 1 maxb sum
    ? == left 0 { ^ -1 } {}
    ? != & left - left 1 0 { ^ -1 } {}
    : i last + ( __zs_hbit left ) 1
    = s 0
    ~ < s nsym {
        : i w # i . wp s
        = . bp s ? > w 0 - + maxb 1 w 0
        = s + s 1
    }
    = . bp nsym - + maxb 1 last
    ^ ( __zs_huf_build tab bits0 + nsym 1 )
}

// ── Output buffer ───────────────────────────────────────────────────

@ __zs_need * ZsDec d i n → v {
    ? != . d err 0 { ^ v } {}
    : i want + . d olen n
    ? > want . d limit { = . d err ZSE_LARGE ^ v } {}
    ? > want . d ocap {
        : i twice * . d ocap 2
        : i newcap ? > twice want twice want
        ( vec_reserve [u] . d out newcap )
        = . d op ( vec_data [u] . d out )
        = . d ocap ( vec_cap [u] . d out )
        ? < . d ocap want { = . d err ZSE_CORRUPT } {}
    } {}
}

// ── Literals ────────────────────────────────────────────────────────

@ __zs_lit_need * ZsDec d i n → v {
    ? > n . d litcap {
        ( vec_free [u] . d lit )
        = . d lit ( vec_with_cap [u] n )
        = . d litcap ( vec_cap [u] . d lit )
        ? < . d litcap n { = . d err ZSE_CORRUPT } {}
    } {}
}

// Decode one Huffman-coded bitstream into the literals buffer at
// `at`. Returns the number of symbols, or -1.
@ __zs_huf_stream * ZsDec d i off i len i at i cap → i {
    ? <= len 0 { ^ -1 } {}
    : *ZsBk b ( nurl_alloc Z ZsBk )
    = . b src # *u + # i . d src off
    = . b len len
    ? != ( __zs_bk_start b ) 0 { ( nurl_free # s b ) ^ -1 } {}
    : i maxb . d hufbits
    : i mask - << 1 maxb 1
    : *i tp ( vec_data [i] . d huf )
    : *u lp ( vec_data [u] . d lit )
    : ~ i state ( __zs_bk_take b maxb )
    : ~ i n 0
    : ~ b bad F
    ~ & ! bad > . b off - 0 maxb {
        : i e # i . tp state
        ? >= + at n cap { = bad T } {
            = . lp + at n # u & e 255
            = n + n 1
            : i nb & >> e 8 255
            : i rest ( __zs_bk_take b nb )
            = state & + << state nb rest mask
        }
    }
    // A stream must land exactly on its own beginning.
    ? != . b off - 0 maxb { = bad T } {}
    ( nurl_free # s b )
    ^ ? bad -1 n
}

// Decode the Huffman tree description. Returns bytes consumed, or -1.
@ __zs_huf_table * ZsDec d i off i len → i {
    ? <= len 0 { ^ -1 } {}
    : *u sp . d src
    : i header # i . sp off
    : *i wp ( vec_data [i] . d sc1 )
    : ~ i nsym 0
    : ~ i used 1
    ? >= header 128 {
        // Weights written straight out, two to a byte, high nibble first.
        = nsym - header 127
        : i nbytes >> + nsym 1 1
        ? > + 1 nbytes len { ^ -1 } {}
        : ~ i k 0
        ~ < k nsym {
            : i byte # i . sp + + off 1 >> k 1
            = . wp k ? == & k 1 0 >> byte 4 & byte 15
            = k + k 1
        }
        = used + 1 nbytes
    } {
        // Weights are themselves FSE-coded in the next `header` bytes.
        ? > + 1 header len { ^ -1 } {}
        : *ZsFwd f ( nurl_alloc Z ZsFwd )
        = . f src # *u + # i . d src + off 1
        = . f len header
        = . f bit 0
        = . f err 0
        : i hdr ( __zs_fse_header f . d sc2 7 )
        ? < hdr 0 { ( nurl_free # s f ) ^ -1 } {}
        : i wsym & hdr 65535
        : i wlog >> hdr 16
        ? != ( __zs_fse_build . d sc3 . d sc2 . d sc1 wsym wlog ) 0 {
            ( nurl_free # s f ) ^ -1
        } {}
        : i bp ( __zs_fw_bytepos f )
        ( nurl_free # s f )
        : i rem - header bp
        ? <= rem 0 { ^ -1 } {}
        // Two interleaved states share one table: state1 takes the even
        // weights, state2 the odd ones.
        : *ZsBk b ( nurl_alloc Z ZsBk )
        = . b src # *u + # i . d src + + off 1 bp
        = . b len rem
        ? != ( __zs_bk_start b ) 0 { ( nurl_free # s b ) ^ -1 } {}
        : *i tp ( vec_data [i] . d sc3 )
        : ~ i s1 ( __zs_bk_take b wlog )
        : ~ i s2 ( __zs_bk_take b wlog )
        : ~ i n 0
        : ~ b done F
        : ~ b bad F
        ~ ! done {
            ? >= + n 2 ZS_MAX_SYMS { = bad T = done T } {
                : i e1 # i . tp s1
                = . wp n & e1 255
                = n + n 1
                = s1 + >> e1 16 ( __zs_bk_take b & >> e1 8 255 )
                ? < . b off 0 {
                    = . wp n & # i . tp s2 255
                    = n + n 1
                    = done T
                } {
                    : i e2 # i . tp s2
                    = . wp n & e2 255
                    = n + n 1
                    = s2 + >> e2 16 ( __zs_bk_take b & >> e2 8 255 )
                    ? < . b off 0 {
                        = . wp n & # i . tp s1 255
                        = n + n 1
                        = done T
                    } {}
                }
            }
        }
        ( nurl_free # s b )
        ? bad { ^ -1 } {}
        = nsym n
        = used + 1 header
    }
    ? | <= nsym 0 >= nsym ZS_MAX_SYMS { ^ -1 } {}
    : i maxb ( __zs_huf_from_weights . d huf . d sc1 . d sc2 nsym )
    ? < maxb 0 { ^ -1 } {}
    = . d hufbits maxb
    ^ used
}

// Literals section. Leaves the reader positioned after it.
@ __zs_literals * ZsDec d * ZsFwd f → v {
    : *u fsp . f src
    : *u dsp . d src
    : i btype ( __zs_fw_take f 2 )
    : i sfmt ( __zs_fw_take f 2 )
    ? != . f err 0 { = . d err ZSE_CORRUPT ^ v } {}
    ? <= btype 1 {
        // Raw or RLE: one size field, whose width the format bit selects.
        : ~ i size 0
        ? == sfmt 1 { = size ( __zs_fw_take f 12 ) }
        { ? == sfmt 3 { = size ( __zs_fw_take f 20 ) }
            { ( __zs_fw_rewind f 1 ) = size ( __zs_fw_take f 5 ) } }
        ? != . f err 0 { = . d err ZSE_CORRUPT ^ v } {}
        ( __zs_lit_need d ? > size 0 size 1 )
        ? != . d err 0 { ^ v } {}
        ( __zs_fw_align f )
        : i at ( __zs_fw_bytepos f )
        : *u lp ( vec_data [u] . d lit )
        ? == btype 0 {
            ? > + at size . f len { = . d err ZSE_CORRUPT ^ v } {}
            ? > size 0 {
                ( nurl_memcpy # s lp # s # *u + # i . f src at size )
            } {}
            = . f bit << + at size 3
        } {
            ? >= at . f len { = . d err ZSE_CORRUPT ^ v } {}
            : i byte # i . fsp at
            : ~ i k 0
            ~ < k size { = . lp k # u byte = k + k 1 }
            = . f bit << + at 1 3
        }
        = . d litlen size
        ^ v
    } {}
    // Huffman-coded, with a fresh tree (2) or the previous one (3).
    : ~ i nstreams 4
    : ~ i regen 0
    : ~ i csize 0
    ? == sfmt 0 {
        = nstreams 1
        = regen ( __zs_fw_take f 10 )
        = csize ( __zs_fw_take f 10 )
    } { ? == sfmt 1 {
            = regen ( __zs_fw_take f 10 )
            = csize ( __zs_fw_take f 10 )
        } { ? == sfmt 2 {
                = regen ( __zs_fw_take f 14 )
                = csize ( __zs_fw_take f 14 )
            } {
                = regen ( __zs_fw_take f 18 )
                = csize ( __zs_fw_take f 18 )
            } } }
    ? != . f err 0 { = . d err ZSE_CORRUPT ^ v } {}
    ( __zs_fw_align f )
    : i at ( __zs_fw_bytepos f )
    ? > + at csize . f len { = . d err ZSE_CORRUPT ^ v } {}
    ( __zs_lit_need d ? > regen 0 regen 1 )
    ? != . d err 0 { ^ v } {}
    // The sub-stream is expressed as an absolute offset into src so the
    // Huffman helpers can work without another reader.
    : i base + . d pos at
    : ~ i hoff base
    : ~ i hlen csize
    ? == btype 2 {
        : i used ( __zs_huf_table d hoff hlen )
        ? < used 0 { = . d err ZSE_CORRUPT ^ v } {}
        = hoff + hoff used
        = hlen - hlen used
    } { ? == . d hufbits 0 { = . d err ZSE_CORRUPT ^ v } {} }
    ? <= hlen 0 { = . d err ZSE_CORRUPT ^ v } {}
    : ~ i total 0
    ? == nstreams 1 {
        = total ( __zs_huf_stream d hoff hlen 0 regen )
    } {
        ? < hlen 6 { = . d err ZSE_CORRUPT ^ v } {}
        : i c1 | # i . dsp hoff << # i . dsp + hoff 1 8
        : i c2 | # i . dsp + hoff 2 << # i . dsp + hoff 3 8
        : i c3 | # i . dsp + hoff 4 << # i . dsp + hoff 5 8
        : i c4 - - - - hlen 6 c1 c2 c3
        ? <= c4 0 { = . d err ZSE_CORRUPT ^ v } {}
        : i s1 ( __zs_huf_stream d + hoff 6 c1 0 regen )
        ? < s1 0 { = . d err ZSE_CORRUPT ^ v } {}
        : i s2 ( __zs_huf_stream d + + hoff 6 c1 c2 s1 regen )
        ? < s2 0 { = . d err ZSE_CORRUPT ^ v } {}
        : i s3 ( __zs_huf_stream d + + + hoff 6 c1 c2 c3 + s1 s2 regen )
        ? < s3 0 { = . d err ZSE_CORRUPT ^ v } {}
        : i s4 ( __zs_huf_stream d + + + + hoff 6 c1 c2 c3 c4 + + s1 s2 s3 regen )
        ? < s4 0 { = . d err ZSE_CORRUPT ^ v } {}
        = total + + + s1 s2 s3 s4
    }
    ? != total regen { = . d err ZSE_CORRUPT ^ v } {}
    = . d litlen regen
    = . f bit << + at csize 3
}

// ── Sequences ───────────────────────────────────────────────────────
//
// Only the extra-bit counts are tabulated: every baseline is the
// previous baseline plus 1<<extra, which is how the format was built.

@ __zs_pl * i p i at i a i b i c i d i e i f i g i h → i {
    = . p at a
    = . p + at 1 b
    = . p + at 2 c
    = . p + at 3 d
    = . p + at 4 e
    = . p + at 5 f
    = . p + at 6 g
    = . p + at 7 h
    ^ + at 8
}

// Literals-length codes 0..35: 16 direct values, then widening fields.
@ __zs_ll_extra → ( Vec i ) {
    : ( Vec i ) v ( __zs_zeros 36 )
    : *i p ( vec_data [i] v )
    : ~ i at 16
    = at ( __zs_pl p at 1 1 1 1 2 2 3 3 )
    = at ( __zs_pl p at 4 6 7 8 9 10 11 12 )
    = at ( __zs_pl p at 13 14 15 16 0 0 0 0 )
    ^ v
}

// Match-length codes 0..52: 32 direct values (baseline code+3), then
// the same widening shape.
@ __zs_ml_extra → ( Vec i ) {
    : ( Vec i ) v ( __zs_zeros 53 )
    : *i p ( vec_data [i] v )
    : ~ i at 32
    = at ( __zs_pl p at 1 1 1 1 2 2 3 3 )
    = at ( __zs_pl p at 4 4 5 7 8 9 10 11 )
    = at ( __zs_pl p at 12 13 14 15 16 0 0 0 )
    ^ v
}

@ __zs_ll_base ( Vec i ) extra → ( Vec i ) {
    : ( Vec i ) v ( __zs_zeros 36 )
    : *i p ( vec_data [i] v )
    : *i e ( vec_data [i] extra )
    : ~ i c 0
    ~ < c 16 { = . p c c = c + c 1 }
    ~ < c 36 {
        = . p c + # i . p - c 1 << 1 # i . e - c 1
        = c + c 1
    }
    ^ v
}

@ __zs_ml_base ( Vec i ) extra → ( Vec i ) {
    : ( Vec i ) v ( __zs_zeros 53 )
    : *i p ( vec_data [i] v )
    : *i e ( vec_data [i] extra )
    : ~ i c 0
    ~ < c 32 { = . p c + c 3 = c + c 1 }
    ~ < c 53 {
        = . p c + # i . p - c 1 << 1 # i . e - c 1
        = c + c 1
    }
    ^ v
}

@ __zs_ll_default ( Vec i ) freq → i {
    : *i p ( vec_data [i] freq )
    : ~ i at 0
    = at ( __zs_pl p at 4 3 2 2 2 2 2 2 )
    = at ( __zs_pl p at 2 2 2 2 2 1 1 1 )
    = at ( __zs_pl p at 2 2 2 2 2 2 2 2 )
    = at ( __zs_pl p at 2 3 2 1 1 1 1 1 )
    = at ( __zs_pl p at -1 -1 -1 -1 0 0 0 0 )
    ^ 36
}

@ __zs_of_default ( Vec i ) freq → i {
    : *i p ( vec_data [i] freq )
    : ~ i at 0
    = at ( __zs_pl p at 1 1 1 1 1 1 2 2 )
    = at ( __zs_pl p at 2 1 1 1 1 1 1 1 )
    = at ( __zs_pl p at 1 1 1 1 1 1 1 1 )
    = at ( __zs_pl p at -1 -1 -1 -1 -1 0 0 0 )
    ^ 29
}

@ __zs_ml_default ( Vec i ) freq → i {
    : *i p ( vec_data [i] freq )
    : ~ i at 0
    = at ( __zs_pl p at 1 4 3 2 2 2 2 2 )  // 0..7
    = at ( __zs_pl p at 2 1 1 1 1 1 1 1 )  // 8..15
    = at ( __zs_pl p at 1 1 1 1 1 1 1 1 )  // 16..23
    = at ( __zs_pl p at 1 1 1 1 1 1 1 1 )  // 24..31
    = at ( __zs_pl p at 1 1 1 1 1 1 1 1 )  // 32..39
    = at ( __zs_pl p at 1 1 1 1 1 1 -1 -1 )  // 40..47
    = at ( __zs_pl p at -1 -1 -1 -1 -1 0 0 0 )  // 48..52 (+ pad)
    ^ 53
}

// One of the three sequence tables. `which`: 0 = literals lengths,
// 1 = offsets, 2 = match lengths.
@ __zs_seq_table * ZsDec d * ZsFwd f i which i mode → v {
    : ( Vec i ) tab ? == which 0 . d llt ? == which 1 . d oft . d mlt
    : i maxlog ? == which 1 8 9
    : ~ i log -1
    ? == mode 0 {
        : i n ? == which 0 ( __zs_ll_default . d sc1 )
        ? == which 1 ( __zs_of_default . d sc1 )
        ( __zs_ml_default . d sc1 )
        = log ? == which 1 5 6
        ? != ( __zs_fse_build tab . d sc1 . d sc2 n log ) 0 {
            = . d err ZSE_CORRUPT
            ^ v
        } {}
    } { ? == mode 1 {
            ( __zs_fw_align f )
            : i at ( __zs_fw_bytepos f )
            ? >= at . f len { = . d err ZSE_CORRUPT ^ v } {}
            : *u fsp . f src
            ( __zs_fse_rle tab # i . fsp at )
            = . f bit << + at 1 3
            = log 0
        } { ? == mode 2 {
                : i hdr ( __zs_fse_header f . d sc1 maxlog )
                ? < hdr 0 { = . d err ZSE_CORRUPT ^ v } {}
                : i n & hdr 65535
                = log >> hdr 16
                ? != ( __zs_fse_build tab . d sc1 . d sc2 n log ) 0 {
                    = . d err ZSE_CORRUPT
                    ^ v
                } {}
            } {
                // Repeat: keep the table from the previous block.
                : i prev ? == which 0 . d lllog ? == which 1 . d oflog . d mllog
                ? < prev 0 { = . d err ZSE_CORRUPT ^ v } {}
                = log prev
            } } }
    ? == which 0 { = . d lllog log }
    { ? == which 1 { = . d oflog log } { = . d mllog log } }
}

// Copy `n` literals to the output, then a match of `ml` bytes from
// `offset` back. Overlapping copies are byte by byte on purpose: an
// offset of 1 is the format's run-length encoding.
@ __zs_emit * ZsDec d i ll i ml i offset → v {
    ? > + . d litpos ll . d litlen { = . d err ZSE_CORRUPT ^ v } {}
    ( __zs_need d + ll ml )
    ? != . d err 0 { ^ v } {}
    : *u op . d op
    : *u lp ( vec_data [u] . d lit )
    : ~ i o . d olen
    ? > ll 0 {
        ( nurl_memcpy # s # *u + # i op o
        # s # *u + # i lp . d litpos ll )
        = o + o ll
        = . d litpos + . d litpos ll
    } {}
    ? | <= offset 0 > offset - o . d framestart { = . d err ZSE_CORRUPT ^ v } {}
    // The match copy, in chunks of `offset` bytes. Each chunk reads
    // only bytes written before it started, so no single memcpy ever
    // overlaps — while the SEQUENCE of them still reproduces the
    // format's run semantics, where an offset of 1 means "repeat this
    // byte". A byte-at-a-time loop was a fifth of decode time.
    : ~ i left ml
    : ~ i dst o
    ~ > left 0 {
        : i chunk ? > offset left left offset
        ( nurl_memcpy # s # *u + # i op dst
        # s # *u + # i op - dst offset chunk )
        = dst + dst chunk
        = left - left chunk
    }
    = . d olen + o ml
}

// The offset code carries three recent offsets in slots 1..3; a
// sequence with no literals shifts the meaning of each slot by one.
@ __zs_offset * ZsDec d i code i ll → i {
    ? > code 3 {
        : i off - code 3
        = . d rep2 . d rep1
        = . d rep1 . d rep0
        = . d rep0 off
        ^ off
    } {}
    : i idx ? == ll 0 code - code 1
    ? == idx 0 { ^ . d rep0 } {}
    : i off ? == idx 1 . d rep1 ? == idx 2 . d rep2 - . d rep0 1
    ? > idx 1 { = . d rep2 . d rep1 } {}
    = . d rep1 . d rep0
    = . d rep0 off
    ^ off
}

@ __zs_sequences * ZsDec d * ZsFwd f i blocklen → v {
    : ~ i nseq ( __zs_fw_take f 8 )
    ? >= nseq 128 {
        ? == nseq 255 {
            = nseq + ( __zs_fw_take f 16 ) 0x7F00
        } {
            = nseq + << - nseq 128 8 ( __zs_fw_take f 8 )
        }
    } {}
    ? != . f err 0 { = . d err ZSE_CORRUPT ^ v } {}
    ? == nseq 0 {
        // No sequences: the block is its literals, and nothing else may
        // follow them.
        ( __zs_emit d . d litlen 0 1 )
        = . d litpos 0
        ^ v
    } {}
    : i modes ( __zs_fw_take f 8 )
    ? != . f err 0 { = . d err ZSE_CORRUPT ^ v } {}
    ? != & modes 3 0 { = . d err ZSE_CORRUPT ^ v } {}
    ( __zs_seq_table d f 0 & >> modes 6 3 )
    ( __zs_seq_table d f 1 & >> modes 4 3 )
    ( __zs_seq_table d f 2 & >> modes 2 3 )
    ? != . d err 0 { ^ v } {}
    ( __zs_fw_align f )
    : i at ( __zs_fw_bytepos f )
    ? >= at blocklen { = . d err ZSE_CORRUPT ^ v } {}
    : *ZsBk b ( nurl_alloc Z ZsBk )
    = . b src # *u + # i . f src at
    = . b len - blocklen at
    ? != ( __zs_bk_start b ) 0 {
        ( nurl_free # s b )
        = . d err ZSE_CORRUPT
        ^ v
    } {}
    : ( Vec i ) llx ( __zs_ll_extra )
    : ( Vec i ) mlx ( __zs_ml_extra )
    : ( Vec i ) llb ( __zs_ll_base llx )
    : ( Vec i ) mlb ( __zs_ml_base mlx )
    : *i llxp ( vec_data [i] llx )
    : *i mlxp ( vec_data [i] mlx )
    : *i llbp ( vec_data [i] llb )
    : *i mlbp ( vec_data [i] mlb )
    : *i lltp ( vec_data [i] . d llt )
    : *i oftp ( vec_data [i] . d oft )
    : *i mltp ( vec_data [i] . d mlt )
    // From here the bit cursor is a LOCAL. It is read six to eight times
    // per sequence, and as a field of the reader struct every one of
    // those was a load and a store the compiler could not eliminate.
    : *u bsp . b src
    : i blen . b len
    : ~ i boff . b off
    // States are initialized literals-length, offset, match-length.
    : i lllog . d lllog
    : i oflog . d oflog
    : i mllog . d mllog
    = boff - boff lllog
    : ~ i lls ( __zs_bits bsp blen boff lllog )
    = boff - boff oflog
    : ~ i ofs ( __zs_bits bsp blen boff oflog )
    = boff - boff mllog
    : ~ i mls ( __zs_bits bsp blen boff mllog )
    : ~ i n 0
    ~ & < n nseq == . d err 0 {
        : i ofe # i . oftp ofs
        : i lle # i . lltp lls
        : i mle # i . mltp mls
        : i ofc & ofe 255
        : i llc & lle 255
        : i mlc & mle 255
        ? | | > llc 35 > mlc 52 > ofc 63 { = . d err ZSE_CORRUPT } {
            // Values are read offset first, then match, then literals.
            = boff - boff ofc
            : i offcode + << 1 ofc ( __zs_bits bsp blen boff ofc )
            : i mlx # i . mlxp mlc
            = boff - boff mlx
            : i ml + # i . mlbp mlc ( __zs_bits bsp blen boff mlx )
            : i llx # i . llxp llc
            = boff - boff llx
            : i ll + # i . llbp llc ( __zs_bits bsp blen boff llx )
            : i off ( __zs_offset d offcode ll )
            ( __zs_emit d ll ml off )
            ? < + n 1 nseq {
                : i lnb & >> lle 8 255
                = boff - boff lnb
                = lls + >> lle 16 ( __zs_bits bsp blen boff lnb )
                : i mnb & >> mle 8 255
                = boff - boff mnb
                = mls + >> mle 16 ( __zs_bits bsp blen boff mnb )
                : i onb & >> ofe 8 255
                = boff - boff onb
                = ofs + >> ofe 16 ( __zs_bits bsp blen boff onb )
            } {}
        }
        = n + n 1
    }
    // The stream must be consumed exactly.
    ? & == . d err 0 != boff 0 { = . d err ZSE_CORRUPT } {}
    ( nurl_free # s b )
    ( vec_free [i] llx ) ( vec_free [i] mlx )
    ( vec_free [i] llb ) ( vec_free [i] mlb )
    ? != . d err 0 { ^ v } {}
    // Whatever literals the sequences did not consume close the block.
    ? < . d litpos . d litlen {
        ( __zs_emit d - . d litlen . d litpos 0 1 )
    } {}
    = . d litpos 0
}

// ── Blocks and frames ───────────────────────────────────────────────

@ __zs_block * ZsDec d i blocklen → v {
    : *ZsFwd f ( nurl_alloc Z ZsFwd )
    = . f src # *u + # i . d src . d pos
    = . f len blocklen
    = . f bit 0
    = . f err 0
    = . d litpos 0
    ( __zs_literals d f )
    ? == . d err 0 { ( __zs_sequences d f blocklen ) } {}
    ( nurl_free # s f )
}

@ __zs_u32 * ZsDec d i off → i {
    : *u sp . d src
    ^ | | | # i . sp off
    << # i . sp + off 1 8
    << # i . sp + off 2 16
    << # i . sp + off 3 24
}

@ __zs_frame * ZsDec d → v {
    : *u sp . d src
    // Frame_Header_Descriptor
    ? >= . d pos . d srclen { = . d err ZSE_TRUNC ^ v } {}
    : i desc # i . sp . d pos
    = . d pos + . d pos 1
    : i fcs_flag >> desc 6
    : i single & >> desc 5 1
    ? != & >> desc 3 1 0 { = . d err ZSE_CORRUPT ^ v } {}
    : i checksum & >> desc 2 1
    : i did_flag & desc 3
    : ~ i window 0
    ? == single 0 {
        ? >= . d pos . d srclen { = . d err ZSE_TRUNC ^ v } {}
        : i wd # i . sp . d pos
        = . d pos + . d pos 1
        : i base << 1 + 10 >> wd 3
        = window + base * >> base 3 & wd 7
    } {}
    ? != did_flag 0 {
        // A dictionary is named: without it the output would be wrong.
        = . d err ZSE_UNSUP
        ^ v
    } {}
    : ~ i fcs 0
    ? | != single 0 != fcs_flag 0 {
        : i nbytes ? == fcs_flag 0 1 ? == fcs_flag 1 2 ? == fcs_flag 2 4 8
        ? > + . d pos nbytes . d srclen { = . d err ZSE_TRUNC ^ v } {}
        : ~ i k 0
        ~ < k nbytes {
            = fcs | fcs << # i . sp + . d pos k * k 8
            = k + k 1
        }
        ? == nbytes 2 { = fcs + fcs 256 } {}
        = . d pos + . d pos nbytes
    } {}
    ? != single 0 { = window fcs } {}
    = . d window window
    = . d framestart . d olen
    = . d rep0 1
    = . d rep1 4
    = . d rep2 8
    = . d hufbits 0
    = . d lllog -1
    = . d oflog -1
    = . d mllog -1
    // Reserve the declared size up front — one allocation for the frame.
    ? > fcs 0 { ( __zs_need d fcs ) } {}
    ? != . d err 0 { ^ v } {}
    : ~ b last F
    ~ & ! last == . d err 0 {
        ? > + . d pos 3 . d srclen { = . d err ZSE_TRUNC ^ v } {}
        : i hdr | | # i . sp . d pos
        << # i . sp + . d pos 1 8
        << # i . sp + . d pos 2 16
        = . d pos + . d pos 3
        = last != & hdr 1 0
        : i btype & >> hdr 1 3
        : i blen >> hdr 3
        // An RLE block's Block_Size is what it REGENERATES; it occupies
        // exactly one byte of input. Bounding the read by blen would
        // reject every large run.
        : i inbytes ? == btype 1 1 blen
        ? > + . d pos inbytes . d srclen { = . d err ZSE_TRUNC ^ v } {}
        ? == btype 0 {
            ( __zs_need d blen )
            ? == . d err 0 {
                ? > blen 0 {
                    ( nurl_memcpy # s # *u + # i . d op . d olen
                    # s # *u + # i . d src . d pos blen )
                } {}
                = . d olen + . d olen blen
            } {}
            = . d pos + . d pos blen
        } { ? == btype 1 {
                ? != blen 0 {
                    ? == . d pos . d srclen { = . d err ZSE_TRUNC ^ v } {}
                    : i byte # i . sp . d pos
                    ( __zs_need d blen )
                    ? == . d err 0 {
                        : ~ i k 0
                        ~ < k blen { = . . d op + . d olen k # u byte = k + k 1 }
                        = . d olen + . d olen blen
                    } {}
                } {}
                = . d pos + . d pos 1
            } { ? == btype 2 {
                    ( __zs_block d blen )
                    = . d pos + . d pos blen
                } {
                    = . d err ZSE_CORRUPT
                } } }
    }
    ? != . d err 0 { ^ v } {}
    ? > fcs 0 {
        ? != - . d olen . d framestart fcs { = . d err ZSE_CORRUPT ^ v } {}
    } {}
    ? != checksum 0 {
        ? > + . d pos 4 . d srclen { = . d err ZSE_TRUNC ^ v } {}
        : i want ( __zs_u32 d . d pos )
        = . d pos + . d pos 4
        : i got & ( xxh64_ptr # *u + # i . d op . d framestart
        - . d olen . d framestart 0 ) 0xFFFFFFFF
        ? != got & want 0xFFFFFFFF { = . d err ZSE_CKSUM ^ v } {}
    } {}
}

// ── Public API ──────────────────────────────────────────────────────

@ __zs_new ( Vec u ) src i limit → *ZsDec {
    : *ZsDec d ( nurl_alloc Z ZsDec )
    = . d src ( vec_data [u] src )
    = . d srclen ( vec_len [u] src )
    = . d pos 0
    = . d out ( vec_new [u] )
    = . d op ( vec_data [u] . d out )
    = . d olen 0
    = . d ocap 0
    = . d limit limit
    = . d framestart 0
    = . d lit ( vec_with_cap [u] 1024 )
    = . d litlen 0
    = . d litcap ( vec_cap [u] . d lit )
    = . d litpos 0
    = . d huf ( __zs_zeros 2048 )
    = . d hufbits 0
    = . d llt ( __zs_zeros 512 )
    = . d lllog -1
    = . d oft ( __zs_zeros 256 )
    = . d oflog -1
    = . d mlt ( __zs_zeros 512 )
    = . d mllog -1
    = . d sc1 ( __zs_zeros 300 )
    = . d sc2 ( __zs_zeros 300 )
    = . d sc3 ( __zs_zeros 128 )
    = . d rep0 1
    = . d rep1 4
    = . d rep2 8
    = . d window 0
    = . d err 0
    ^ d
}

@ __zs_dispose * ZsDec d → v {
    ( vec_free [u] . d lit )
    ( vec_free [i] . d huf )
    ( vec_free [i] . d llt )
    ( vec_free [i] . d oft )
    ( vec_free [i] . d mlt )
    ( vec_free [i] . d sc1 )
    ( vec_free [i] . d sc2 )
    ( vec_free [i] . d sc3 )
    ( nurl_free # s d )
}

@ zstd_decode_limit ( Vec u ) src i max_out → !( Vec u ) ZstdErr {
    : i n ( vec_len [u] src )
    ? == n 0 {
        ^ @ !( Vec u ) ZstdErr { T ( vec_new [u] ) }
    } {}
    : *ZsDec d ( __zs_new src max_out )
    ~ & == . d err 0 < . d pos . d srclen {
        ? > + . d pos 4 . d srclen { = . d err ZSE_TRUNC } {
            : i magic ( __zs_u32 d . d pos )
            ? == magic ZS_MAGIC {
                = . d pos + . d pos 4
                ( __zs_frame d )
            } { ? & >= magic ZS_SKIP_LO <= magic ZS_SKIP_HI {
                    // A skippable frame carries a payload for someone else.
                    ? > + . d pos 8 . d srclen { = . d err ZSE_TRUNC } {
                        : i skip ( __zs_u32 d + . d pos 4 )
                        ? > + + . d pos 8 skip . d srclen { = . d err ZSE_TRUNC }
                        { = . d pos + + . d pos 8 skip }
                    }
                } { = . d err ZSE_MAGIC } }
        }
    }
    : i err . d err
    : ( Vec u ) out . d out
    : i olen . d olen
    ( __zs_dispose d )
    ? != err 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) ZstdErr { F ( __zs_err err ) }
    } {}
    : b ok ( vec_set_len [u] out olen )
    ? ! ok {
        ( vec_free [u] out )
        ^ @ !( Vec u ) ZstdErr { F # ZstdErr ZstdCorrupt }
    } {}
    ^ @ !( Vec u ) ZstdErr { T out }
}

@ zstd_decode ( Vec u ) src → !( Vec u ) ZstdErr {
    ^ ( zstd_decode_limit src 0x7FFFFFFFFFFFFFFF )
}

// ── Encoder ─────────────────────────────────────────────────────────
//
// A Lempel-Ziv match finder feeding FSE-coded sequences — the same
// shape as the reference compressor, minus the parts that trade code
// for the last few percent. Matches come from a hash table with a
// collision chain whose search depth is what `level` selects. The three
// sequence tables are the format's PREDEFINED distributions: they cost
// zero header bytes, which is the right trade until a block is large
// enough to pay for a custom table.
//
// The sequence bitstream is written so that reading it BACKWARD yields
// the format's order, which is why sequences are encoded last-to-first
// and each state is flushed at the end.

: i ZS_BLOCK_MAX 131072  // the format's largest block
: i ZS_MIN_MATCH 4  // the hash indexes 4 bytes, so matches start there
// What a literal costs, in bits, when the match finder is deciding
// whether a longer-but-further match is worth its offset. Literals are
// Huffman-coded, so they are NOT eight bits each; pricing them at eight
// overvalues distance and makes a deeper search compress WORSE — which
// is exactly what level 12 did against level 1 before this was a price.
: i ZS_LIT_BITS 5

@ __zs_pu32 ( Vec u ) v i x → v {
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
}

// ── A bit writer whose output is read from the end ──────────────────

: ZsBw {
    ( Vec u ) buf
    i acc  // pending bits, LSB first
    i bits  // how many are pending
}

@ __zs_bw_add * ZsBw w i val i n → v {
    ? <= n 0 { ^ v } {}
    = . w acc | . w acc << & val - << 1 n 1 . w bits
    = . w bits + . w bits n
    ~ >= . w bits 8 {
        ( vec_push [u] . w buf # u & . w acc 255 )
        = . w acc >> # u64 . w acc 8
        = . w bits - . w bits 8
    }
}

// Close the stream: a single 1 bit marks the last information bit, and
// the rest of the byte is zero padding the decoder skips.
@ __zs_bw_close * ZsBw w → v {
    ( __zs_bw_add w 1 1 )
    ? > . w bits 0 {
        ( vec_push [u] . w buf # u & . w acc 255 )
        = . w acc 0
        = . w bits 0
    } {}
}

// ── FSE encoding table ──────────────────────────────────────────────

: ZsCt {
    ( Vec i ) next  // next-state table in cumulative symbol order
    ( Vec i ) dnb  // per symbol: delta applied to derive the bit count
    ( Vec i ) dfs  // per symbol: offset into `next`
    i log
}

@ __zs_ct_free ZsCt ct → v {
    ( vec_free [i] . ct next )
    ( vec_free [i] . ct dnb )
    ( vec_free [i] . ct dfs )
}

// Mirror of `__zs_fse_build`: the same spread, read the other way.
@ __zs_ct_build ( Vec i ) freq i nsym i log → ZsCt {
    : i size << 1 log
    : ( Vec i ) next ( __zs_zeros size )
    : ( Vec i ) dnb ( __zs_zeros ? > nsym 0 nsym 1 )
    : ( Vec i ) dfs ( __zs_zeros ? > nsym 0 nsym 1 )
    : ( Vec i ) symbol ( __zs_zeros size )
    : ( Vec i ) cumul ( __zs_zeros + nsym 2 )
    : *i fp ( vec_data [i] freq )
    : *i np ( vec_data [i] next )
    : *i dnbp ( vec_data [i] dnb )
    : *i dfsp ( vec_data [i] dfs )
    : *i sp ( vec_data [i] symbol )
    : *i cp ( vec_data [i] cumul )
    // Start positions per symbol; a "less than one" symbol takes a
    // single cell from the top of the table.
    : ~ i high size
    : ~ i s 0
    ~ < s nsym {
        : i c # i . fp s
        ? == c -1 {
            = . cp + s 1 + # i . cp s 1
            = high - high 1
            = . sp high s
        } {
            = . cp + s 1 + # i . cp s c
        }
        = s + s 1
    }
    : i step + + >> size 1 >> size 3 3
    : i mask - size 1
    : ~ i pos 0
    = s 0
    ~ < s nsym {
        : i c # i . fp s
        ? > c 0 {
            : ~ i k 0
            ~ < k c {
                = . sp pos s
                = pos & + pos step mask
                ~ >= pos high { = pos & + pos step mask }
                = k + k 1
            }
        } {}
        = s + s 1
    }
    // Each cell records the state a symbol lands in, in symbol order.
    : ~ i u 0
    ~ < u size {
        : i sym # i . sp u
        : i at # i . cp sym
        = . cp sym + at 1
        = . np at + size u
        = u + u 1
    }
    // Per-symbol transform: how many bits leave the state, and where in
    // `next` this symbol's cells begin.
    : ~ i total 0
    = s 0
    ~ < s nsym {
        : i c # i . fp s
        ? | == c 1 == c -1 {
            = . dnbp s - << log 16 size
            = . dfsp s - total 1
            = total + total 1
        } { ? > c 1 {
                : i maxbits - log ( __zs_hbit - c 1 )
                = . dnbp s - << maxbits 16 << c maxbits
                = . dfsp s - total c
                = total + total c
            } {} }
        = s + s 1
    }
    ( vec_free [i] symbol )
    ( vec_free [i] cumul )
    ^ @ ZsCt { next dnb dfs log }
}

@ __zs_ct_init ZsCt ct i sym → i {
    : *i dnbp ( vec_data [i] . ct dnb )
    : *i dfsp ( vec_data [i] . ct dfs )
    : *i np ( vec_data [i] . ct next )
    : i dnb # i . dnbp sym
    : i nb >> + dnb 32768 16
    : i v - << nb 16 dnb
    ^ # i . np + >> v nb # i . dfsp sym
}

@ __zs_ct_encode * ZsBw w ZsCt ct i state i sym → i {
    : *i dnbp ( vec_data [i] . ct dnb )
    : *i dfsp ( vec_data [i] . ct dfs )
    : *i np ( vec_data [i] . ct next )
    : i nb >> + state # i . dnbp sym 16
    ( __zs_bw_add w state nb )
    ^ # i . np + >> state nb # i . dfsp sym
}

@ __zs_ct_flush * ZsBw w ZsCt ct i state → v {
    ( __zs_bw_add w state . ct log )
}

// ── Code assignment ─────────────────────────────────────────────────

@ __zs_ll_code ( Vec i ) base i ll → i {
    ? < ll 16 { ^ ll } {}
    : *i p ( vec_data [i] base )
    : ~ i c 16
    ~ & < c 35 <= # i . p + c 1 ll { = c + c 1 }
    ^ c
}

@ __zs_ml_code ( Vec i ) base i ml → i {
    ? < ml 35 { ^ - ml 3 } {}
    : *i p ( vec_data [i] base )
    : ~ i c 32
    ~ & < c 52 <= # i . p + c 1 ml { = c + c 1 }
    ^ c
}

// ── Match finder ────────────────────────────────────────────────────

@ __zs_hash4 * u p i at i hlog → i {
    : i v | | | # i . p at << # i . p + at 1 8
    << # i . p + at 2 16 << # i . p + at 3 24
    ^ & >> # u64 * v 2654435761 - 32 hlog - << 1 hlog 1
}

@ __zs_matchlen * u p i a i b i limit → i {
    : ~ i k 0
    ~ & < + b k limit == # i . p + a k # i . p + b k { = k + k 1 }
    ^ k
}

// ── Huffman-coded literals ──────────────────────────────────────────
//
// Literals are half the output of a text block, so coding them is the
// difference between "a valid frame" and "a competitive one".
//
// Code lengths come from an ordinary Huffman merge over the block's
// byte counts. The format caps a code at 11 bits; when the merge
// produces a deeper tree the counts are halved and the merge repeats,
// which converges quickly and costs a fraction of a percent against a
// length-limited construction.

@ __zs_huf_merge ( Vec i ) counts ( Vec i ) lens i nsym → i {
    : ( Vec i ) cnt ( __zs_zeros * 2 ZS_MAX_SYMS )
    : ( Vec i ) par ( __zs_zeros * 2 ZS_MAX_SYMS )
    : ( Vec i ) live ( __zs_zeros * 2 ZS_MAX_SYMS )
    : *i cp ( vec_data [i] counts )
    : *i lp ( vec_data [i] lens )
    : *i c ( vec_data [i] cnt )
    : *i pa ( vec_data [i] par )
    : *i lv ( vec_data [i] live )
    : ~ i nodes 0
    : ~ i present 0
    : ~ i s 0
    ~ < s nsym {
        = . lp s 0
        ? > # i . cp s 0 {
            = . c s # i . cp s
            = . lv s 1
            = present + present 1
        } {}
        = s + s 1
    }
    = nodes nsym
    ? == present 0 { ( vec_free [i] cnt ) ( vec_free [i] par ) ( vec_free [i] live ) ^ 0 } {}
    ? == present 1 {
        // A single distinct byte still needs a one-bit code.
        = s 0
        ~ < s nsym { ? > # i . cp s 0 { = . lp s 1 } {} = s + s 1 }
        ( vec_free [i] cnt ) ( vec_free [i] par ) ( vec_free [i] live )
        ^ 1
    } {}
    : ~ i remaining present
    ~ > remaining 1 {
        // Two lightest live nodes become one.
        : ~ i a -1
        : ~ i b -1
        : ~ i k 0
        ~ < k nodes {
            ? != # i . lv k 0 {
                ? | == a -1 < # i . c k # i . c a { = b a = a k }
                { ? | == b -1 < # i . c k # i . c b { = b k } {} }
            } {}
            = k + k 1
        }
        = . lv a 0
        = . lv b 0
        : i n nodes
        = nodes + nodes 1
        = . c n + # i . c a # i . c b
        = . lv n 1
        = . pa a n
        = . pa b n
        = . pa n -1
        = remaining - remaining 1
    }
    // Depth of each leaf is its code length.
    : ~ i maxb 0
    = s 0
    ~ < s nsym {
        ? > # i . cp s 0 {
            : ~ i d 0
            : ~ i k s
            ~ != # i . pa k -1 { = k # i . pa k = d + d 1 }
            = . lp s d
            ? > d maxb { = maxb d } {}
        } {}
        = s + s 1
    }
    ( vec_free [i] cnt ) ( vec_free [i] par ) ( vec_free [i] live )
    ^ maxb
}

// Code lengths for the block's literals, capped at 11 bits.
@ __zs_huf_lengths ( Vec i ) counts ( Vec i ) lens i nsym → i {
    : ~ i maxb ( __zs_huf_merge counts lens nsym )
    : *i cp ( vec_data [i] counts )
    : ~ i guard 0
    ~ & > maxb ZS_MAX_HUF_BITS < guard 32 {
        // Flatten the distribution and try again: a tree over halved
        // counts is shallower, and the coding loss is negligible.
        : ~ i s 0
        ~ < s nsym {
            : i c # i . cp s
            ? > c 0 { = . cp s ? > >> c 1 1 >> c 1 1 } {}
            = s + s 1
        }
        = maxb ( __zs_huf_merge counts lens nsym )
        = guard + guard 1
    }
    ^ maxb
}

// Canonical codes, assigned longest-first so they agree with the way a
// decoder lays its table out.
@ __zs_huf_codes ( Vec i ) lens ( Vec i ) codes i nsym i maxb → v {
    : ( Vec i ) rank ( __zs_zeros 16 )
    : ( Vec i ) val ( __zs_zeros 16 )
    : *i lp ( vec_data [i] lens )
    : *i cop ( vec_data [i] codes )
    : *i rp ( vec_data [i] rank )
    : *i vp ( vec_data [i] val )
    : ~ i s 0
    ~ < s nsym {
        : i L # i . lp s
        ? > L 0 { = . rp L + # i . rp L 1 } {}
        = s + s 1
    }
    : ~ i min 0
    : ~ i n maxb
    ~ > n 0 {
        = . vp n min
        = min >> + min # i . rp n 1
        = n - n 1
    }
    = s 0
    ~ < s nsym {
        : i L # i . lp s
        ? > L 0 {
            = . cop s # i . vp L
            = . vp L + # i . vp L 1
        } { = . cop s 0 }
        = s + s 1
    }
    ( vec_free [i] rank )
    ( vec_free [i] val )
}

// Flush a forward bitstream: no end marker, just zero padding. Header
// bitstreams are read forward and their length is known, so the 1-bit
// terminator a backward stream needs would be one bit of corruption.
@ __zs_bw_close_fwd * ZsBw w → v {
    ? > . w bits 0 {
        ( vec_push [u] . w buf # u & . w acc 255 )
        = . w acc 0
        = . w bits 0
    } {}
}

// Scale counts onto a table of 1<<log cells. Every symbol that occurs
// keeps at least one cell; the rounding error lands on the largest.
// Returns the highest symbol with a cell, or -1.
@ __zs_normalize ( Vec i ) counts ( Vec i ) norm i nsym i log → i {
    : *i cp ( vec_data [i] counts )
    : *i np ( vec_data [i] norm )
    : i scale << 1 log
    : ~ i total 0
    : ~ i s 0
    ~ < s nsym { = total + total # i . cp s = s + s 1 }
    ? <= total 0 { ^ -1 } {}
    : ~ i sum 0
    : ~ i big 0
    = s 0
    ~ < s nsym {
        : i c # i . cp s
        : ~ i q 0
        ? > c 0 {
            = q / * c scale total
            ? < q 1 { = q 1 } {}
        } {}
        = . np s q
        = sum + sum q
        ? > q # i . np big { = big s } {}
        = s + s 1
    }
    // Reconcile: the largest symbol absorbs the difference, and if that
    // is not enough, take from every symbol that can spare a cell.
    ~ != sum scale {
        ? < sum scale {
            = . np big + # i . np big - scale sum
            = sum scale
        } {
            : i over - sum scale
            : i can - # i . np big 1
            ? >= can over {
                = . np big - # i . np big over
                = sum scale
            } {
                = . np big 1
                = sum - sum can
                = s 0
                ~ & < s nsym > sum scale {
                    ? > # i . np s 1 {
                        : i take ? > - # i . np s 1 - sum scale - sum scale - # i . np s 1
                        = . np s - # i . np s take
                        = sum - sum take
                    } {}
                    = s + s 1
                }
                ? != sum scale { ^ -1 } {}
            }
        }
    }
    : ~ i maxsym -1
    = s 0
    ~ < s nsym { ? > # i . np s 0 { = maxsym s } {} = s + s 1 }
    ^ maxsym
}

// Write a normalized distribution — the exact inverse of the reader in
// `__zs_fse_header`, sharing its shrinking field width and its 2-bit
// runs of zero-probability symbols.
@ __zs_write_ncount * ZsBw w ( Vec i ) norm i nsym i log → v {
    : *i np ( vec_data [i] norm )
    ( __zs_bw_add w - log 5 4 )
    : i size << 1 log
    : ~ i remaining + size 1
    : ~ i threshold size
    : ~ i nbits + log 1
    : ~ i s 0
    : ~ b prev0 F
    ~ & < s nsym > remaining 1 {
        ? prev0 {
            // Skip the run of zeros and spell its length in 2-bit
            // groups, chaining on 3.
            : ~ i start s
            ~ & < s nsym == # i . np s 0 { = s + s 1 }
            ? >= s nsym { = prev0 F } {
                ~ >= s + start 3 {
                    = start + start 3
                    ( __zs_bw_add w 3 2 )
                }
                ( __zs_bw_add w - s start 2 )
                = prev0 F
            }
        } {
            : i c # i . np s
            = s + s 1
            : i max - - * 2 threshold 1 remaining
            = remaining - remaining ? < c 0 - 0 c c
            : ~ i v + c 1
            ? >= v threshold { = v + v max } {}
            ( __zs_bw_add w v ? < v max - nbits 1 nbits )
            = prev0 == v 1
            ~ < remaining threshold {
                = nbits - nbits 1
                = threshold >> threshold 1
            }
        }
    }
}

// The Huffman tree description in its FSE-coded form: needed whenever
// the block uses a literal byte above 128, since the direct form's
// header byte cannot count that far.
@ __zs_tree_fse ( Vec u ) tree ( Vec i ) wts i nw i maxb → b {
    ? < nw 4 { ^ F } {}
    : i alpha + maxb 1
    : ( Vec i ) counts ( __zs_zeros 16 )
    : ( Vec i ) norm ( __zs_zeros 16 )
    : *i cp ( vec_data [i] counts )
    : *i wp ( vec_data [i] wts )
    : ~ i k 0
    ~ < k nw { : i x # i . wp k = . cp x + # i . cp x 1 = k + k 1 }
    : i log 6
    : i maxsym ( __zs_normalize counts norm alpha log )
    ? < maxsym 1 { ( vec_free [i] counts ) ( vec_free [i] norm ) ^ F } {}
    : ZsCt ct ( __zs_ct_build norm + maxsym 1 log )
    : *ZsBw w ( nurl_alloc Z ZsBw )
    = . w buf ( vec_new [u] )
    = . w acc 0
    = . w bits 0
    ( __zs_write_ncount w norm + maxsym 1 log )
    ( __zs_bw_close_fwd w )
    // Two states, even weights on the first, odd on the second, encoded
    // from the end so a backward reader replays them in order.
    : ~ i ip nw
    : ~ i s1 0
    : ~ i s2 0
    ? != & nw 1 0 {
        = ip - ip 1
        = s1 ( __zs_ct_init ct # i . wp ip )
        = ip - ip 1
        = s2 ( __zs_ct_init ct # i . wp ip )
        = ip - ip 1
        = s1 ( __zs_ct_encode w ct s1 # i . wp ip )
    } {
        = ip - ip 1
        = s2 ( __zs_ct_init ct # i . wp ip )
        = ip - ip 1
        = s1 ( __zs_ct_init ct # i . wp ip )
    }
    ~ > ip 0 {
        = ip - ip 1
        = s2 ( __zs_ct_encode w ct s2 # i . wp ip )
        = ip - ip 1
        = s1 ( __zs_ct_encode w ct s1 # i . wp ip )
    }
    ( __zs_ct_flush w ct s2 )
    ( __zs_ct_flush w ct s1 )
    ( __zs_bw_close w )
    : i n ( vec_len [u] . w buf )
    : ~ b ok F
    ? & > n 0 < n 128 {
        ( vec_push [u] tree # u n )
        ( vec_extend [u] tree . w buf )
        = ok T
    } {}
    ( vec_free [u] . w buf )
    ( nurl_free # s w )
    ( __zs_ct_free ct )
    ( vec_free [i] counts )
    ( vec_free [i] norm )
    ^ ok
}

// One Huffman bitstream over lits[from, to), written so that reading it
// backward replays the symbols in order.
@ __zs_huf_stream_enc ( Vec u ) dst ( Vec u ) lits i from i to
( Vec i ) lens ( Vec i ) codes → i {
    : *ZsBw w ( nurl_alloc Z ZsBw )
    = . w buf ( vec_new [u] )
    = . w acc 0
    = . w bits 0
    : *u lp ( vec_data [u] lits )
    : *i lnp ( vec_data [i] lens )
    : *i cop ( vec_data [i] codes )
    : ~ i k to
    ~ > k from {
        : i sym # i . lp - k 1
        ( __zs_bw_add w # i . cop sym # i . lnp sym )
        = k - k 1
    }
    ( __zs_bw_close w )
    : i n ( vec_len [u] . w buf )
    ( vec_extend [u] dst . w buf )
    ( vec_free [u] . w buf )
    ( nurl_free # s w )
    ^ n
}

// Write the literals section. Returns T when it went out Huffman-coded,
// F when raw literals were smaller (or the tree could not be sent).
@ __zs_lit_compress ( Vec u ) body ( Vec u ) lits → b {
    : i n ( vec_len [u] lits )
    ? < n 64 { ^ F } {}
    : ( Vec i ) counts ( __zs_zeros ZS_MAX_SYMS )
    : *i cnp ( vec_data [i] counts )
    : *u lp ( vec_data [u] lits )
    : ~ i k 0
    ~ < k n { : i c # i . lp k = . cnp c + # i . cnp c 1 = k + k 1 }
    // The tree description is 4 bits per symbol up to the last one
    // present, and its header byte only reaches 128 symbols.
    : ~ i last 0
    : ~ i s 0
    ~ < s ZS_MAX_SYMS { ? > # i . cnp s 0 { = last s } {} = s + s 1 }
    ? == last 0 { ( vec_free [i] counts ) ^ F } {}
    : ( Vec i ) lens ( __zs_zeros ZS_MAX_SYMS )
    : ( Vec i ) codes ( __zs_zeros ZS_MAX_SYMS )
    : i maxb ( __zs_huf_lengths counts lens ZS_MAX_SYMS )
    ? | <= maxb 0 > maxb ZS_MAX_HUF_BITS {
        ( vec_free [i] counts ) ( vec_free [i] lens ) ( vec_free [i] codes )
        ^ F
    } {}
    ( __zs_huf_codes lens codes ZS_MAX_SYMS maxb )
    // Tree description: weight = maxbits + 1 - length. The last
    // symbol's weight is what completes the power of two, so it is
    // never transmitted.
    : ( Vec i ) wts ( __zs_zeros ? > last 0 last 1 )
    : *i lnp ( vec_data [i] lens )
    : *i wtp ( vec_data [i] wts )
    = s 0
    ~ < s last {
        : i L # i . lnp s
        = . wtp s ? > L 0 - + maxb 1 L 0
        = s + s 1
    }
    // Two ways to send it: four bits per weight, or the weights
    // themselves FSE-coded. The direct form cannot count past 128
    // symbols, so a block with a high literal byte has only one option.
    : ( Vec u ) tdir ( vec_new [u] )
    ? <= last 128 {
        ( vec_push [u] tdir # u + 127 last )
        : ~ i acc 0
        = s 0
        ~ < s last {
            : i wgt # i . wtp s
            ? == & s 1 0 { = acc << wgt 4 } { ( vec_push [u] tdir # u | acc wgt ) }
            = s + s 1
        }
        ? != & last 1 0 { ( vec_push [u] tdir # u acc ) } {}
    } {}
    : ( Vec u ) tfse ( vec_new [u] )
    : b okfse ( __zs_tree_fse tfse wts last maxb )
    : i ndir ( vec_len [u] tdir )
    : i nfse ( vec_len [u] tfse )
    : ( Vec u ) tree ( vec_new [u] )
    ? & > ndir 0 | ! okfse <= ndir nfse {
        ( vec_extend [u] tree tdir )
    } { ? okfse { ( vec_extend [u] tree tfse ) } {} }
    ( vec_free [u] tdir )
    ( vec_free [u] tfse )
    ( vec_free [i] wts )
    ? == ( vec_len [u] tree ) 0 {
        ( vec_free [u] tree )
        ( vec_free [i] counts ) ( vec_free [i] lens ) ( vec_free [i] codes )
        ^ F
    } {}
    // Four streams above 1023 literals, because that is the only shape
    // the larger size formats describe.
    : ( Vec u ) payload ( vec_with_cap [u] + n 32 )
    : ~ i nstreams 1
    ? <= n 1023 {
        : i _s1 ( __zs_huf_stream_enc payload lits 0 n lens codes )
    } {
        = nstreams 4
        : i seg >> + n 3 2
        : i e1 ? > seg n n seg
        : i e2 ? > * 2 seg n n * 2 seg
        : i e3 ? > * 3 seg n n * 3 seg
        : ( Vec u ) s1 ( vec_new [u] )
        : ( Vec u ) s2 ( vec_new [u] )
        : ( Vec u ) s3 ( vec_new [u] )
        : ( Vec u ) s4 ( vec_new [u] )
        : i n1 ( __zs_huf_stream_enc s1 lits 0 e1 lens codes )
        : i n2 ( __zs_huf_stream_enc s2 lits e1 e2 lens codes )
        : i n3 ( __zs_huf_stream_enc s3 lits e2 e3 lens codes )
        : i _n4 ( __zs_huf_stream_enc s4 lits e3 n lens codes )
        ( vec_push [u] payload # u & n1 255 )
        ( vec_push [u] payload # u & >> n1 8 255 )
        ( vec_push [u] payload # u & n2 255 )
        ( vec_push [u] payload # u & >> n2 8 255 )
        ( vec_push [u] payload # u & n3 255 )
        ( vec_push [u] payload # u & >> n3 8 255 )
        ( vec_extend [u] payload s1 )
        ( vec_extend [u] payload s2 )
        ( vec_extend [u] payload s3 )
        ( vec_extend [u] payload s4 )
        ( vec_free [u] s1 ) ( vec_free [u] s2 )
        ( vec_free [u] s3 ) ( vec_free [u] s4 )
    }
    : i treelen ( vec_len [u] tree )
    : i csize + treelen ( vec_len [u] payload )
    // Each size format describes only so large a section; pick the one
    // that fits, and fall back to raw literals if none does.
    : b one == nstreams 1
    : b fits ? one & <= csize 1023 <= n 1023
    & <= n 262143 <= csize 262143
    : i hdrlen ? one 3 ? & <= n 16383 <= csize 16383 4 5
    // Only worth it if the whole section beats raw literals.
    : b win & fits < + hdrlen csize n
    ? win {
        ? one {
            : i hv | | 2 << 0 2 | << n 4 << csize 14
            ( vec_push [u] body # u & hv 255 )
            ( vec_push [u] body # u & >> hv 8 255 )
            ( vec_push [u] body # u & >> hv 16 255 )
        } { ? == hdrlen 4 {
                : i hv | | 2 << 2 2 | << n 4 << csize 18
                ( vec_push [u] body # u & hv 255 )
                ( vec_push [u] body # u & >> hv 8 255 )
                ( vec_push [u] body # u & >> hv 16 255 )
                ( vec_push [u] body # u & >> hv 24 255 )
            } {
                : i hv | | 2 << 3 2 | << n 4 << csize 22
                ( vec_push [u] body # u & hv 255 )
                ( vec_push [u] body # u & >> hv 8 255 )
                ( vec_push [u] body # u & >> hv 16 255 )
                ( vec_push [u] body # u & >> hv 24 255 )
                ( vec_push [u] body # u & >> # u64 hv 32 255 )
            } }
        ( vec_extend [u] body tree )
        ( vec_extend [u] body payload )
    } {}
    : b used win
    ( vec_free [u] tree )
    ( vec_free [u] payload )
    ( vec_free [i] counts )
    ( vec_free [i] lens )
    ( vec_free [i] codes )
    ^ used
}

// ── Block assembly ──────────────────────────────────────────────────

@ __zs_lit_header ( Vec u ) body i n → v {
    ? < n 32 {
        ( vec_push [u] body # u << n 3 )
    } { ? < n 4096 {
            : i hv | 4 << n 4
            ( vec_push [u] body # u & hv 255 )
            ( vec_push [u] body # u & >> hv 8 255 )
        } {
            : i hv | 12 << n 4
            ( vec_push [u] body # u & hv 255 )
            ( vec_push [u] body # u & >> hv 8 255 )
            ( vec_push [u] body # u & >> hv 16 255 )
        } }
}

@ __zs_nseq_header ( Vec u ) body i n → v {
    ? < n 128 {
        ( vec_push [u] body # u n )
    } { ? < n 0x7F00 {
            ( vec_push [u] body # u + 128 >> n 8 )
            ( vec_push [u] body # u & n 255 )
        } {
            ( vec_push [u] body # u 255 )
            : i r - n 0x7F00
            ( vec_push [u] body # u & r 255 )
            ( vec_push [u] body # u & >> r 8 255 )
        } }
}

@ __zs_block_header ( Vec u ) out i btype i size i last → v {
    : i hdr | | last << btype 1 << size 3
    ( vec_push [u] out # u & hdr 255 )
    ( vec_push [u] out # u & >> hdr 8 255 )
    ( vec_push [u] out # u & >> hdr 16 255 )
}

// Write one block: the sequences if they pay for themselves, the raw
// bytes if they do not. A compressed block that is not smaller than its
// content is not allowed to be written as one.
// Pick and emit one sequence table. A block with enough sequences pays
// for a distribution of its own; a short one takes the predefined table
// and spends no header bytes at all. `modeslot[0]` receives the mode.
@ __zs_seq_ctable ( Vec u ) tabs ( Vec i ) counts i nsym i maxlog i nseq
( Vec i ) deffreq i defn i deflog ( Vec i ) modeslot → ZsCt {
    : *i mp ( vec_data [i] modeslot )
    ? >= nseq 24 {
        : ( Vec i ) norm ( __zs_zeros ? > nsym 0 nsym 1 )
        // Resolution the sequence count can pay for, floored at what
        // the alphabet needs and capped at what the format allows.
        : ~ i log - ( __zs_hbit - nseq 1 ) 2
        : i minlog + ( __zs_hbit nsym ) 1
        ? < log minlog { = log minlog } {}
        ? < log 5 { = log 5 } {}
        ? > log maxlog { = log maxlog } {}
        : i maxsym ( __zs_normalize counts norm nsym log )
        ? > maxsym 0 {
            : *ZsBw w ( nurl_alloc Z ZsBw )
            = . w buf ( vec_new [u] )
            = . w acc 0
            = . w bits 0
            ( __zs_write_ncount w norm + maxsym 1 log )
            ( __zs_bw_close_fwd w )
            ( vec_extend [u] tabs . w buf )
            ( vec_free [u] . w buf )
            ( nurl_free # s w )
            : ZsCt ct ( __zs_ct_build norm + maxsym 1 log )
            ( vec_free [i] norm )
            = . mp 0 2
            ^ ct
        } {}
        ( vec_free [i] norm )
    } {}
    = . mp 0 0
    ^ ( __zs_ct_build deffreq defn deflog )
}

@ __zs_write_block ( Vec u ) out ( Vec u ) src i bstart i blen i last
( Vec u ) lits ( Vec i ) sll ( Vec i ) sml ( Vec i ) soff
( Vec i ) llb ( Vec i ) mlb ( Vec i ) llx ( Vec i ) mlx → v {
    : i nseq ( vec_len [i] sll )
    : i nlit ( vec_len [u] lits )
    : ( Vec u ) body ( vec_with_cap [u] + blen 64 )
    ? ! ( __zs_lit_compress body lits ) {
        ( __zs_lit_header body nlit )
        ( vec_extend [u] body lits )
    } {}
    ( __zs_nseq_header body nseq )
    ? > nseq 0 {
        : *i llp ( vec_data [i] sll )
        : *i mlp ( vec_data [i] sml )
        : *i ofp ( vec_data [i] soff )
        : *i llxp ( vec_data [i] llx )
        : *i mlxp ( vec_data [i] mlx )
        : *i llbp ( vec_data [i] llb )
        : *i mlbp ( vec_data [i] mlb )
        // Codes first: they are needed twice, to count and to encode.
        : ( Vec i ) llc ( __zs_zeros nseq )
        : ( Vec i ) mlc ( __zs_zeros nseq )
        : ( Vec i ) ofc ( __zs_zeros nseq )
        : ( Vec i ) llcnt ( __zs_zeros 36 )
        : ( Vec i ) mlcnt ( __zs_zeros 53 )
        : ( Vec i ) ofcnt ( __zs_zeros 32 )
        : *i llcp ( vec_data [i] llc )
        : *i mlcp ( vec_data [i] mlc )
        : *i ofcp ( vec_data [i] ofc )
        : *i llnp ( vec_data [i] llcnt )
        : *i mlnp ( vec_data [i] mlcnt )
        : *i ofnp ( vec_data [i] ofcnt )
        : ~ i k 0
        ~ < k nseq {
            : i a ( __zs_ll_code llb # i . llp k )
            : i b ( __zs_ml_code mlb # i . mlp k )
            : i c ( __zs_hbit # i . ofp k )
            = . llcp k a
            = . mlcp k b
            = . ofcp k c
            = . llnp a + # i . llnp a 1
            = . mlnp b + # i . mlnp b 1
            = . ofnp c + # i . ofnp c 1
            = k + k 1
        }
        // Tables, into a side buffer: the mode byte that describes them
        // has to be written first.
        : ( Vec i ) deffreq ( __zs_zeros 64 )
        : ( Vec i ) modeslot ( __zs_zeros 3 )
        : ( Vec u ) tabs ( vec_new [u] )
        : *i msp ( vec_data [i] modeslot )
        : i lldefn ( __zs_ll_default deffreq )
        : ZsCt llct ( __zs_seq_ctable tabs llcnt 36 9 nseq deffreq lldefn 6 modeslot )
        : i llmode # i . msp 0
        : i ofdefn ( __zs_of_default deffreq )
        : ZsCt ofct ( __zs_seq_ctable tabs ofcnt 32 8 nseq deffreq ofdefn 5 modeslot )
        : i ofmode # i . msp 0
        : i mldefn ( __zs_ml_default deffreq )
        : ZsCt mlct ( __zs_seq_ctable tabs mlcnt 53 9 nseq deffreq mldefn 6 modeslot )
        : i mlmode # i . msp 0
        ( vec_push [u] body # u | | << llmode 6 << ofmode 4 << mlmode 2 )
        ( vec_extend [u] body tabs )
        : *ZsBw w ( nurl_alloc Z ZsBw )
        = . w buf ( vec_new [u] )
        = . w acc 0
        = . w bits 0
        // Encoded last sequence first: the decoder reads backward.
        : i lastn - nseq 1
        : i llc0 # i . llcp lastn
        : i mlc0 # i . mlcp lastn
        : i ofc0 # i . ofcp lastn
        : ~ i lls ( __zs_ct_init llct llc0 )
        : ~ i ofs ( __zs_ct_init ofct ofc0 )
        : ~ i mls ( __zs_ct_init mlct mlc0 )
        ( __zs_bw_add w - # i . llp lastn # i . llbp llc0 # i . llxp llc0 )
        ( __zs_bw_add w - # i . mlp lastn # i . mlbp mlc0 # i . mlxp mlc0 )
        ( __zs_bw_add w - # i . ofp lastn << 1 ofc0 ofc0 )
        : ~ i n - nseq 2
        ~ >= n 0 {
            : i a # i . llcp n
            : i b # i . mlcp n
            : i c # i . ofcp n
            // Offset, match, then literals: the reverse of the order a
            // decoder updates its states in, because it reads this
            // stream from the far end.
            = ofs ( __zs_ct_encode w ofct ofs c )
            = mls ( __zs_ct_encode w mlct mls b )
            = lls ( __zs_ct_encode w llct lls a )
            ( __zs_bw_add w - # i . llp n # i . llbp a # i . llxp a )
            ( __zs_bw_add w - # i . mlp n # i . mlbp b # i . mlxp b )
            ( __zs_bw_add w - # i . ofp n << 1 c c )
            = n - n 1
        }
        ( __zs_ct_flush w mlct mls )
        ( __zs_ct_flush w ofct ofs )
        ( __zs_ct_flush w llct lls )
        ( __zs_bw_close w )
        ( vec_extend [u] body . w buf )
        ( vec_free [u] . w buf )
        ( nurl_free # s w )
        ( __zs_ct_free llct )
        ( __zs_ct_free ofct )
        ( __zs_ct_free mlct )
        ( vec_free [u] tabs )
        ( vec_free [i] deffreq )
        ( vec_free [i] modeslot )
        ( vec_free [i] llc ) ( vec_free [i] mlc ) ( vec_free [i] ofc )
        ( vec_free [i] llcnt ) ( vec_free [i] mlcnt ) ( vec_free [i] ofcnt )
    } {}
    : i bodylen ( vec_len [u] body )
    ? < bodylen blen {
        ( __zs_block_header out 2 bodylen last )
        ( vec_extend [u] out body )
    } {
        ( __zs_block_header out 0 blen last )
        ( vec_extend_range [u] out src bstart blen )
    }
    ( vec_free [u] body )
}

// Frame header. The window has to cover the largest match distance the
// block encoder can emit, and the declared content size lets a decoder
// allocate the output in one go.
@ __zs_write_header ( Vec u ) out i srclen → v {
    ( __zs_pu32 out ZS_MAGIC )
    : i fcs_flag ? <= srclen 0xFFFFFFFF 2 3
    : ~ i wlog 10
    ~ & < wlog 27 < << 1 wlog srclen { = wlog + wlog 1 }
    : i desc | << fcs_flag 6 4  // + content checksum
    ( vec_push [u] out # u desc )
    ( vec_push [u] out # u << - wlog 10 3 )  // exponent, mantissa 0
    ? == fcs_flag 2 {
        ( __zs_pu32 out srclen )
    } {
        ( __zs_pu32 out & srclen 0xFFFFFFFF )
        ( __zs_pu32 out >> # u64 srclen 32 )
    }
    ^ v
}

// Search depth per level — and an honest one.
//
// Level 1 takes the first candidate in the chain and never looks aside;
// every level above it examines four and considers starting one byte
// later (lazy matching), which is worth about 4 % on text.
//
// It does NOT keep growing, because a deeper chain was measured and did
// not pay: at 16, 48, 128 and 512 candidates the output on the gate's
// text corpus came out 1.0 – 1.6 % LARGER than at four. That is the
// greedy parse showing through — the extra candidates are longer
// matches further back, each locally cheaper and globally worse,
// because taking one abandons the recent offset the following
// sequences would have ridden for two bits apiece. A distance penalty
// heavy enough to make depth monotone (3x the offset's bit length) made
// every level worse still. The fix for that is an optimal parser, not a
// bigger number here, so until one lands the levels above 2 select the
// same parameters rather than pretending to earn their extra time.
@ __zs_attempts i level → i {
    ? <= level 1 { ^ 1 } {}
    ^ 4
}

// The best match at `at`, priced rather than merely measured. A longer
// match that lies further back is not automatically better: its offset
// costs bits, and a match at the most recent offset costs almost none.
// Choosing by length alone is why more search made the output BIGGER —
// level 12 lost to level 1 on ordinary text until this was a price.
//
// Reports through `out`: slot 0 = length, slot 1 = offset. Returns the
// score in eighths of a bit saved, or -1 when nothing matched.
@ __zs_find * u p ( Vec i ) htab ( Vec i ) chain i hlog i chainmask
i attempts i at i bend i rep0 i ll ( Vec i ) out → i {
    : *i hp ( vec_data [i] htab )
    : *i cp ( vec_data [i] chain )
    : *i op ( vec_data [i] out )
    : ~ i best 0
    : ~ i bestoff 0
    : ~ i bestscore -1
    // The most recent offset first: it is two bits, so it wins ties and
    // most near-ties, and keeping it alive is what makes runs cheap.
    ? & > ll 0 & > rep0 0 >= - at rep0 0 {
        : i ml ( __zs_matchlen p - at rep0 at bend )
        ? >= ml ZS_MIN_MATCH {
            = best ml
            = bestoff rep0
            = bestscore - * ml ZS_LIT_BITS 1
        } {}
    } {}
    : ~ i cand # i . hp ( __zs_hash4 p at hlog )
    : ~ i tries attempts
    ~ & > cand 0 > tries 0 {
        : i cpos - cand 1
        : i off - at cpos
        ? > off 0 {
            : i ml ( __zs_matchlen p cpos at bend )
            ? >= ml ZS_MIN_MATCH {
                : i cost ? & > ll 0 == off rep0 1 ( __zs_hbit off )
                : i score - * ml ZS_LIT_BITS cost
                ? > score bestscore {
                    = best ml
                    = bestoff off
                    = bestscore score
                } {}
            } {}
        } {}
        = cand # i . cp & cpos chainmask
        = tries - tries 1
    }
    = . op 0 best
    = . op 1 bestoff
    ^ bestscore
}

@ zstd_encode_at ( Vec u ) src i level → ( Vec u ) {
    : i n ( vec_len [u] src )
    : ( Vec u ) out ( vec_with_cap [u] + >> n 1 64 )
    ( __zs_write_header out n )
    ? == n 0 {
        ( __zs_block_header out 0 0 1 )
        ( __zs_pu32 out & ( xxh64 src ) 0xFFFFFFFF )
        ^ out
    } {}
    : *u p ( vec_data [u] src )
    : i attempts ( __zs_attempts level )
    // Hash table sized to the input, chain covering the whole window.
    : ~ i hlog 12
    ~ & < hlog 20 < << 1 hlog n { = hlog + hlog 1 }
    : ( Vec i ) htab ( __zs_zeros << 1 hlog )
    : i chainbits ? > hlog 18 18 hlog
    : i chainmask - << 1 + chainbits 2 1
    : ( Vec i ) chain ( __zs_zeros + chainmask 1 )
    : *i hp ( vec_data [i] htab )
    : *i cp ( vec_data [i] chain )
    // Sequence code tables, shared by every block.
    : ( Vec i ) llx ( __zs_ll_extra )
    : ( Vec i ) mlx ( __zs_ml_extra )
    : ( Vec i ) llb ( __zs_ll_base llx )
    : ( Vec i ) mlb ( __zs_ml_base mlx )
    : ( Vec u ) lits ( vec_with_cap [u] ZS_BLOCK_MAX )
    : ( Vec i ) sll ( vec_new [i] )
    : ( Vec i ) sml ( vec_new [i] )
    : ( Vec i ) soff ( vec_new [i] )
    : ( Vec i ) found ( __zs_zeros 2 )
    : *i fp ( vec_data [i] found )
    : b lazy >= level 2
    : ~ i rep0 1
    : ~ i rep1 4
    : ~ i rep2 8
    : ~ i pos 0
    ~ < pos n {
        : i bstart pos
        : i bend ? > - n pos ZS_BLOCK_MAX + pos ZS_BLOCK_MAX n
        : i blen - bend bstart
        ( vec_clear [u] lits )
        ( vec_clear [i] sll )
        ( vec_clear [i] sml )
        ( vec_clear [i] soff )
        : ~ i anchor bstart
        : ~ i at bstart
        ~ <= + at ZS_MIN_MATCH bend {
            : i score ( __zs_find p htab chain hlog chainmask attempts
            at bend rep0 - at anchor found )
            : ~ i best # i . fp 0
            : ~ i bestoff # i . fp 1
            // Lazy matching: a match starting one byte later may be
            // worth more than this one even after paying for the extra
            // literal. Only from level 5 up — it doubles the searching.
            ? & lazy & >= best ZS_MIN_MATCH <= + at + ZS_MIN_MATCH 1 bend {
                : i s2 ( __zs_find p htab chain hlog chainmask attempts
                + at 1 bend rep0 + 1 - at anchor found )
                ? > s2 + score ZS_LIT_BITS {
                    // Take the literal at `at` and start there instead.
                    : i hl ( __zs_hash4 p at hlog )
                    = . cp & at chainmask # i . hp hl
                    = . hp hl + at 1
                    = at + at 1
                    = best # i . fp 0
                    = bestoff # i . fp 1
                } {}
            } {}
            ? >= best ZS_MIN_MATCH {
                : i ll - at anchor
                ( vec_extend_range [u] lits src anchor ll )
                // The most recent offset costs two bits instead of
                // twenty — but only when literals precede it, because
                // with none the repeat slots shift by one.
                : ~ i ofbase + bestoff 3
                ? & > ll 0 == bestoff rep0 {
                    = ofbase 1
                } {
                    = rep2 rep1
                    = rep1 rep0
                    = rep0 bestoff
                }
                ( vec_push [i] sll ll )
                ( vec_push [i] sml best )
                ( vec_push [i] soff ofbase )
                // Index every position the match covers, so a later
                // match can start anywhere inside it.
                : ~ i k at
                ~ & < k + at best <= + k ZS_MIN_MATCH bend {
                    : i hk ( __zs_hash4 p k hlog )
                    = . cp & k chainmask # i . hp hk
                    = . hp hk + k 1
                    = k + k 1
                }
                = at + at best
                = anchor at
            } {
                : i h ( __zs_hash4 p at hlog )
                = . cp & at chainmask # i . hp h
                = . hp h + at 1
                = at + at 1
            }
        }
        ( vec_extend_range [u] lits src anchor - bend anchor )
        : i last ? == bend n 1 0
        ( __zs_write_block out src bstart blen last lits sll sml soff
        llb mlb llx mlx )
        = pos bend
    }
    ( __zs_pu32 out & ( xxh64 src ) 0xFFFFFFFF )
    ( vec_free [i] htab )
    ( vec_free [i] chain )
    ( vec_free [i] llx ) ( vec_free [i] mlx )
    ( vec_free [i] llb ) ( vec_free [i] mlb )
    ( vec_free [u] lits )
    ( vec_free [i] sll ) ( vec_free [i] sml ) ( vec_free [i] soff )
    ( vec_free [i] found )
    ^ out
}

@ zstd_encode ( Vec u ) src → ( Vec u ) {
    ^ ( zstd_encode_at src 3 )
}

// The first frame's declared content size, without decoding anything.
// Absent when the frame was produced by a streaming compressor that did
// not know the size in advance.
@ zstd_content_size ( Vec u ) src → ?i {
    : i n ( vec_len [u] src )
    ? < n 6 { ^ @ ?i { F } } {}
    : *u p ( vec_data [u] src )
    : i magic | | | # i . p 0 << # i . p 1 8 << # i . p 2 16 << # i . p 3 24
    ? != magic ZS_MAGIC { ^ @ ?i { F } } {}
    : i desc # i . p 4
    : i fcs_flag >> desc 6
    : i single & >> desc 5 1
    : i did_flag & desc 3
    ? & == single 0 == fcs_flag 0 { ^ @ ?i { F } } {}
    : ~ i at 5
    ? == single 0 { = at + at 1 } {}
    = at + at ? == did_flag 0 0 ? == did_flag 1 1 ? == did_flag 2 2 4
    : i nbytes ? == fcs_flag 0 1 ? == fcs_flag 1 2 ? == fcs_flag 2 4 8
    ? > + at nbytes n { ^ @ ?i { F } } {}
    : ~ i fcs 0
    : ~ i k 0
    ~ < k nbytes {
        = fcs | fcs << # i . p + at k * k 8
        = k + k 1
    }
    ? == nbytes 2 { = fcs + fcs 256 } {}
    ^ @ ?i { T fcs }
}
