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

// Decode-side sequence statistics, for studying what an encoder chose:
// zeroed by zstd_decode, read back with zstd_seq_stats. Scalars because
// the language has no compound-typed globals.
: ~ i g_zs_nseq 0
: ~ i g_zs_sumll 0
: ~ i g_zs_summl 0
: ~ i g_zs_nrep 0

// [0]=sequences [1]=literal bytes in sequences [2]=match bytes
// [3]=sequences that rode a repeat offset (offbase 1..3)
@ zstd_seq_stats → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v g_zs_nseq )
    ( vec_push [i] v g_zs_sumll )
    ( vec_push [i] v g_zs_summl )
    ( vec_push [i] v g_zs_nrep )
    ^ v
}

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
    // An offset may not reach behind this frame's own output, and may
    // not exceed the window the frame's header promised — a decoder
    // that keeps the whole frame in memory could serve the second case
    // anyway, and would then accept a frame the format calls invalid
    // and quietly hand back whatever those bytes happened to be.
    ? | <= offset 0 > offset - o . d framestart { = . d err ZSE_CORRUPT ^ v } {}
    ? & > . d window 0 > offset . d window { = . d err ZSE_CORRUPT ^ v } {}
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
            = g_zs_nseq + g_zs_nseq 1
            = g_zs_sumll + g_zs_sumll ll
            = g_zs_summl + g_zs_summl ml
            ? <= offcode 3 { = g_zs_nrep + g_zs_nrep 1 } {}
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
    = g_zs_nseq 0
    = g_zs_sumll 0
    = g_zs_summl 0
    = g_zs_nrep 0
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

// ── Cross-block writer state: repeat and treeless modes ─────────────
//
// The format lets a block reuse the previous block's entropy tables —
// mode 3 for a sequence table, block type 3 (treeless) for the Huffman
// tree — and on any multi-block input that reuse is worth real bytes:
// three FSE descriptions and a tree, per block, on data whose shape
// barely changed. The writer keeps what the DECODER would be holding
// (the last tables it built) and, per block, prices sending a new
// table against reusing the standing one against the predefined one,
// in bits, and takes the cheapest. The decoder mirror of this state is
// ZsDec's hufbits / lllog / oflog / mllog.
: ZsWst {
    ( Vec i ) hlen  // previous Huffman code lengths; empty until hvalid
    i hvalid
    ( Vec i ) lldist  // previous normalized distributions
    ( Vec i ) ofdist
    ( Vec i ) mldist
    i lllg  // their accuracy logs
    i oflg
    i mllg
    i llok  // 1 = a table is standing (sent or predefined)
    i ofok
    i mlok
    ( Vec i ) shadow  // save/restore snapshot: 256+3*64 dists + 8 scalars
}

@ __zs_wst_new → *ZsWst {
    : *ZsWst st ( nurl_alloc Z ZsWst )
    = . st hlen ( __zs_zeros 256 )
    = . st hvalid 0
    = . st lldist ( __zs_zeros 64 )
    = . st ofdist ( __zs_zeros 64 )
    = . st mldist ( __zs_zeros 64 )
    = . st llok 0
    = . st ofok 0
    = . st mlok 0
    = . st shadow ( __zs_zeros 912 )
    ^ st
}

