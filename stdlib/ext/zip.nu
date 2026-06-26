// stdlib/ext/zip.nu — ZIP archive read/write (store + deflate).
//
// THE interchange container (xlsx / docx / epub / jar are all zip).
// In-memory archives over ( Vec u ) — pair with read_file_bytes /
// write_file_bytes for files. Compression uses the pure-NURL DEFLATE
// codec (stdlib/std/deflate.nu via ext/compress.nu) — zip stores bare
// raw deflate streams, so `deflate`/`inflate` are used directly.
//
// Writer (builder):
//   ( zip_new )                            → Zip
//   ( zip_add Zip s name ( Vec u ) data )  → ! v ZipErr   deflate, or store
//                                            when deflate isn't smaller
//   ( zip_add_stored Zip s name ( Vec u ) data ) → ! v ZipErr   force store
//   ( zip_finish Zip )                     → ( Vec u )    archive bytes;
//                                            consumes the builder
// Reader:
//   ( zip_open ( Vec u ) bytes )           → ! ZipArchive ZipErr
//       BORROWS `bytes` — keep them alive until zip_close.
//   ( zip_count ZipArchive )               → i
//   ( zip_name_at ZipArchive i )           → ? String     owned copy
//   ( zip_size_at ZipArchive i )           → ? i          uncompressed size
//   ( zip_extract ZipArchive i )           → ! ( Vec u ) ZipErr   crc-checked
//   ( zip_extract_name ZipArchive s name ) → ! ( Vec u ) ZipErr
//   ( zip_close ZipArchive )               → v
//
// Determinism: entries carry a fixed DOS timestamp (1980-01-01), so
// identical inputs produce byte-identical archives.
//
// Out of scope: zip64 (>4 GiB / >65535 entries), encryption, data
// descriptors (bit 3) on WRITE; on READ, descriptor-flagged entries
// work because the central directory carries the real sizes/crc.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/compress.nu`  // pure deflate/inflate + crc32 (via std/deflate.nu)

: | ZipErr {
    ZipBadArchive  // no/garbled end-of-central-directory or headers
    ZipUnsupported  // zip64 / encrypted / unknown compression method
    ZipCrc  // extracted bytes fail the stored CRC-32
    ZipInflate  // deflate stream is corrupt
    ZipDeflate  // compression failed
    ZipNotFound  // zip_extract_name: no such entry
    ZipTooLarge  // would need zip64
}

@ zip_err_name ZipErr e → s {
    ^ ?? e {
        ZipBadArchive → `bad-archive`
        ZipUnsupported → `unsupported`
        ZipCrc → `crc-mismatch`
        ZipInflate → `inflate-error`
        ZipDeflate → `deflate-error`
        ZipNotFound → `not-found`
        ZipTooLarge → `too-large`
    }
}

// ── little-endian byte helpers ──────────────────────────────────────

