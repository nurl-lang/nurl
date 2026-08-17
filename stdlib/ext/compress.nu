// stdlib/ext/compress.nu — zlib, gzip and Zstandard framing, in one
// place and with nothing underneath.
//
// Every codec here is pure NURL: DEFLATE from `std/deflate.nu` and
// Zstandard from `std/zstd.nu`. There is no libz, no libzstd, no
// runtime.c bridge and no build-time sentinel — this module compiles
// and runs anywhere the compiler does, including a freestanding target,
// a unikernel, and wasm. (It did not always: the `zstd_*` calls were an
// `& `zstd` @ ...` FFI, and because an FFI declaration is checked
// against a build-time sentinel, a machine without libzstd-dev could
// not compile this file AT ALL — not even to use gzip.)
//
// API:
//
//   ( zlib_compress    ( Vec u ) src )         → ! ( Vec u ) CompressErr
//   ( zlib_compress_at ( Vec u ) src i level ) → ! ( Vec u ) CompressErr
//   ( zlib_decompress  ( Vec u ) src )         → ! ( Vec u ) CompressErr
//
//   ( gzip_compress    ( Vec u ) src )         → ! ( Vec u ) CompressErr
//   ( gzip_compress_at ( Vec u ) src i level ) → ! ( Vec u ) CompressErr
//   ( gzip_decompress  ( Vec u ) src )         → ! ( Vec u ) CompressErr
//
//   ( zstd_compress    ( Vec u ) src )         → ! ( Vec u ) CompressErr
//   ( zstd_compress_at ( Vec u ) src i level ) → ! ( Vec u ) CompressErr
//   ( zstd_decompress  ( Vec u ) src )         → ! ( Vec u ) CompressErr
//
// Memory model:
//
//   * Inputs are BORROWED — the caller still owns and frees the source
//     Vec[u]. Outputs are OWNED Vec[u] handles; free with `vec_free [u]`.
//   * Empty input produces an empty output for both compress and
//     decompress. No magic header bytes are produced for empty payloads.
//
// Wire format:
//
//   * `zlib_*` uses the **zlib stream format** (RFC 1950): 2-byte
//     header (CMF + FLG) followed by raw DEFLATE blocks then a 4-byte
//     Adler-32 checksum. Tools like `gzip` / `gunzip` reject this — use
//     `gzip_*` for filesystem / HTTP `Content-Encoding: gzip` interop.
//   * `gzip_*` uses the **gzip file format** (RFC 1952): 10-byte header
//     (`1f 8b` magic, deflate method, mtime, OS), raw DEFLATE body,
//     CRC-32 + ISIZE trailer. Directly interoperable with `gzip` /
//     `gunzip` / `Content-Encoding: gzip`.
//   * `zstd_*` uses Zstandard's frame format (RFC 8878) — directly
//     interoperable with the `zstd` / `unzstd` CLI tools, in both
//     directions, which `tools/zstd_gate.sh` checks against those very
//     tools.
//
// Compression levels:
//   * zlib: 0 (no compression) … 9 (max). Default 6. The pure encoder
//     has a single mode, so the level is accepted and ignored.
//   * zstd: 1 … 19. Default 3. Levels up to 12 are greedy with lazy
//     matching; 13 and up run the optimal parser. See `std/zstd.nu`.

$ `stdlib/core/vec.nu`
$ `stdlib/std/deflate.nu`  // pure-NURL DEFLATE/inflate + crc32/adler32
$ `stdlib/std/zstd.nu`  // pure-NURL Zstandard (RFC 8878)

: | CompressErr {
    CompressBufTooSmall  // dst buffer overflow on grow-and-retry
    CompressData  // malformed input (zlib Z_DATA_ERROR / zstd error code)
    CompressMemory  // libz Z_MEM_ERROR / zstd out-of-memory
    CompressOther
}

@ compress_err_name CompressErr e → s {
    ^ ?? e {
        CompressBufTooSmall → `CompressBufTooSmall`
        CompressData → `CompressData`
        CompressMemory → `CompressMemory`
        CompressOther → `CompressOther`
    }
}