@ __zs_wst_free * ZsWst st → v {
    ( vec_free [i] . st hlen )
    ( vec_free [i] . st lldist )
    ( vec_free [i] . st ofdist )
    ( vec_free [i] . st mldist )
    ( vec_free [i] . st shadow )
    ( nurl_free # s st )
}

// Writing a block ADVANCES this state (a sent table becomes the
// standing one). Trying several parses of the same block therefore
// needs the state as it stood before each trial: save it, and either
// commit the advance (the trial won) or put it back (it lost).
@ __zs_wst_save * ZsWst st i slot → v {
    : *i sh0 ( vec_data [i] . st shadow )
    : *i sh # *i + # i sh0 * slot 3648
    : *i hl ( vec_data [i] . st hlen )
    : *i l1 ( vec_data [i] . st lldist )
    : *i l2 ( vec_data [i] . st ofdist )
    : *i l3 ( vec_data [i] . st mldist )
    : ~ i t 0
    ~ < t 256 { = . sh t # i . hl t = t + t 1 }
    ~ < t 320 { = . sh t # i . l1 - t 256 = t + t 1 }
    ~ < t 384 { = . sh t # i . l2 - t 320 = t + t 1 }
    ~ < t 448 { = . sh t # i . l3 - t 384 = t + t 1 }
    = . sh 448 . st hvalid
    = . sh 449 . st lllg
    = . sh 450 . st oflg
    = . sh 451 . st mllg
    = . sh 452 . st llok
    = . sh 453 . st ofok
    = . sh 454 . st mlok
}

@ __zs_wst_restore * ZsWst st i slot → v {
    : *i sh0 ( vec_data [i] . st shadow )
    : *i sh # *i + # i sh0 * slot 3648
    : *i hl ( vec_data [i] . st hlen )
    : *i l1 ( vec_data [i] . st lldist )
    : *i l2 ( vec_data [i] . st ofdist )
    : *i l3 ( vec_data [i] . st mldist )
    : ~ i t 0
    ~ < t 256 { = . hl t # i . sh t = t + t 1 }
    ~ < t 320 { = . l1 - t 256 # i . sh t = t + t 1 }
    ~ < t 384 { = . l2 - t 320 # i . sh t = t + t 1 }
    ~ < t 448 { = . l3 - t 384 # i . sh t = t + t 1 }
    = . st hvalid # i . sh 448
    = . st lllg # i . sh 449
    = . st oflg # i . sh 450
    = . st mllg # i . sh 451
    = . st llok # i . sh 452
    = . st ofok # i . sh 453
    = . st mlok # i . sh 454
}

// The cost, in 1/16 bits, of coding `counts` with the distribution
// `dist` (normalized to 1<<log). -1 when some present symbol has no
// cell — that table cannot code this block at all.
@ __zs_dist_cost * i cnt i nsym * i dist i ndist i log → i {
    : ~ i totalc 0
    : ~ i s 0
    ~ < s nsym {
        : i c # i . cnt s
        ? > c 0 {
            ? | >= s ndist == # i . dist s 0 { ^ -1 } {}
            : i share0 # i . dist s
            // A "less than one" (-1) cell prices as one cell.
            : i share ? < share0 0 1 share0
            = totalc + totalc * c - << log 4 ( __zs_log2_16 share )
        } {}
        = s + s 1
    }
    ^ totalc
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
    // Reconcile by largest remainder: each leftover cell goes to the
    // symbol whose share was rounded down the hardest. Dumping the
    // whole difference on the biggest symbol — the previous rule —
    // distorts exactly the code the data uses most.
    ~ < sum scale {
        : ~ i pick -1
        : ~ i pickrem -1
        : ~ i t 0
        ~ < t nsym {
            ? > # i . cp t 0 {
                : i rem % * # i . cp t scale total
                ? > rem pickrem { = pickrem rem = pick t } {}
            } {}
            = t + t 1
        }
        ? < pick 0 { = pick big } {}
        = . np pick + # i . np pick 1
        = sum + sum 1
    }
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
@ __zs_lit_compress ( Vec u ) body ( Vec u ) lits * ZsWst wst → b {
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
    : ~ i maxb ( __zs_huf_lengths counts lens ZS_MAX_SYMS )
    ? | <= maxb 0 > maxb ZS_MAX_HUF_BITS {
        ( vec_free [i] counts ) ( vec_free [i] lens ) ( vec_free [i] codes )
        ^ F
    } {}
    ( __zs_huf_codes lens codes ZS_MAX_SYMS maxb )
    // The standing tree — the one the decoder still holds from the
    // previous block — codes this block for zero header bytes if it
    // covers every byte present. Weigh that against a fresh tree's
    // bits-plus-description; the winner is decided in whole bits
    // before anything is built.
    : ~ b treeless F
    ? == . wst hvalid 1 {
        : *i hlp ( vec_data [i] . wst hlen )
        : ~ i newbits 0
        : ~ i prevbits 0
        : ~ b covered T
        : *i lnp0 ( vec_data [i] lens )
        : ~ i t 0
        ~ < t ZS_MAX_SYMS {
            : i c # i . cnp t
            ? > c 0 {
                = newbits + newbits * c # i . lnp0 t
                ? > # i . hlp t 0 { = prevbits + prevbits * c # i . hlp t }
                { = covered F }
            } {}
            = t + t 1
        }
        // A fresh description costs 40-120 bytes; charge a conservative
        // 40 against the fresh tree and let ties keep the old one.
        ? & covered <= prevbits + newbits 320 {
            = treeless T
            = t 0
            ~ < t ZS_MAX_SYMS { = . lnp0 t # i . hlp t = t + t 1 }
            : ~ i mb 0
            = t 0
            ~ < t ZS_MAX_SYMS {
                ? > # i . lnp0 t mb { = mb # i . lnp0 t } {}
                = t + t 1
            }
            = maxb mb
            ( __zs_huf_codes lens codes ZS_MAX_SYMS maxb )
        } {}
    } {}
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
    ? treeless {} {
        ? & > ndir 0 | ! okfse <= ndir nfse {
            ( vec_extend [u] tree tdir )
        } { ? okfse { ( vec_extend [u] tree tfse ) } {} }
    }
    ( vec_free [u] tdir )
    ( vec_free [u] tfse )
    ( vec_free [i] wts )
    ? & ! treeless == ( vec_len [u] tree ) 0 {
        ( vec_free [u] tree )
        ( vec_free [i] counts ) ( vec_free [i] lens ) ( vec_free [i] codes )
        ^ F
    } {}
    : i btype ? treeless 3 2
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
            : i hv | | btype << 0 2 | << n 4 << csize 14
            ( vec_push [u] body # u & hv 255 )
            ( vec_push [u] body # u & >> hv 8 255 )
            ( vec_push [u] body # u & >> hv 16 255 )
        } { ? == hdrlen 4 {
                : i hv | | btype << 2 2 | << n 4 << csize 18
                ( vec_push [u] body # u & hv 255 )
                ( vec_push [u] body # u & >> hv 8 255 )
                ( vec_push [u] body # u & >> hv 16 255 )
                ( vec_push [u] body # u & >> hv 24 255 )
            } {
                : i hv | | btype << 3 2 | << n 4 << csize 22
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
    // A tree that actually went out is what the decoder now holds.
    ? & used ! treeless {
        : *i hlp2 ( vec_data [i] . wst hlen )
        : *i lnp2 ( vec_data [i] lens )
        : ~ i t 0
        ~ < t ZS_MAX_SYMS { = . hlp2 t # i . lnp2 t = t + t 1 }
        = . wst hvalid 1
    } {}
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
( Vec i ) deffreq i defn i deflog ( Vec i ) modeslot
* ZsWst st i which → ZsCt {
    : *i mp ( vec_data [i] modeslot )
    : *i cntp ( vec_data [i] counts )
    // The standing table (what the decoder still holds), if any.
    : ( Vec i ) prev ? == which 0 . st lldist ? == which 1 . st ofdist . st mldist
    : i prevok ? == which 0 . st llok ? == which 1 . st ofok . st mlok
    : i prevlog ? == which 0 . st lllg ? == which 1 . st oflg . st mllg
    : *i prevp ( vec_data [i] prev )
    : ~ i cost_rep -1
    ? == prevok 1 { = cost_rep ( __zs_dist_cost cntp nsym prevp 64 prevlog ) } {}
    // The predefined table: normalize its -1 entries to one cell for
    // pricing (that is what they get in the real table).
    : ( Vec i ) defnorm ( __zs_zeros 64 )
    : *i dfp ( vec_data [i] deffreq )
    : *i dnp ( vec_data [i] defnorm )
    : ~ i q 0
    ~ < q defn {
        : i f # i . dfp q
        = . dnp q ? < f 0 1 f
        = q + q 1
    }
    : i cost_pre ( __zs_dist_cost cntp nsym dnp 64 deflog )
    // A fresh table, if the block can pay for one.
    : ~ i cost_new -1
    : ( Vec i ) norm ( __zs_zeros ? > nsym 0 nsym 1 )
    : ( Vec u ) ncount ( vec_new [u] )
    : ~ i newlog 0
    : ~ i maxsym -1
    ? >= nseq 24 {
        // Resolution the sequence count can pay for, floored at what
        // the alphabet needs and capped at what the format allows.
        : ~ i log - ( __zs_hbit - nseq 1 ) 2
        : i minlog + ( __zs_hbit nsym ) 1
        ? < log minlog { = log minlog } {}
        ? < log 5 { = log 5 } {}
        ? > log maxlog { = log maxlog } {}
        = maxsym ( __zs_normalize counts norm nsym log )
        ? > maxsym 0 {
            = newlog log
            : *ZsBw w ( nurl_alloc Z ZsBw )
            = . w buf ( vec_new [u] )
            = . w acc 0
            = . w bits 0
            ( __zs_write_ncount w norm + maxsym 1 log )
            ( __zs_bw_close_fwd w )
            ( vec_extend [u] ncount . w buf )
            ( vec_free [u] . w buf )
            ( nurl_free # s w )
            : *i normp ( vec_data [i] norm )
            = cost_new + ( __zs_dist_cost cntp nsym normp nsym log )
            << * ( vec_len [u] ncount ) 8 4
        } {}
    } {}
    // Cheapest wins; a tie keeps the standing table (no header bytes,
    // no new state).
    : ~ i mode 0
    ? & >= cost_rep 0 | < cost_new 0 <= cost_rep cost_new {
        ? <= cost_rep cost_pre { = mode 3 } {}
    } {}
    ? & != mode 3 >= cost_new 0 {
        ? < cost_new cost_pre { = mode 2 } {}
    } {}
    = . mp 0 mode
    ? == mode 2 {
        ( vec_extend [u] tabs ncount )
        : ZsCt ct ( __zs_ct_build norm + maxsym 1 newlog )
        // The fresh table becomes the standing one.
        : *i normp2 ( vec_data [i] norm )
        = q 0
        ~ < q 64 { = . prevp q ? < q nsym # i . normp2 q 0 = q + q 1 }
        ? == which 0 { = . st lllg newlog = . st llok 1 } {
            ? == which 1 { = . st oflg newlog = . st ofok 1 } {
                = . st mllg newlog
                = . st mlok 1
            }
        }
        ( vec_free [i] norm )
        ( vec_free [u] ncount )
        ( vec_free [i] defnorm )
        ^ ct
    } {}
    ( vec_free [i] norm )
    ( vec_free [u] ncount )
    ? == mode 3 {
        ( vec_free [i] defnorm )
        ^ ( __zs_ct_build prev 64 prevlog )
    } {}
    // Predefined: it becomes the standing table too — that is what the
    // decoder will be holding. Stored RAW, -1 cells intact: the decoder
    // builds its predef table with the "less than one" cells taken from
    // the TOP, and a repeat must rebuild exactly that table, not a
    // lookalike whose 1-cells were spread normally.
    = q 0
    ~ < q 64 { = . prevp q ? < q defn # i . dfp q 0 = q + q 1 }
    ? == which 0 { = . st lllg deflog = . st llok 1 } {
        ? == which 1 { = . st oflg deflog = . st ofok 1 } {
            = . st mllg deflog
            = . st mlok 1
        }
    }
    ( vec_free [i] defnorm )
    ^ ( __zs_ct_build deffreq defn deflog )
}

@ __zs_write_block ( Vec u ) out ( Vec u ) src i bstart i blen i last
( Vec u ) lits ( Vec i ) sll ( Vec i ) sml ( Vec i ) soff
( Vec i ) llb ( Vec i ) mlb ( Vec i ) llx ( Vec i ) mlx * ZsWst wst → v {
    : i nseq ( vec_len [i] sll )
    : i nlit ( vec_len [u] lits )
    : ( Vec u ) body ( vec_with_cap [u] + blen 64 )
    ? ! ( __zs_lit_compress body lits wst ) {
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
        : ZsCt llct ( __zs_seq_ctable tabs llcnt 36 9 nseq deffreq lldefn 6 modeslot wst 0 )
        : i llmode # i . msp 0
        : i ofdefn ( __zs_of_default deffreq )
        : ZsCt ofct ( __zs_seq_ctable tabs ofcnt 32 8 nseq deffreq ofdefn 5 modeslot wst 1 )
        : i ofmode # i . msp 0
        : i mldefn ( __zs_ml_default deffreq )
        : ZsCt mlct ( __zs_seq_ctable tabs mlcnt 53 9 nseq deffreq mldefn 6 modeslot wst 2 )
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

// Greedy search depth per level — and an honest one.
//
// Level 1 takes the first candidate in the chain and never looks aside;
// levels 2–12 examine four and consider starting one byte later (lazy
// matching), worth about 4 % on text. Depth beyond four was measured
// and did not pay UNDER A GREEDY PARSE: the extra candidates are longer
// matches further back, each locally cheaper and globally worse,
// because taking one abandons the recent offset the following
// sequences would have ridden for two bits apiece. That is not a law of
// nature, it is the greedy parse showing through — and from level 13 up
// the encoder switches to the optimal parser (__zs_encode_opt), where
// depth DOES pay because every candidate is priced against every other
// path through the block.
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

// ── Optimal parser (levels 13+) ─────────────────────────────────────
//
// The greedy parser above chooses each match on its own; this one
// chooses the SET of matches with the smallest priced total, which is
// the difference between beating `zstd -3` and chasing `zstd -19`.
//
// It is a shortest-path problem: node = position in the block, edge =
// one literal or one match, weight = the bits that choice will cost.
// Positions are relaxed left to right, so by the time a position is
// extended its own cost is final. Three things make the classic DP
// match this format:
//
//  * REPEAT OFFSETS make edge weights history-dependent — offbase 1
//    costs ~2 bits but only if the offset matches a rep slot, and the
//    slots depend on the path. Exact handling would need reps in the
//    node state; like the reference's btultra2, each position instead
//    CARRIES the rep state of its best arrival, which is exact along
//    the chosen path and approximate off it.
//  * The LITERALS-LENGTH code prices a whole run at once, so a match
//    edge pays its run's LL code and a literal edge pays only the
//    literal byte; the run length rides along in the arrival state.
//  * Prices must come from somewhere. Pass 1 prices literals from the
//    block's own byte counts and sequences from the predefined
//    distributions; pass 2 reprices everything from what pass 1
//    actually chose and parses again. (The reference's btultra2 is
//    this same two-pass shape.)
//
// A match longer than `suff` ends deliberation: it is taken whole and
// the parse resumes after it, exactly so that a megabyte of zeros costs
// one decision, not half a billion relaxations.

: i ZS_OPT_SUFF 1024
: i ZS_OPT_INF 0x0FFFFFFFFFFFFFFF
: i ZS_H3_MASK 65535

// log2 in 1/16ths of a bit: floor-log2 plus a parabolic correction for
// the fraction, within ~0.02 bit of the true value — plenty for prices.
@ __zs_log2_16 i x → i {
    ? <= x 1 { ^ 0 } {}
    : i l ( __zs_hbit x )
    : ~ i frac 0
    ? >= l 4 { = frac & >> x - l 4 15 } { = frac & << x - 4 l 15 }
    : i corr >> + * * frac - 16 frac 5 128 8
    ^ + + << l 4 frac corr
}

// Symbol prices from occurrence counts: price = log2(total/count),
// in 1/16 bits. An unseen symbol prices one bit past the rarest.
@ __zs_prices_16 * i cnt i n * i price → v {
    : ~ i total 0
    : ~ i s 0
    ~ < s n { = total + total # i . cnt s = s + s 1 }
    ? <= total 0 { = total 1 } {}
    : i lt ( __zs_log2_16 total )
    = s 0
    ~ < s n {
        : i c # i . cnt s
        = . price s ? > c 0 - lt ( __zs_log2_16 c ) + lt 16
        = s + s 1
    }
}

@ __zs_fill0 * i pp i n → v {
    : ~ i s 0
    ~ < s n { = . pp s 0 = s + s 1 }
}

// Code lookups over raw base-table pointers (the Vec forms above walk
// the same tables; these avoid re-fetching vec_data in a hot loop).
@ __zs_ll_code_p * i basep i ll → i {
    ? < ll 16 { ^ ll } {}
    : ~ i c 16
    ~ & < c 35 <= # i . basep + c 1 ll { = c + c 1 }
    ^ c
}

@ __zs_ml_code_p * i basep i ml → i {
    ? < ml 35 { ^ - ml 3 } {}
    : ~ i c 32
    ~ & < c 52 <= # i . basep + c 1 ml { = c + c 1 }
    ^ c
}

// Everything one block's parse needs, behind one pointer: the input,
// the match-finder tables, the DP arrays, and the price tables. The
// arrays are allocated once per encode and rewritten per block.
: ZsOpt {
    * u p
    i bstart
    i blen
    * i hp  // hash4 chain heads
    * i cp  // chain links
    * i h3p  // hash3 last-position table
    i hlog
    i chainmask
    i attempts
    i insert  // 1 = build the chain while parsing (pass 1 only)
    i suff
    i skipu  // skip-until, set by an immediate take
    * i cost  // DP: best arrival price, 1/16 bits
    * i bln  // DP: arriving match length; 0 = literal
    * i bof  // DP: arriving match offset (raw distance)
    * i bll  // DP: the match's literal-run length
    * i blit  // DP: literal run at this arrival
    * i br0  // DP: rep state at this arrival
    * i br1
    * i br2
    * i litp  // price tables (extras folded in)
    * i llp
    * i mlp
    * i ofp
    * i llbp  // code base tables
    * i mlbp
    * i cco  // candidate cache: offsets, 8 slots per position
    * i ccm  // candidate cache: match lengths
    * i ccn  // candidate cache: how many slots are filled
    i rep0  // rep state at block start
    i rep1
    i rep2
}

// Relax one candidate over a run of lengths. The ML code is stepped
// incrementally — its base table is sorted, so a length walk crosses
// each code boundary once instead of looking every length up.
@ __zs_opt_relax * ZsOpt o i k i cbase i off i ofprice i lmin i lmax
i nr0 i nr1 i nr2 → v {
    ? > lmin lmax { ^ v } {}
    : *i costp . o cost
    : *i blnp . o bln
    : *i bofp . o bof
    : *i bllp . o bll
    : *i blitp . o blit
    : *i br0p . o br0
    : *i br1p . o br1
    : *i br2p . o br2
    : *i mlpp . o mlp
    : *i mlbp2 . o mlbp
    : i lr # i . blitp k
    : i c0 + cbase ofprice
    : ~ i mlc ( __zs_ml_code_p mlbp2 lmin )
    : ~ i nextb ? < mlc 52 # i . mlbp2 + mlc 1 ZS_OPT_INF
    : ~ i L lmin
    ~ <= L lmax {
        ~ >= L nextb {
            = mlc + mlc 1
            = nextb ? < mlc 52 # i . mlbp2 + mlc 1 ZS_OPT_INF
        }
        : i tot + c0 # i . mlpp mlc
        : i j + k L
        ? < tot # i . costp j {
            = . costp j tot
            = . blnp j L
            = . bofp j off
            = . bllp j lr
            = . blitp j 0
            = . br0p j nr0
            = . br1p j nr1
            = . br2p j nr2
        } {}
        = L + L 1
    }
}

// All match edges out of position k: the three rep offsets (length 3
// up — an ML code starts at 3, and a rep is the cheapest offset there
// is), one hash3 candidate (the length-3 matches the 4-byte hash can
// never see), and the hash4 chain. Chain candidates are kept only when
// strictly longer than everything cheaper: the chain yields offsets in
// increasing order, so for any target length the first candidate that
// covers it is the cheapest, and each candidate relaxes only the
// lengths the previous one could not reach.
@ __zs_opt_matches * ZsOpt o i k → v {
    : *u p . o p
    : i bstart . o bstart
    : i n . o blen
    : i absk + bstart k
    : i bend + bstart n
    : *i costp . o cost
    : *i blitp . o blit
    : *i br0p . o br0
    : *i br1p . o br1
    : *i br2p . o br2
    : *i llpp . o llp
    : *i ofpp . o ofp
    : *i llbp2 . o llbp
    : i ck # i . costp k
    : i lr # i . blitp k
    : i r0 # i . br0p k
    : i r1 # i . br1p k
    : i r2 # i . br2p k
    : i cbase + ck # i . llpp 0
    : i suff . o suff
    : ~ i bestlen 2
    : ~ i bestoff 0
    : ~ i bestofp 0
    // Rep candidates. With no literals before the match the slots
    // shift: rep0 itself is unreachable and rep0-1 appears — mirror of
    // the decoder's __zs_offset.
    : ~ i ri 0
    ~ < ri 3 {
        : ~ i rv 0
        ? > lr 0 {
            = rv ? == ri 0 r0 ? == ri 1 r1 r2
        } {
            = rv ? == ri 0 r1 ? == ri 1 r2 - r0 1
        }
        : i ob + ri 1
        ? & > rv 0 <= rv absk {
            : i src0 - absk rv
            ? == # i . p src0 # i . p absk {
                : i ml ( __zs_matchlen p src0 absk bend )
                ? >= ml 3 {
                    : i ofprice # i . ofpp ( __zs_hbit ob )
                    : ~ i nr0 rv
                    : ~ i nr1 r0
                    : ~ i nr2 r1
                    ? == rv r0 { = nr1 r1 = nr2 r2 } {
                        ? == rv r1 { = nr2 r2 } {}
                    }
                    ? >= ml suff {
                        ? > ml bestlen {
                            = bestlen ml
                            = bestoff rv
                            = bestofp ofprice
                        } {}
                    } {
                        ( __zs_opt_relax o k cbase rv ofprice 3 ml nr0 nr1 nr2 )
                        ? > ml bestlen {
                            = bestlen ml
                            = bestoff rv
                            = bestofp ofprice
                        } {}
                    }
                } {}
            } {}
        } {}
        = ri + ri 1
    }
    : *i ccop . o cco
    : *i ccmp . o ccm
    : *i ccnp . o ccn
    : i cslot << k 3
    ? == . o insert 1 {
        = . ccnp k 0
        ? < bestlen suff {
            // hash3: one candidate, the most recent position with these
            // three bytes. Worth having because a length-3 match at a
            // small offset beats three literals, and the 4-byte hash is
            // blind to it.
            : *i h3pp . o h3p
            : i v3 | | # i . p absk << # i . p + absk 1 8 << # i . p + absk 2 16
            : i h3i2 * 2 & >> * v3 2654435761 16 ZS_H3_MASK
            : ~ i h3q 0
            ~ & < h3q 2 < bestlen suff {
                : i cand3 # i . h3pp + h3i2 h3q
                = h3q + h3q 1
                ? > cand3 0 {
                    : i cpos - cand3 1
                    : i off - absk cpos
                    ? & > off 0 == # i . p cpos # i . p absk {
                        : i ml ( __zs_matchlen p cpos absk bend )
                        ? & >= ml 3 > ml bestlen {
                            : i ofprice # i . ofpp ( __zs_hbit + off 3 )
                            : ~ i nr0 off
                            : ~ i nr1 r0
                            : ~ i nr2 r1
                            ? == off r0 { = nr1 r1 = nr2 r2 } {
                                ? == off r1 { = nr2 r2 } {}
                            }
                            = . ccop + cslot # i . ccnp k off
                            = . ccmp + cslot # i . ccnp k ml
                            = . ccnp k + # i . ccnp k 1
                            ? >= ml suff {
                                = bestlen ml
                                = bestoff off
                                = bestofp ofprice
                            } {
                                : i lmin ? > + bestlen 1 3 + bestlen 1 3
                                ( __zs_opt_relax o k cbase off ofprice lmin ml nr0 nr1 nr2 )
                                = bestlen ml
                                = bestoff off
                                = bestofp ofprice
                            }
                        } {}
                    } {}
                } {}
            }
        } {}
        ? & < bestlen suff <= + k 4 n {
            : *i hpp . o hp
            : *i cp2 . o cp
            : i chainmask . o chainmask
            : i h4 ( __zs_hash4 p absk . o hlog )
            : ~ i cand # i . hpp h4
            : ~ i tries . o attempts
            : ~ i walked * . o attempts 8
            : ~ b stop F
            ~ & & > cand 0 > tries 0 & > walked 0 ! stop {
                : i cpos - cand 1
                : i off - absk cpos
                = walked - walked 1
                ? > off 0 {
                    = tries - tries 1
                    ? >= + absk bestlen bend { = stop T } {
                        // One byte decides whether this candidate can
                        // even beat the best so far; most cannot.
                        ? == # i . p + cpos bestlen # i . p + absk bestlen {
                            : i ml ( __zs_matchlen p cpos absk bend )
                            ? & >= ml 4 > ml bestlen {
                                : i ofprice # i . ofpp ( __zs_hbit + off 3 )
                                : ~ i nr0 off
                                : ~ i nr1 r0
                                : ~ i nr2 r1
                                ? == off r0 { = nr1 r1 = nr2 r2 } {
                                    ? == off r1 { = nr2 r2 } {}
                                }
                                ? < # i . ccnp k 8 {
                                    = . ccop + cslot # i . ccnp k off
                                    = . ccmp + cslot # i . ccnp k ml
                                    = . ccnp k + # i . ccnp k 1
                                } {}
                                ? >= ml suff {
                                    = bestlen ml
                                    = bestoff off
                                    = bestofp ofprice
                                    = stop T
                                } {
                                    : i lmin ? > + bestlen 1 4 + bestlen 1 4
                                    ( __zs_opt_relax o k cbase off ofprice lmin ml nr0 nr1 nr2 )
                                    = bestlen ml
                                    = bestoff off
                                    = bestofp ofprice
                                }
                            } {}
                        } {}
                    }
                } {}
                = cand # i . cp2 & cpos chainmask
            }
        } {}
    } {
        // Pass 2: the chain now holds positions AHEAD of this one as
        // well as behind it, so walking it from the head would spend
        // the whole budget on the future. The candidates pass 1 found
        // are cached per position instead — reps are re-evaluated
        // (their offsets depend on the path, which repricing changes),
        // the ladder is replayed.
        : i cn # i . ccnp k
        : ~ i ci 0
        ~ < ci cn {
            : i off # i . ccop + cslot ci
            : i ml0 # i . ccmp + cslot ci
            : i ml ? > ml0 - n k - n k ml0
            : i minl ? >= ml0 4 4 3
            ? > ml bestlen {
                : i ofprice # i . ofpp ( __zs_hbit + off 3 )
                : ~ i nr0 off
                : ~ i nr1 r0
                : ~ i nr2 r1
                ? == off r0 { = nr1 r1 = nr2 r2 } {
                    ? == off r1 { = nr2 r2 } {}
                }
                ? >= ml suff {
                    = bestlen ml
                    = bestoff off
                    = bestofp ofprice
                    = ci cn
                } {
                    : i lmin ? > + bestlen 1 minl + bestlen 1 minl
                    ( __zs_opt_relax o k cbase off ofprice lmin ml nr0 nr1 nr2 )
                    = bestlen ml
                    = bestoff off
                    = bestofp ofprice
                }
            } {}
            = ci + ci 1
        }
    }
    // A match past `suff` ends deliberation: relax its endpoint alone
    // and jump the cursor past it.
    ? >= bestlen suff {
        : ~ i nr0 bestoff
        : ~ i nr1 r0
        : ~ i nr2 r1
        ? == bestoff r0 { = nr1 r1 = nr2 r2 } {
            ? == bestoff r1 { = nr2 r2 } {}
        }
        ( __zs_opt_relax o k cbase bestoff bestofp bestlen bestlen nr0 nr1 nr2 )
        = . o skipu + k bestlen
    } {}
}

@ __zs_opt_parse * ZsOpt o → v {
    : *u p . o p
    : i bstart . o bstart
    : i n . o blen
    : i bend + bstart n
    : *i costp . o cost
    : *i blnp . o bln
    : *i blitp . o blit
    : *i br0p . o br0
    : *i br1p . o br1
    : *i br2p . o br2
    : *i litpp . o litp
    : *i llpp . o llp
    : *i llbp3 . o llbp
    : *i hpp . o hp
    : *i cp2 . o cp
    : *i h3pp . o h3p
    : i hlog . o hlog
    : i chainmask . o chainmask
    : i do_insert . o insert
    = . costp 0 0
    = . blnp 0 0
    = . blitp 0 0
    = . br0p 0 . o rep0
    = . br1p 0 . o rep1
    = . br2p 0 . o rep2
    : ~ i k 1
    ~ <= k n { = . costp k ZS_OPT_INF = k + k 1 }
    = . o skipu 0
    = k 0
    ~ < k n {
        ? >= k . o skipu {
            : i absk + bstart k
            : i ck # i . costp k
            // The literal edge. Its price carries the MARGINAL growth
            // of the literals-length code: a run that will cost a
            // bigger LL code when the next match lands must look more
            // expensive while it is being laid down, or the parse
            // prefers literals it cannot actually afford. (This is a
            // potential transform — the total over any path is
            // unchanged, the attribution moves; the match edge pays
            // llp[0] as its share below.)
            : i run0 # i . blitp k
            : i dll - # i . llpp ( __zs_ll_code_p llbp3 + run0 1 )
            # i . llpp ( __zs_ll_code_p llbp3 run0 )
            : i lc + + ck # i . litpp # i . p absk dll
            ? < lc # i . costp + k 1 {
                = . costp + k 1 lc
                = . blnp + k 1 0
                = . blitp + k 1 + # i . blitp k 1
                = . br0p + k 1 # i . br0p k
                = . br1p + k 1 # i . br1p k
                = . br2p + k 1 # i . br2p k
            } {}
            ? <= + k 3 n { ( __zs_opt_matches o k ) } {}
            ? == do_insert 1 {
                ? <= + absk 4 bend {
                    : i h4 ( __zs_hash4 p absk hlog )
                    = . cp2 & absk chainmask # i . hpp h4
                    = . hpp h4 + absk 1
                } {}
                ? <= + absk 3 bend {
                    : i v3 | | # i . p absk << # i . p + absk 1 8 << # i . p + absk 2 16
                    : i h3w * 2 & >> * v3 2654435761 16 ZS_H3_MASK
                    = . h3pp + h3w 1 # i . h3pp h3w
                    = . h3pp h3w + absk 1
                } {}
            } {}
        } {}
        = k + k 1
    }
}

// Walk the DP result back into sequences, then forward into the
// (lits, sll, sml, soff) form the block writer takes. The forward walk
// replays the decoder's rep bookkeeping, so the offbase chosen here is
// exactly what the decoder will resolve back to the same distance.
@ __zs_opt_extract * ZsOpt o ( Vec u ) srcv ( Vec u ) lits
( Vec i ) sll ( Vec i ) sml ( Vec i ) soff * i reps → v {
    : i n . o blen
    : i bstart . o bstart
    : *i blnp . o bln
    : *i bofp . o bof
    : *i bllp . o bll
    : ( Vec i ) tll ( vec_new [i] )
    : ( Vec i ) tml ( vec_new [i] )
    : ( Vec i ) tof ( vec_new [i] )
    : ~ i j n
    ~ > j 0 {
        : i L # i . blnp j
        ? == L 0 { = j - j 1 } {
            : i ll # i . bllp j
            ( vec_push [i] tll ll )
            ( vec_push [i] tml L )
            ( vec_push [i] tof # i . bofp j )
            = j - j + L ll
        }
    }
    : i ns ( vec_len [i] tll )
    : *i tllp ( vec_data [i] tll )
    : *i tmlp ( vec_data [i] tml )
    : *i tofp ( vec_data [i] tof )
    : ~ i r0 # i . reps 0
    : ~ i r1 # i . reps 1
    : ~ i r2 # i . reps 2
    : ~ i cur bstart
    : ~ i si - ns 1
    ~ >= si 0 {
        : i ll # i . tllp si
        : i L # i . tmlp si
        : i off # i . tofp si
        ( vec_extend_range [u] lits srcv cur ll )
        = cur + cur ll
        : ~ i ob + off 3
        ? > ll 0 {
            ? == off r0 { = ob 1 } {
                ? == off r1 { = ob 2 } {
                    ? == off r2 { = ob 3 } {}
                }
            }
        } {
            ? == off r1 { = ob 1 } {
                ? == off r2 { = ob 2 } {
                    ? == off - r0 1 { = ob 3 } {}
                }
            }
        }
        ( vec_push [i] sll ll )
        ( vec_push [i] sml L )
        ( vec_push [i] soff ob )
        : ~ i nr0 off
        : ~ i nr1 r0
        : ~ i nr2 r1
        ? == off r0 { = nr1 r1 = nr2 r2 } {
            ? == off r1 { = nr2 r2 } {}
        }
        = r0 nr0
        = r1 nr1
        = r2 nr2
        = cur + cur L
        = si - si 1
    }
    ( vec_extend_range [u] lits srcv cur - + bstart n cur )
    = . reps 0 r0
    = . reps 1 r1
    = . reps 2 r2
    ( vec_free [i] tll )
    ( vec_free [i] tml )
    ( vec_free [i] tof )
}

// Sequence-code prices as the FSE coder will really charge them: the
// counts are normalized onto the same table the writer will build, and
// the price of a symbol is its share of that table — quantization
// included. Entropy-of-counts flattered symbols whose share rounds
// down, and the parse bought sequences the coder then billed higher.
@ __zs_seq_prices_q * i cnt i nsym i maxlog i nseq * i price → v {
    : ( Vec i ) cnt2 ( __zs_zeros nsym )
    : ( Vec i ) norm ( __zs_zeros nsym )
    : *i c2 ( vec_data [i] cnt2 )
    : ~ i t 0
    ~ < t nsym { = . c2 t # i . cnt t = t + t 1 }
    : ~ i log - ( __zs_hbit ? > nseq 1 - nseq 1 1 ) 2
    : i minlog + ( __zs_hbit nsym ) 1
    ? < log minlog { = log minlog } {}
    ? < log 5 { = log 5 } {}
    ? > log maxlog { = log maxlog } {}
    : i maxsym ( __zs_normalize cnt2 norm nsym log )
    ? <= maxsym 0 {
        ( __zs_prices_16 cnt nsym price )
        ( vec_free [i] cnt2 )
        ( vec_free [i] norm )
        ^ v
    } {}
    : *i np ( vec_data [i] norm )
    : i lt << log 4
    = t 0
    ~ < t nsym {
        : i share # i . np t
        = . price t ? > share 0 - lt ( __zs_log2_16 share ) + lt 16
        = t + t 1
    }
    ( vec_free [i] cnt2 )
    ( vec_free [i] norm )
}

// Prices for pass 2: what pass 1 actually chose, counted and turned
// into bits. Extra-bit costs are folded into each code's price so the
// relax loop adds one number.
@ __zs_opt_reprice * ZsOpt o ( Vec u ) lits ( Vec i ) sll ( Vec i ) sml
( Vec i ) soff ( Vec i ) scratch ( Vec i ) llx ( Vec i ) mlx → v {
    : *i cnt ( vec_data [i] scratch )
    : *i litpp . o litp
    : *i llpp . o llp
    : *i mlpp . o mlp
    : *i ofpp . o ofp
    : *i llbp2 . o llbp
    : *i mlbp2 . o mlbp
    : *i llxp ( vec_data [i] llx )
    : *i mlxp ( vec_data [i] mlx )
    : i ns ( vec_len [i] sll )
    // Literals are priced at the INTEGER bit lengths a Huffman tree
    // would actually assign, not at fractional entropy: the section is
    // Huffman-coded, so a byte costs a whole number of bits, and a
    // parse priced on the fraction buys literals the coder cannot
    // deliver that cheaply.
    ( __zs_fill0 cnt 256 )
    : i nlit ( vec_len [u] lits )
    : *u lp ( vec_data [u] lits )
    : ~ i q 0
    ~ < q nlit { : i b # i . lp q = . cnt b + # i . cnt b 1 = q + q 1 }
    : ( Vec i ) hlens ( __zs_zeros 256 )
    : ( Vec i ) hcnt ( __zs_zeros 256 )
    : *i hcp ( vec_data [i] hcnt )
    = q 0
    ~ < q 256 { = . hcp q # i . cnt q = q + q 1 }
    : i hmax ( __zs_huf_lengths hcnt hlens 256 )
    : *i hlp3 ( vec_data [i] hlens )
    ? & > hmax 0 <= hmax ZS_MAX_HUF_BITS {
        = q 0
        ~ < q 256 {
            : i hl # i . hlp3 q
            = . litpp q ? > hl 0 << hl 4 + << hmax 4 16
            = q + q 1
        }
    } {
        ( __zs_prices_16 cnt 256 litpp )
        = q 0
        ~ < q 256 {
            ? < # i . litpp q 16 { = . litpp q 16 } {}
            = q + q 1
        }
    }
    ( vec_free [i] hlens )
    ( vec_free [i] hcnt )
    // Sequence codes.
    : *i sllp ( vec_data [i] sll )
    : *i smlp ( vec_data [i] sml )
    : *i sofp ( vec_data [i] soff )
    ( __zs_fill0 cnt 64 )
    = q 0
    ~ < q ns {
        : i c ( __zs_ll_code_p llbp2 # i . sllp q )
        = . cnt c + # i . cnt c 1
        = q + q 1
    }
    ( __zs_seq_prices_q cnt 36 9 ns llpp )
    = q 0
    ~ < q 36 {
        = . llpp q + # i . llpp q << # i . llxp q 4
        = q + q 1
    }
    ( __zs_fill0 cnt 64 )
    = q 0
    ~ < q ns {
        : i c ( __zs_ml_code_p mlbp2 # i . smlp q )
        = . cnt c + # i . cnt c 1
        = q + q 1
    }
    ( __zs_seq_prices_q cnt 53 9 ns mlpp )
    = q 0
    ~ < q 53 {
        = . mlpp q + # i . mlpp q << # i . mlxp q 4
        = q + q 1
    }
    ( __zs_fill0 cnt 64 )
    = q 0
    ~ < q ns {
        : i c ( __zs_hbit # i . sofp q )
        = . cnt c + # i . cnt c 1
        = q + q 1
    }
    ( __zs_seq_prices_q cnt 32 8 ns ofpp )
    = q 0
    ~ < q 32 {
        = . ofpp q + # i . ofpp q << q 4
        = q + q 1
    }
}

// Pass-1 prices: literals from the block's own byte counts (most of
// the win — 'e' is not priced like 'q'), sequence codes from the
// format's predefined distributions.
@ __zs_opt_price_static * ZsOpt o i bstart i blen ( Vec i ) scratch
( Vec i ) llx ( Vec i ) mlx i variant → v {
    : *i cnt ( vec_data [i] scratch )
    : *u p . o p
    : *i litpp . o litp
    : *i llpp . o llp
    : *i mlpp . o mlp
    : *i ofpp . o ofp
    : *i llxp ( vec_data [i] llx )
    : *i mlxp ( vec_data [i] mlx )
    ( __zs_fill0 cnt 256 )
    : ~ i q 0
    ~ < q blen {
        : i b # i . p + bstart q
        = . cnt b + # i . cnt b 1
        = q + q 1
    }
    ( __zs_prices_16 cnt 256 litpp )
    = q 0
    ~ < q 256 {
        ? < # i . litpp q 16 { = . litpp q 16 } {}
        = q + q 1
    }
    : i lln ( __zs_ll_default scratch )
    = q 0
    ~ < q 36 { ? < # i . cnt q 1 { = . cnt q 1 } {} = q + q 1 }
    ( __zs_prices_16 cnt 36 llpp )
    = q 0
    ~ < q 36 {
        = . llpp q + # i . llpp q << # i . llxp q 4
        = q + q 1
    }
    // Two seed families, both fed to the same keep-the-cheapest
    // selector: predefined match-length prices settle into one
    // equilibrium, optimistic ones into another, and which wins is a
    // property of the data — dictionary text prefers the optimist,
    // word salad the predefined. Guessing is not required when both
    // fixed points can simply be visited.
    ? == variant 1 {
        = q 0
        ~ < q 53 {
            = . mlpp q + << # i . mlxp q 4 48
            = q + q 1
        }
    } {
        : i mln ( __zs_ml_default scratch )
        = q 0
        ~ < q 53 { ? < # i . cnt q 1 { = . cnt q 1 } {} = q + q 1 }
        ( __zs_prices_16 cnt 53 mlpp )
        = q 0
        ~ < q 53 {
            = . mlpp q + # i . mlpp q << # i . mlxp q 4
            = q + q 1
        }
    }
    // Offset codes are priced OPTIMISTICALLY in pass 1: the code cost
    // is set near its floor and only the unavoidable extra bits stay
    // real. Pessimism here is self-fulfilling — a match kind that pass
    // 1 never takes is absent from the statistics, so pass 2 prices it
    // high, so it is never taken; the marginal length-3 match at a
    // kilobyte's distance sits exactly on that edge, and the iteration
    // must be allowed to DISCOVER it before the numbers judge it.
    = q 0
    ~ < q 32 {
        = . ofpp q + << q 4 32
        = q + q 1
    }
}

@ __zs_encode_opt ( Vec u ) src i level → ( Vec u ) {
    : i n ( vec_len [u] src )
    : ( Vec u ) out ( vec_with_cap [u] + >> n 1 64 )
    ( __zs_write_header out n )
    ? == n 0 {
        ( __zs_block_header out 0 0 1 )
        ( __zs_pu32 out & ( xxh64 src ) 0xFFFFFFFF )
        ^ out
    } {}
    : *u p ( vec_data [u] src )
    : ~ i hlog 12
    ~ & < hlog 20 < << 1 hlog n { = hlog + hlog 1 }
    : ( Vec i ) htab ( __zs_zeros << 1 hlog )
    : i chainbits ? > hlog 18 18 hlog
    : i chainmask - << 1 + chainbits 2 1
    : ( Vec i ) chain ( __zs_zeros + chainmask 1 )
    : ( Vec i ) h3tab ( __zs_zeros * 2 + ZS_H3_MASK 1 )
    : ( Vec i ) llx ( __zs_ll_extra )
    : ( Vec i ) mlx ( __zs_ml_extra )
    : ( Vec i ) llb ( __zs_ll_base llx )
    : ( Vec i ) mlb ( __zs_ml_base mlx )
    : i cap + ZS_BLOCK_MAX 1
    : ( Vec i ) vcost ( __zs_zeros cap )
    : ( Vec i ) vbln ( __zs_zeros cap )
    : ( Vec i ) vbof ( __zs_zeros cap )
    : ( Vec i ) vbll ( __zs_zeros cap )
    : ( Vec i ) vblit ( __zs_zeros cap )
    : ( Vec i ) vbr0 ( __zs_zeros cap )
    : ( Vec i ) vbr1 ( __zs_zeros cap )
    : ( Vec i ) vbr2 ( __zs_zeros cap )
    : ( Vec i ) vlitp ( __zs_zeros 256 )
    : ( Vec i ) vllp ( __zs_zeros 36 )
    : ( Vec i ) vmlp ( __zs_zeros 53 )
    : ( Vec i ) vofp ( __zs_zeros 32 )
    : ( Vec i ) scratch ( __zs_zeros 256 )
    : ( Vec i ) reps3 ( __zs_zeros 3 )
    : ( Vec i ) vcco ( __zs_zeros << cap 3 )
    : ( Vec i ) vccm ( __zs_zeros << cap 3 )
    : ( Vec i ) vccn ( __zs_zeros cap )
    : *i reps3p ( vec_data [i] reps3 )
    : *ZsOpt o ( nurl_alloc Z ZsOpt )
    = . o p p
    = . o hp ( vec_data [i] htab )
    = . o cp ( vec_data [i] chain )
    = . o h3p ( vec_data [i] h3tab )
    = . o hlog hlog
    = . o chainmask chainmask
    = . o attempts ? >= level 19 256 ? >= level 16 64 32
    = . o suff ZS_OPT_SUFF
    = . o cost ( vec_data [i] vcost )
    = . o bln ( vec_data [i] vbln )
    = . o bof ( vec_data [i] vbof )
    = . o bll ( vec_data [i] vbll )
    = . o blit ( vec_data [i] vblit )
    = . o br0 ( vec_data [i] vbr0 )
    = . o br1 ( vec_data [i] vbr1 )
    = . o br2 ( vec_data [i] vbr2 )
    = . o litp ( vec_data [i] vlitp )
    = . o llp ( vec_data [i] vllp )
    = . o mlp ( vec_data [i] vmlp )
    = . o ofp ( vec_data [i] vofp )
    = . o llbp ( vec_data [i] llb )
    = . o mlbp ( vec_data [i] mlb )
    = . o cco ( vec_data [i] vcco )
    = . o ccm ( vec_data [i] vccm )
    = . o ccn ( vec_data [i] vccn )
    : ( Vec u ) lits ( vec_with_cap [u] ZS_BLOCK_MAX )
    : ( Vec i ) sll ( vec_new [i] )
    : ( Vec i ) sml ( vec_new [i] )
    : ( Vec i ) soff ( vec_new [i] )
    : *ZsWst wst ( __zs_wst_new )
    : ~ i rep0 1
    : ~ i rep1 4
    : ~ i rep2 8
    : ~ i pos 0
    // Balanced blocks: 196 kB as 98+98 beats 128+68 — the tables of two
    // like-sized blocks fit their halves better than one full block's
    // tables fit a full block and a stub's fit a stub.
    : i nblk / + n - ZS_BLOCK_MAX 1 ZS_BLOCK_MAX
    : i tgt / + n - nblk 1 nblk
    ~ < pos n {
        : i blen ? > - n pos tgt tgt - n pos
        = . o bstart pos
        = . o blen blen
        = . o rep0 rep0
        = . o rep1 rep1
        = . o rep2 rep2
        : i nseeds ? >= level 19 2 1
        : i extra ? >= level 19 15 ? >= level 16 3 1
        : ( Vec u ) bestbody ( vec_new [u] )
        : ( Vec i ) bestreps ( __zs_zeros 3 )
        : *i bestrepsp ( vec_data [i] bestreps )
        : ~ i bestsz ZS_OPT_INF
        : i last ? == + pos blen n 1 0
        ( __zs_wst_save wst 0 )
        : ~ i seed 0
        ~ < seed nseeds {
            ( __zs_opt_price_static o pos blen scratch llx mlx seed )
            // The chain and the candidate cache are built by the very
            // first parse of the block; every later parse — later
            // rounds and the other seed alike — replays the cache.
            = . o insert ? == seed 0 1 0
            ( __zs_opt_parse o )
            = . o insert 0
            ( vec_clear [u] lits )
            ( vec_clear [i] sll )
            ( vec_clear [i] sml )
            ( vec_clear [i] soff )
            = . reps3p 0 rep0
            = . reps3p 1 rep1
            = . reps3p 2 rep2
            ( __zs_opt_extract o src lits sll sml soff reps3p )
            : ~ i round 0
            ~ <= round extra {
                ? > round 0 {
                    ( __zs_opt_reprice o lits sll sml soff scratch llx mlx )
                    ( __zs_opt_parse o )
                    ( vec_clear [u] lits )
                    ( vec_clear [i] sll )
                    ( vec_clear [i] sml )
                    ( vec_clear [i] soff )
                    = . reps3p 0 rep0
                    = . reps3p 1 rep1
                    = . reps3p 2 rep2
                    ( __zs_opt_extract o src lits sll sml soff reps3p )
                } {}
                : ( Vec u ) trial ( vec_new [u] )
                // Every trial writes from the SAME pre-block state: a
                // repeat or treeless choice may only reference tables
                // that actually went out in a previous block, never
                // ones a losing trial of THIS block imagined sending.
                ( __zs_wst_restore wst 0 )
                ( __zs_write_block trial src pos blen last lits sll sml soff
                llb mlb llx mlx wst )
                ? < ( vec_len [u] trial ) bestsz {
                    = bestsz ( vec_len [u] trial )
                    ( vec_clear [u] bestbody )
                    ( vec_extend [u] bestbody trial )
                    = . bestrepsp 0 # i . reps3p 0
                    = . bestrepsp 1 # i . reps3p 1
                    = . bestrepsp 2 # i . reps3p 2
                    ( __zs_wst_save wst 1 )
                } {}
                ( vec_free [u] trial )
                = round + round 1
            }
            = seed + seed 1
        }
        // The winner's post-block state is what the next block builds on.
        ( __zs_wst_restore wst 1 )
        ( vec_extend [u] out bestbody )
        ( vec_free [u] bestbody )
        = rep0 # i . bestrepsp 0
        = rep1 # i . bestrepsp 1
        = rep2 # i . bestrepsp 2
        ( vec_free [i] bestreps )
        = pos + pos blen
    }
    ( __zs_pu32 out & ( xxh64 src ) 0xFFFFFFFF )
    ( __zs_wst_free wst )
    ( nurl_free # s o )
    ( vec_free [i] htab )
    ( vec_free [i] chain )
    ( vec_free [i] h3tab )
    ( vec_free [i] llx )
    ( vec_free [i] mlx )
    ( vec_free [i] llb )
    ( vec_free [i] mlb )
    ( vec_free [i] vcost )
    ( vec_free [i] vbln )
    ( vec_free [i] vbof )
    ( vec_free [i] vbll )
    ( vec_free [i] vblit )
    ( vec_free [i] vbr0 )
    ( vec_free [i] vbr1 )
    ( vec_free [i] vbr2 )
    ( vec_free [i] vlitp )
    ( vec_free [i] vllp )
    ( vec_free [i] vmlp )
    ( vec_free [i] vofp )
    ( vec_free [i] scratch )
    ( vec_free [i] reps3 )
    ( vec_free [i] vcco )
    ( vec_free [i] vccm )
    ( vec_free [i] vccn )
    ( vec_free [u] lits )
    ( vec_free [i] sll )
    ( vec_free [i] sml )
    ( vec_free [i] soff )
    ^ out
}

@ zstd_encode_at ( Vec u ) src i level → ( Vec u ) {
    ? >= level 13 { ^ ( __zs_encode_opt src level ) } {}
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
    : *ZsWst wst ( __zs_wst_new )
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
        llb mlb llx mlx wst )
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
    ( __zs_wst_free wst )
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