@ __zip_push_u16 ( Vec u ) out i v → v {
    ( vec_push [u] out # u & v 255 )
    ( vec_push [u] out # u & / v 256 255 )
}

@ __zip_push_u32 ( Vec u ) out i v → v {
    ( vec_push [u] out # u & v 255 )
    ( vec_push [u] out # u & / v 256 255 )
    ( vec_push [u] out # u & / v 65536 255 )
    ( vec_push [u] out # u & / v 16777216 255 )
}

@ __zip_rd_u16 * u p i off → i {
    ^ + # i . p off * # i . p + off 1 256
}

@ __zip_rd_u32 * u p i off → i {
    ^ + + + # i . p off * # i . p + off 1 256 * # i . p + off 2 65536 * # i . p + off 3 16777216
}

// ── raw deflate / inflate (windowBits −15) ──────────────────────────

// Compress src → fresh Vec of raw DEFLATE. None when it produced no gain
// (caller stores instead).
@ __zip_deflate ( Vec u ) src → ?( Vec u ) {
    : i srclen ( vec_len [u] src )
    ? <= srclen 0 { ^ @ ?( Vec u ) { F } } {}
    : ( Vec u ) out ( deflate src )
    ? >= ( vec_len [u] out ) srclen { ( vec_free [u] out ) ^ @ ?( Vec u ) { F } } {}  // no gain → store
    ^ @ ?( Vec u ) { T out }
}

// Inflate exactly `usize` bytes out of src[off .. off+csize).
@ __zip_inflate * u srcp i off i csize i usize → ?( Vec u ) {
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_raw raw # s + # i srcp off csize )
    : !( Vec u ) DeflateErr r ( inflate raw )
    ( vec_free [u] raw )
    ?? r {
        F _ → ^ @ ?( Vec u ) { F }
        T out → {
            ? != ( vec_len [u] out ) usize { ( vec_free [u] out ) ^ @ ?( Vec u ) { F } } {}
            ^ @ ?( Vec u ) { T out }
        }
    }
}

// ── writer ──────────────────────────────────────────────────────────
//
// Zip builder: `body` accumulates local headers + file data as they
// are added; `central` accumulates the matching central-directory
// records; `count` in ctl slot 0. Offsets are byte positions in body.

: Zip { s ctl ( Vec u ) body ( Vec u ) central }

: i ZIP_DOSDATE 33  // 1980-01-01 → (0<<9)|(1<<5)|1

@ zip_new → Zip {
    ^ @ Zip { ( nurl_zalloc 8 ) ( vec_new [u] ) ( vec_new [u] ) }
}

// Shared add: method 8 with `comp` bytes, or method 0 when comp is None.
@ __zip_add_entry Zip z s name ( Vec u ) data ? ( Vec u ) comp → !v ZipErr {
    : i namelen ( nurl_str_len name )
    : i usize ( vec_len [u] data )
    ? | > usize 4294967295 > namelen 65535 { ^ @ !v ZipErr { F ZipTooLarge } } {}
    : i crc ( crc32 data )
    : i offset ( vec_len [u] . z body )
    ? > offset 4294967295 { ^ @ !v ZipErr { F ZipTooLarge } } {}
    : ~ i method 0
    : ~ i csize usize
    ?? comp { T c → { = method 8 = csize ( vec_len [u] c ) } F → {} }
    // ── local file header ──
    : ( Vec u ) b . z body
    ( __zip_push_u32 b 0x04034b50 )
    ( __zip_push_u16 b 20 )  // version needed
    ( __zip_push_u16 b 0 )  // flags
    ( __zip_push_u16 b method )
    ( __zip_push_u16 b 0 )  // dos time
    ( __zip_push_u16 b ZIP_DOSDATE )
    ( __zip_push_u32 b crc )
    ( __zip_push_u32 b csize )
    ( __zip_push_u32 b usize )
    ( __zip_push_u16 b namelen )
    ( __zip_push_u16 b 0 )  // extra len
    ( bytes_extend_str b name )
    ?? comp {
        T c → {
            : i cn ( vec_len [u] c )
            : *u cp ( vec_data [u] c )
            : ~ i k 0
            ~ < k cn { ( vec_push [u] b . cp k ) = k + k 1 }
            ( vec_free [u] c )
        }
        F → {
            : *u dp ( vec_data [u] data )
            : ~ i k 0
            ~ < k usize { ( vec_push [u] b . dp k ) = k + k 1 }
        }
    }
    // ── central directory record ──
    : ( Vec u ) cd . z central
    ( __zip_push_u32 cd 0x02014b50 )
    ( __zip_push_u16 cd 20 )  // version made by
    ( __zip_push_u16 cd 20 )  // version needed
    ( __zip_push_u16 cd 0 )  // flags
    ( __zip_push_u16 cd method )
    ( __zip_push_u16 cd 0 )  // dos time
    ( __zip_push_u16 cd ZIP_DOSDATE )
    ( __zip_push_u32 cd crc )
    ( __zip_push_u32 cd csize )
    ( __zip_push_u32 cd usize )
    ( __zip_push_u16 cd namelen )
    ( __zip_push_u16 cd 0 )  // extra
    ( __zip_push_u16 cd 0 )  // comment
    ( __zip_push_u16 cd 0 )  // disk start
    ( __zip_push_u16 cd 0 )  // internal attrs
    ( __zip_push_u32 cd 0 )  // external attrs
    ( __zip_push_u32 cd offset )
    ( bytes_extend_str cd name )
    ( nurl_poke . z ctl 0 + ( nurl_peek . z ctl 0 ) 1 )
    ^ @ !v ZipErr { T 0 }
}

@ zip_add Zip z s name ( Vec u ) data → !v ZipErr {
    : ?( Vec u ) comp ( __zip_deflate data )
    ^ ( __zip_add_entry z name data comp )
}

@ zip_add_stored Zip z s name ( Vec u ) data → !v ZipErr {
    ^ ( __zip_add_entry z name data @ ?( Vec u ) { F } )
}

// Append the central directory + end record; returns the archive and
// frees the builder.
@ zip_finish Zip z → ( Vec u ) {
    : ( Vec u ) out . z body
    : i cd_off ( vec_len [u] out )
    : i cd_len ( vec_len [u] . z central )
    : i count ( nurl_peek . z ctl 0 )
    : *u cp ( vec_data [u] . z central )
    : ~ i k 0
    ~ < k cd_len { ( vec_push [u] out . cp k ) = k + k 1 }
    ( __zip_push_u32 out 0x06054b50 )  // EOCD
    ( __zip_push_u16 out 0 )  // disk
    ( __zip_push_u16 out 0 )  // cd disk
    ( __zip_push_u16 out count )
    ( __zip_push_u16 out count )
    ( __zip_push_u32 out cd_len )
    ( __zip_push_u32 out cd_off )
    ( __zip_push_u16 out 0 )  // comment len
    ( vec_free [u] . z central )
    ( nurl_free . z ctl )
    ^ out
}

// ── reader ──────────────────────────────────────────────────────────
//
// ZipArchive: ctl slot 0 = entry count, slot 1 = entries ptr, slot 2 =
// source data ptr (borrowed), slot 3 = source len. Entries are a flat
// i64 array, 7 slots each:
//   0 name_off (into source)  1 name_len  2 method  3 csize
//   4 usize    5 local_hdr_off            6 crc

: ZipArchive { s ctl }

@ zip_count ZipArchive a → i { ^ ( nurl_peek . a ctl 0 ) }

@ __zip_entry ZipArchive a i idx i field → i {
    : s ep # s ( nurl_peek . a ctl 1 )
    ^ ( nurl_peek ep + * idx 7 field )
}

@ zip_open ( Vec u ) bytes → !ZipArchive ZipErr {
    : i n ( vec_len [u] bytes )
    ? < n 22 { ^ @ !ZipArchive ZipErr { F ZipBadArchive } } {}
    : *u p ( vec_data [u] bytes )
    // find EOCD: scan back from n-22 over the ≤64K comment window
    : ~ i eocd -1
    : ~ i scan - n 22
    : i lo ? > - n 65557 0 - n 65557 0
    ~ & >= scan lo < eocd 0 {
        ? & & & == # i . p scan 80 == # i . p + scan 1 75 == # i . p + scan 2 5 == # i . p + scan 3 6 {
            : i clen ( __zip_rd_u16 p + scan 20 )
            ? == + + scan 22 clen n { = eocd scan } {}
        } {}
        = scan - scan 1
    }
    ? < eocd 0 { ^ @ !ZipArchive ZipErr { F ZipBadArchive } } {}
    : i count ( __zip_rd_u16 p + eocd 10 )
    : i cd_len ( __zip_rd_u32 p + eocd 12 )
    : i cd_off ( __zip_rd_u32 p + eocd 16 )
    ? > + cd_off cd_len eocd { ^ @ !ZipArchive ZipErr { F ZipBadArchive } } {}
    // 0xFFFF entries / 0xFFFFFFFF offsets ⇒ zip64
    ? | == count 65535 == cd_off 4294967295 { ^ @ !ZipArchive ZipErr { F ZipUnsupported } } {}
    : s entries ( nurl_zalloc * count 56 )
    : ~ i pos cd_off
    : ~ i e 0
    : ~ b bad F
    ~ & < e count ! bad {
        ? | > + pos 46 n != ( __zip_rd_u32 p pos ) 0x02014b50 { = bad T } {
            : i method ( __zip_rd_u16 p + pos 10 )
            : i crc ( __zip_rd_u32 p + pos 16 )
            : i csize ( __zip_rd_u32 p + pos 20 )
            : i usize ( __zip_rd_u32 p + pos 24 )
            : i nlen ( __zip_rd_u16 p + pos 28 )
            : i xlen ( __zip_rd_u16 p + pos 30 )
            : i clen ( __zip_rd_u16 p + pos 32 )
            : i lho ( __zip_rd_u32 p + pos 42 )
            : i eoff * e 7
            ( nurl_poke entries + eoff 0 + pos 46 )  // name_off
            ( nurl_poke entries + eoff 1 nlen )
            ( nurl_poke entries + eoff 2 method )
            ( nurl_poke entries + eoff 3 csize )
            ( nurl_poke entries + eoff 4 usize )
            ( nurl_poke entries + eoff 5 lho )
            ( nurl_poke entries + eoff 6 crc )
            = pos + + + pos 46 nlen + xlen clen
            = e + e 1
        }
    }
    ? bad {
        ( nurl_free entries )
        ^ @ !ZipArchive ZipErr { F ZipBadArchive }
    } {}
    : s ctl ( nurl_zalloc 32 )
    ( nurl_poke ctl 0 count )
    ( nurl_poke ctl 1 # i entries )
    ( nurl_poke ctl 2 # i ( vec_data [u] bytes ) )
    ( nurl_poke ctl 3 n )
    ^ @ !ZipArchive ZipErr { T @ ZipArchive { ctl } }
}

@ zip_name_at ZipArchive a i idx → ?String {
    ? | < idx 0 >= idx ( zip_count a ) { ^ @ ?String { F } } {}
    : *u p # *u ( nurl_peek . a ctl 2 )
    : i off ( __zip_entry a idx 0 )
    : i len ( __zip_entry a idx 1 )
    ^ @ ?String { T ( string_from_bytes # *u + # i p off len ) }
}

@ zip_size_at ZipArchive a i idx → ?i {
    ? | < idx 0 >= idx ( zip_count a ) { ^ @ ?i { F } } {}
    ^ @ ?i { T ( __zip_entry a idx 4 ) }
}

@ zip_extract ZipArchive a i idx → !( Vec u ) ZipErr {
    ? | < idx 0 >= idx ( zip_count a ) { ^ @ !( Vec u ) ZipErr { F ZipNotFound } } {}
    : *u p # *u ( nurl_peek . a ctl 2 )
    : i n ( nurl_peek . a ctl 3 )
    : i method ( __zip_entry a idx 2 )
    : i csize ( __zip_entry a idx 3 )
    : i usize ( __zip_entry a idx 4 )
    : i lho ( __zip_entry a idx 5 )
    : i want_crc ( __zip_entry a idx 6 )
    // skip the LOCAL header (its name/extra lens can differ from CD's)
    ? | > + lho 30 n != ( __zip_rd_u32 p lho ) 0x04034b50 { ^ @ !( Vec u ) ZipErr { F ZipBadArchive } } {}
    : i lnlen ( __zip_rd_u16 p + lho 26 )
    : i lxlen ( __zip_rd_u16 p + lho 28 )
    : i doff + + + lho 30 lnlen lxlen
    ? > + doff csize n { ^ @ !( Vec u ) ZipErr { F ZipBadArchive } } {}
    : ~ ? ( Vec u ) got @ ?( Vec u ) { F }
    ? == method 0 {
        : ( Vec u ) out ( vec_with_cap [u] ? > usize 0 usize 1 )
        ( nurl_memcpy ( vec_data [u] out ) # *u + # i p doff csize )
        : b _ok ( vec_set_len [u] out csize )
        = got @ ?( Vec u ) { T out }
    } {
        ? == method 8 {
            = got ( __zip_inflate p doff csize usize )
        } { ^ @ !( Vec u ) ZipErr { F ZipUnsupported } }
    }
    ?? got {
        T out → {
            : i have_crc ( crc32 out )
            ? != have_crc want_crc {
                ( vec_free [u] out )
                ^ @ !( Vec u ) ZipErr { F ZipCrc }
            } {}
            ^ @ !( Vec u ) ZipErr { T out }
        }
        F → { ^ @ !( Vec u ) ZipErr { F ZipInflate } }
    }
}

@ zip_extract_name ZipArchive a s name → !( Vec u ) ZipErr {
    : i nlen ( nurl_str_len name )
    : *u p # *u ( nurl_peek . a ctl 2 )
    : i count ( zip_count a )
    : ~ i e 0
    ~ < e count {
        ? == ( __zip_entry a e 1 ) nlen {
            : i noff ( __zip_entry a e 0 )
            : ~ i k 0
            : ~ b eq T
            ~ & < k nlen eq {
                ? != # i . p + noff k ( nurl_str_get name k ) { = eq F } {}
                = k + k 1
            }
            ? eq { ^ ( zip_extract a e ) } {}
        } {}
        = e + e 1
    }
    ^ @ !( Vec u ) ZipErr { F ZipNotFound }
}

@ zip_close ZipArchive a → v {
    ( nurl_free # s ( nurl_peek . a ctl 1 ) )
    ( nurl_free . a ctl )
}
