// stdlib/ext/compress.nu — DEFLATE (zlib) and Zstandard bindings via
// direct libz / libzstd FFI.
//
// **Pure-NURL FFI** — every external symbol is declared with `& `z` @ ...`
// or `& `zstd` @ ...` directly in this file. No runtime.c bridge. The
// build-time FFI-lib check (`compiler/nurlc.nu::gen_ffi_decl`) consults
// `stdlib/runtime.z` / `stdlib/runtime.zstd` sentinels emitted by
// `build.sh` so missing zlib1g-dev / libzstd-dev fails at compile time
// with a clear diagnostic rather than a cryptic linker error.
//
// API:
//
//   ( zlib_compress    ( Vec u ) src )         → ! ( Vec u ) CompressErr
//   ( zlib_compress_at ( Vec u ) src i level ) → ! ( Vec u ) CompressErr
//   ( zlib_decompress  ( Vec u ) src )         → ! ( Vec u ) CompressErr
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
// Wire format (v1, intentional MVP gaps):
//
//   * `zlib_*` uses the **zlib stream format** (RFC 1950): 2-byte
//     header (CMF + FLG) followed by raw DEFLATE blocks then a 4-byte
//     Adler-32 checksum. This is NOT the gzip file format (RFC 1952),
//     which adds a 10-byte header (`1f 8b` magic, flags, mtime, OS) and
//     a CRC-32 + ISIZE trailer. Tools like `gzip` / `gunzip` reject
//     `zlib_compress` output. The matching helpers for the gzip file
//     wire format are tracked as next-step work (would need libz's
//     `deflateInit2_` / `inflateInit2_` stream API + a fixed z_stream
//     struct allocation; cleanest via a runtime.c bridge).
//   * `zstd_*` uses Zstandard's standard frame format
//     (RFC 8478-compatible) — directly interoperable with the `zstd` /
//     `unzstd` CLI tools.
//
// Compression levels:
//   * zlib: 0 (no compression) … 9 (max). Default 6 (Z_DEFAULT_COMPRESSION
//     value passes through libz unchanged via `compress2`).
//   * zstd: -22 (fast negative levels) … 22 (max). Default 3.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`

: | CompressErr {
    CompressBufTooSmall   // dst buffer overflow on grow-and-retry
    CompressData          // malformed input (zlib Z_DATA_ERROR / zstd error code)
    CompressMemory        // libz Z_MEM_ERROR / zstd out-of-memory
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

// ── zlib FFI ───────────────────────────────────────────────────────
//
// `compress2(dest, &destLen, source, sourceLen, level)`:
//   dest:      destination buffer (writable)
//   destLen:   in/out — caller sets to dest capacity, libz updates to
//              actual compressed length
//   source:    input buffer
//   sourceLen: input length
//   level:     0..9
// Returns 0 (Z_OK) on success, negative on error.
//
// `uncompress(dest, &destLen, source, sourceLen)`:
//   destLen:   in/out — caller sets to dest capacity, libz updates to
//              decompressed length. -5 (Z_BUF_ERROR) when dest is too
//              small — we grow and retry.
//
// `compressBound(sourceLen)` returns the maximum size compress2 will
// produce. Add a small constant safety margin (libz documents this).

& `z` @ compress2     *u dest *i destLen *u source i sourceLen i32 level → i32
& `z` @ uncompress    *u dest *i destLen *u source i sourceLen           → i32
& `z` @ compressBound i sourceLen                                          → i

// ── zstd FFI ───────────────────────────────────────────────────────
//
// `ZSTD_compress(dst, dstCap, src, srcSize, level) → size_t`
//   returns either the compressed size, or an error code that
//   `ZSTD_isError(code)` flags as non-zero.
// `ZSTD_decompress(dst, dstCap, src, srcSize) → size_t` likewise.
// `ZSTD_compressBound(srcSize) → size_t`.
// `ZSTD_getFrameContentSize(src, srcSize) → unsigned long long`:
//   exact decompressed size (zstd frame embeds it), or the sentinel
//   `ZSTD_CONTENTSIZE_UNKNOWN` (-1ULL) / `ZSTD_CONTENTSIZE_ERROR`
//   (-2ULL) when the frame is streamed without a size field or invalid.
// `ZSTD_isError(code) → unsigned` — 1 if `code` is an error.

& `zstd` @ ZSTD_compress              *u dst i dstCap *u src i srcSize i32 level → i
& `zstd` @ ZSTD_decompress            *u dst i dstCap *u src i srcSize           → i
& `zstd` @ ZSTD_compressBound         i srcSize                                    → i
& `zstd` @ ZSTD_getFrameContentSize   *u src i srcSize                             → i
& `zstd` @ ZSTD_isError               i code                                       → i32

// ── zlib public API ───────────────────────────────────────────────

@ zlib_compress ( Vec u ) src → !( Vec u ) CompressErr {
    ^ ( zlib_compress_at src 6 )
}

@ zlib_compress_at ( Vec u ) src i level → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    : i bound ( compressBound n )
    : ( Vec u ) out ( vec_with_cap [u] bound )
    ( vec_reserve [u] out bound )
    : *u dst ( vec_data [u] out )
    : *u srcp ( vec_data [u] src )
    : s dst_len_p ( nurl_alloc 8 )
    ( nurl_poke dst_len_p 0 bound )
    : i ri ( compress2 dst # *i dst_len_p srcp n level )
    : i actual_len ( nurl_peek dst_len_p 0 )
    ( nurl_free dst_len_p )
    ? != ri 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CompressErr { F ( __zlib_map_err ri ) }
    } {}
    : b _r ( vec_set_len [u] out actual_len )
    ^ @ !( Vec u ) CompressErr { T out }
}