// ── DEFLATE framing helpers (over stdlib/std/deflate.nu) ────────────

@ __df_to_compress_err DeflateErr e → CompressErr {
    ^ ?? e {
        DeflateBadBlock → # CompressErr CompressData
        DeflateBadCode → # CompressErr CompressData
        DeflateBadLength → # CompressErr CompressData
        DeflateBadDist → # CompressErr CompressData
        DeflateTruncated → # CompressErr CompressData
        DeflateOther → # CompressErr CompressOther
    }
}

@ __df_be32 ( Vec u ) v i x → v {
    ( vec_push [u] v # u & >> x 24 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & x 255 )
}

@ __df_le32 ( Vec u ) v i x → v {
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
}

// ── zlib public API ───────────────────────────────────────────────

@ zlib_compress ( Vec u ) src → !( Vec u ) CompressErr {
    ^ ( zlib_compress_at src 6 )
}

// zlib stream (RFC 1950): 2-byte header (0x78 0x9C) + raw DEFLATE +
// 4-byte big-endian Adler-32. `level` is accepted for API compatibility;
// the pure encoder has a single mode.
@ zlib_compress_at ( Vec u ) src i level → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    : ( Vec u ) body ( deflate src )
    : ( Vec u ) out ( vec_with_cap [u] + ( vec_len [u] body ) 6 )
    ( vec_push [u] out # u 120 )  // CMF 0x78
    ( vec_push [u] out # u 156 )  // FLG 0x9C
    ( vec_extend [u] out body )
    ( __df_be32 out ( adler32 src ) )
    ( vec_free [u] body )
    ^ @ !( Vec u ) CompressErr { T out }
}

@ zlib_decompress ( Vec u ) src → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    ? < n 6 { ^ @ !( Vec u ) CompressErr { F CompressData } } {}
    // Strip the 2-byte header and 4-byte Adler-32 trailer.
    : ( Vec u ) raw ( vec_new [u] )
    : *u sp ( vec_data [u] src )
    ( bytes_extend_raw raw # s + # i sp 2 - n 6 )
    : !( Vec u ) DeflateErr r ( inflate raw )
    ( vec_free [u] raw )
    ?? r {
        F e → ^ @ !( Vec u ) CompressErr { F ( __df_to_compress_err e ) }
        T out → ^ @ !( Vec u ) CompressErr { T out }
    }
}

// ── gzip public API ───────────────────────────────────────────────

@ gzip_compress ( Vec u ) src → !( Vec u ) CompressErr {
    ^ ( gzip_compress_at src 6 )
}

// gzip stream (RFC 1952): 10-byte header + raw DEFLATE + CRC-32 (LE) +
// ISIZE (LE, length mod 2^32). `level` accepted for API compatibility.
@ gzip_compress_at ( Vec u ) src i level → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    : ( Vec u ) body ( deflate src )
    : ( Vec u ) out ( vec_with_cap [u] + ( vec_len [u] body ) 18 )
    ( vec_push [u] out # u 31 )  // ID1 0x1f
    ( vec_push [u] out # u 139 )  // ID2 0x8b
    ( vec_push [u] out # u 8 )  // CM = deflate
    ( vec_push [u] out # u 0 )  // FLG
    ( vec_push [u] out # u 0 ) ( vec_push [u] out # u 0 )
    ( vec_push [u] out # u 0 ) ( vec_push [u] out # u 0 )  // MTIME = 0
    ( vec_push [u] out # u 0 )  // XFL
    ( vec_push [u] out # u 255 )  // OS = unknown
    ( vec_extend [u] out body )
    ( __df_le32 out ( crc32 src ) )
    ( __df_le32 out & n 4294967295 )
    ( vec_free [u] body )
    ^ @ !( Vec u ) CompressErr { T out }
}

@ gzip_decompress ( Vec u ) src → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    ? < n 2 { ^ @ !( Vec u ) CompressErr { F CompressData } } {}
    : *u sp ( vec_data [u] src )
    // Accept a zlib stream too (matches zlib's inflateInit2(15+32) auto-
    // detect): non-gzip-magic input is routed to zlib_decompress.
    ? | != # i . sp 0 31 != # i . sp 1 139 {
        ^ ( zlib_decompress src )
    } {}
    ? < n 18 { ^ @ !( Vec u ) CompressErr { F CompressData } } {}
    : i flg # i . sp 3
    : ~ i p 10
    // FEXTRA (4): 2-byte XLEN + XLEN bytes.
    ? != & flg 4 0 {
        ? > + p 2 n { ^ @ !( Vec u ) CompressErr { F CompressData } } {}
        : i xlen + # i . sp p << # i . sp + p 1 8
        = p + + p 2 xlen
    } {}
    // FNAME (8): NUL-terminated.
    ? != & flg 8 0 { ~ & < p n != # i . sp p 0 { = p + p 1 } = p + p 1 } {}
    // FCOMMENT (16): NUL-terminated.
    ? != & flg 16 0 { ~ & < p n != # i . sp p 0 { = p + p 1 } = p + p 1 } {}
    // FHCRC (2): 2 bytes.
    ? != & flg 2 0 { = p + p 2 } {}
    ? >= p - n 8 { ^ @ !( Vec u ) CompressErr { F CompressData } } {}
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_raw raw # s + # i sp p - - n 8 p )
    : !( Vec u ) DeflateErr r ( inflate raw )
    ( vec_free [u] raw )
    ?? r {
        F e → ^ @ !( Vec u ) CompressErr { F ( __df_to_compress_err e ) }
        T out → ^ @ !( Vec u ) CompressErr { T out }
    }
}

// ── zstd public API ───────────────────────────────────────────────
//
// Zstandard is `std/zstd.nu` — pure NURL, no library underneath. These
// wrappers exist so a caller that already speaks `CompressErr` does not
// have to learn a second error type.

@ __zstd_to_compress_err ZstdErr e → CompressErr {
    ^ ?? e {
        ZstdTooLarge → # CompressErr CompressMemory
        _ → # CompressErr CompressData
    }
}

@ zstd_compress ( Vec u ) src → !( Vec u ) CompressErr {
    ^ ( zstd_compress_at src 3 )
}

@ zstd_compress_at ( Vec u ) src i level → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    ^ @ !( Vec u ) CompressErr { T ( zstd_encode_at src level ) }
}

@ zstd_decompress ( Vec u ) src → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    ?? ( zstd_decode src ) {
        T out → { ^ @ !( Vec u ) CompressErr { T out } }
        F e → { ^ @ !( Vec u ) CompressErr { F ( __zstd_to_compress_err e ) } }
    }
}

// ── Raw-DEFLATE streaming codec (RFC 1951, no zlib/gzip wrapper) ────
//
// The `zlib_*` / `gzip_*` helpers above are ONE-SHOT: each call spins up
// a fresh `z_stream`, runs to Z_FINISH, and tears it down. RFC 7692
// WebSocket permessage-deflate instead needs a PERSISTENT stream that
// survives across many messages so the LZ77 sliding window carries over
// ("context takeover"), and each message is flushed with Z_SYNC_FLUSH
// rather than ended with Z_FINISH. This section exposes exactly that as
// a reusable raw-DEFLATE codec — raw because permessage-deflate frames
// carry bare DEFLATE blocks with no 2-byte zlib header / 4-byte Adler-32
// trailer (achieved via libz's NEGATIVE windowBits).
//
//   ( raw_deflate_new   i window_bits i level ) → ! ZDeflate CompressErr
//   ( raw_deflate_block ZDeflate d ( Vec u ) in ) → ! ( Vec u ) CompressErr
//   ( raw_deflate_reset ZDeflate d )               → v   // drop the window
//   ( raw_deflate_free  ZDeflate d )               → v
//   ( raw_inflate_new   i window_bits )            → ! ZInflate CompressErr
//   ( raw_inflate_block ZInflate d ( Vec u ) in i max_out )
//                                                  → ! ( Vec u ) CompressErr
//   ( raw_inflate_reset ZInflate d )               → v
//   ( raw_inflate_free  ZInflate d )               → v
//
// `window_bits` is clamped to [9, 15]. libz changes a raw-deflate
// windowBits of 8 to 9 internally (and 8 is unusable for raw inflate),
// so 8 is treated as 9; callers needing a true 256-byte window are out
// of scope. A deflater and the matching inflater MUST agree the encoder
// never exceeds the inflater's window — inflating at 15 (the max) is
// always safe regardless of the encoder's choice.
//
// Memory: ZDeflate / ZInflate own a heap `z_stream`; there is no
// auto-Drop for the raw `*u` handle, so callers MUST pair every
// successful `*_new` with a `*_free`.

// A persistent raw-DEFLATE compressor. `history` is the uncompressed
// window carried across messages so emitted matches can back-reference
// prior messages (context takeover). raw_deflate_reset drops it.
: ZDeflate { ( Vec u ) history }

// A persistent raw-INFLATE decompressor. `history` is the LZ77 window
// carried across messages so context-takeover streams (a peer that
// back-references prior messages) decode correctly.
: ZInflate { ( Vec u ) history }

@ raw_deflate_new i window_bits i level → !ZDeflate CompressErr {
    ^ @ !ZDeflate CompressErr { T @ ZDeflate { ( vec_new [u] ) } }
}

// Compress one message into a non-final fixed block + sync-flush; the
// output ends with the 00 00 FF FF marker (RFC 7692 §7.2.1 strips it
// before framing). The sliding window is RETAINED across calls (context
// takeover) unless raw_deflate_reset is invoked.
@ raw_deflate_block ZDeflate d ( Vec u ) input → !( Vec u ) CompressErr {
    : ( Vec u ) out ( deflate_block_dict . d history input )
    // Extend the window with this message, trimmed to the last 32 KiB.
    ( bytes_extend_bytes . d history input )
    : i hl ( vec_len [u] . d history )
    ? > hl 32768 {
        : *u hp ( vec_data [u] . d history )
        ( nurl_memmove hp # *u + # i hp - hl 32768 32768 )
        : b _t ( vec_set_len [u] . d history 32768 )
    } {}
    ^ @ !( Vec u ) CompressErr { T out }
}

@ raw_deflate_reset ZDeflate d → v {
    : b _r ( vec_set_len [u] . d history 0 )
}

@ raw_deflate_free ZDeflate d → v {
    ( vec_free [u] . d history )
}

@ raw_inflate_new i window_bits → !ZInflate CompressErr {
    ^ @ !ZInflate CompressErr { T @ ZInflate { ( vec_new [u] ) } }
}

// Decompress one message. The caller appends the 4-byte 00 00 FF FF tail
// (RFC 7692 §7.2.2) before calling. The sliding window is RETAINED across
// calls unless raw_inflate_reset is invoked. `max_out` (>0) caps the
// per-message output as a decompression-bomb guard.
@ raw_inflate_block ZInflate d ( Vec u ) input i max_out → !( Vec u ) CompressErr {
    : i n ( vec_len [u] input )
    ? <= n 0 { ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) } } {}
    : !( Vec u ) DeflateErr r ( inflate_stream . d history input max_out )
    ?? r {
        F e → {
            // inflate_stream signals the max_out (decompression-bomb) cap
            // with DeflateBadLength → surface it as CompressBufTooSmall.
            : CompressErr ce ?? e {
                DeflateBadLength → # CompressErr CompressBufTooSmall
                _ → ( __df_to_compress_err e )
            }
            ^ @ !( Vec u ) CompressErr { F ce }
        }
        T out → ^ @ !( Vec u ) CompressErr { T out }
    }
}

@ raw_inflate_reset ZInflate d → v {
    : b _r ( vec_set_len [u] . d history 0 )
}

@ raw_inflate_free ZInflate d → v {
    ( vec_free [u] . d history )
}