@ zlib_decompress ( Vec u ) src → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    // Decompressed size is not embedded in zlib stream format — guess
    // 4x input as a starting point, double on Z_BUF_ERROR (-5).
    : ~ i guess * n 4
    ? < guess 4096 { = guess 4096 } {}
    : ~ b done F
    : ~ b ok F
    : ( Vec u ) out ( vec_with_cap [u] guess )
    : ~ i actual 0
    : ~ CompressErr last CompressOther
    ~ ! done {
        ( vec_reserve [u] out guess )
        : *u dst ( vec_data [u] out )
        : *u srcp ( vec_data [u] src )
        : s dst_len_p ( nurl_alloc 8 )
        ( nurl_poke dst_len_p 0 guess )
        : i ri ( uncompress dst # *i dst_len_p srcp n )
        : i actual_len ( nurl_peek dst_len_p 0 )
        ( nurl_free dst_len_p )
        ? == ri 0 {
            = actual actual_len
            = ok T
            = done T
        } {
            ? == ri -5 {
                // Z_BUF_ERROR — dst was too small; grow + retry.
                = guess * guess 2
                ? > guess 1073741824 {
                    = last CompressBufTooSmall
                    = done T
                } {}
            } {
                = last ( __zlib_map_err ri )
                = done T
            }
        }
    }
    ? ok {
        : b _r ( vec_set_len [u] out actual )
        ^ @ !( Vec u ) CompressErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CompressErr { F last }
    }
}

@ __zlib_map_err i ri → CompressErr {
    // Z_DATA_ERROR = -3, Z_MEM_ERROR = -4
    ? == ri -3 { ^ @ CompressErr { CompressData } } {}
    ? == ri -4 { ^ @ CompressErr { CompressMemory } } {}
    ^ @ CompressErr { CompressOther }
}

// ── zstd public API ───────────────────────────────────────────────

@ zstd_compress ( Vec u ) src → !( Vec u ) CompressErr {
    ^ ( zstd_compress_at src 3 )
}

@ zstd_compress_at ( Vec u ) src i level → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    : i bound ( ZSTD_compressBound n )
    : ( Vec u ) out ( vec_with_cap [u] bound )
    ( vec_reserve [u] out bound )
    : *u dst ( vec_data [u] out )
    : *u srcp ( vec_data [u] src )
    : i rc ( ZSTD_compress dst bound srcp n level )
    : i is_err ( ZSTD_isError rc )
    ? != is_err 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CompressErr { F CompressOther }
    } {}
    : b _r ( vec_set_len [u] out rc )
    ^ @ !( Vec u ) CompressErr { T out }
}

@ zstd_decompress ( Vec u ) src → !( Vec u ) CompressErr {
    : i n ( vec_len [u] src )
    ? <= n 0 {
        ^ @ !( Vec u ) CompressErr { T ( vec_new [u] ) }
    } {}
    : *u srcp ( vec_data [u] src )
    : i frame_size ( ZSTD_getFrameContentSize srcp n )
    // Frame header missing the size field → fall back to a generous
    // guess + grow. ZSTD_CONTENTSIZE_UNKNOWN = -1, _ERROR = -2.
    : ~ i cap frame_size
    ? <= cap 0 {
        = cap * n 8
        ? < cap 4096 { = cap 4096 } {}
    } {}
    : ( Vec u ) out ( vec_with_cap [u] cap )
    ( vec_reserve [u] out cap )
    : *u dst ( vec_data [u] out )
    : i rc ( ZSTD_decompress dst cap srcp n )
    : i is_err ( ZSTD_isError rc )
    ? != is_err 0 {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CompressErr { F CompressData }
    } {}
    : b _r ( vec_set_len [u] out rc )
    ^ @ !( Vec u ) CompressErr { T out }
}
