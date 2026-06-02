// stdlib/ext/tar.nu — USTAR (POSIX.1-1988) tar reader + writer.
//
// Pure NURL. The format is a sequence of 512-byte blocks: each member is
// one header block followed by ceil(size/512) zero-padded data blocks;
// the archive ends with two all-zero blocks. This is the keystone for
// the package registry — a published package is a `.tar.gz`: compose
// `tar_create` with `gzip_compress` (stdlib/ext/compress.nu) to pack, and
// `gzip_decompress` + `tar_parse` / `tar_unpack` to fetch+install.
//
// Surface:
//
//   ( tar_entry_file path data )   → TarEntry      regular-file member
//   ( tar_entry_dir  path )        → TarEntry      directory member
//   ( tar_entry_free e )           → v
//   ( tar_entries_free entries )   → v             free a parsed Vec
//
//   ( tar_create entries )         → ! ( Vec u ) TarErr   entries → archive bytes
//   ( tar_parse  archive )         → ! ( Vec TarEntry ) TarErr   bytes → entries (in-memory)
//   ( tar_unpack archive dest )    → ! i TarErr     path-safe extract to disk (returns count)
//
// Security (this parser consumes UNTRUSTED archives from the registry):
//
//   * `tar_unpack` rejects any member path that is absolute (`/…`) or
//     contains a `..` component → TarUnsafePath. No path can escape
//     `dest`.
//   * Only regular files (typeflag '0'/NUL) and directories ('5') are
//     extracted. Symlinks / hardlinks / device nodes are refused
//     (TarUnsupported) so a malicious archive can't plant a link that
//     later redirects a write outside the tree.
//   * Every header's checksum is verified before its fields are trusted
//     (TarBadChecksum), and a member whose declared size runs past the
//     end of the archive is TarTruncated.
//
// v1 scope: member paths must fit the 100-byte USTAR `name` field
// (TarPathTooLong on write); the `prefix` field IS honoured on read, so
// archives produced by GNU/BSD tar with split long paths parse back to
// the joined path. uid/gid are written as 0; mode defaults to 0644
// (files) / 0755 (dirs) when the entry carries 0.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`

// ── Types ─────────────────────────────────────────────────────────────

: TarEntry {
    String path
    i mode
    i size
    i mtime
    i typeflag      // ASCII byte: 48 '0' = file, 53 '5' = dir
    ( Vec u ) data  // file contents; empty for a directory
}

: | TarErr {
    TarTruncated      // header or data block runs past the archive end
    TarBadHeader      // missing/!= "ustar" magic
    TarBadChecksum    // header checksum mismatch
    TarUnsafePath     // absolute path or `..` component on extract
    TarPathTooLong    // path does not fit the 100-byte USTAR name field
    TarUnsupported    // entry type is not a regular file or directory
    TarIoError        // filesystem failure during unpack
}

@ tar_err_name TarErr e → s {
    ^ ?? e {
        TarTruncated → `TarTruncated`
        TarBadHeader → `TarBadHeader`
        TarBadChecksum → `TarBadChecksum`
        TarUnsafePath → `TarUnsafePath`
        TarPathTooLong → `TarPathTooLong`
        TarUnsupported → `TarUnsupported`
        TarIoError → `TarIoError`
    }
}

// ── Entry constructors / lifecycle ────────────────────────────────────

@ tar_entry_file s path ( Vec u ) data → TarEntry {
    ^ @ TarEntry { ( string_from path ) 420 ( vec_len [u] data ) 0 48 data }
}

@ tar_entry_dir s path → TarEntry {
    ^ @ TarEntry { ( string_from path ) 493 0 0 53 ( vec_new [u] ) }
}

@ tar_entry_free TarEntry e → v {
    ( string_free . e path )
    ( vec_free [u] . e data )
}

@ tar_entries_free ( Vec TarEntry ) entries → v {
    : i n ( vec_len [TarEntry] entries )
    : ~ i k 0
    ~ < k n {
        : ?TarEntry eo ( vec_get [TarEntry] entries k )
        ?? eo { T e → ( tar_entry_free e ) F → {} }
        = k + k 1
    }
    ( vec_free [TarEntry] entries )
}

// ── Low-level byte helpers ────────────────────────────────────────────

// Append `n` zero bytes to `dst`.
@ __tar_zeros ( Vec u ) dst i n → v {
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] dst # u 0 )
        = k + k 1
    }
}

// Write up to `maxlen` bytes of `str` into the header at `off` (buffer is
// pre-zeroed, so a shorter string is implicitly NUL-padded).
@ __tar_put_str * u p i off s str i maxlen → v {
    : i n ( nurl_str_len str )
    : i lim ? < n maxlen n maxlen
    : ~ i k 0
    ~ < k lim {
        = . p + off k # u ( nurl_str_get str k )
        = k + k 1
    }
}

// Write `value` as a zero-padded octal number of exactly `ndigits` ASCII
// digits, low digit at off+ndigits-1. The field's terminator byte (NUL
// or space) is left as the pre-zeroed buffer holds.
@ __tar_put_octal * u p i off i value i ndigits → v {
    : ~ i v value
    : ~ i k - ndigits 1
    ~ >= k 0 {
        = . p + off k # u + 48 % v 8
        = v / v 8
        = k - k 1
    }
}

// Parse an octal field [off, off+len): skip leading spaces/NULs, then
// accumulate octal digits until the first non-digit.
@ __tar_read_octal * u p i off i len → i {
    : ~ i r 0
    : ~ i started 0
    : ~ i done 0
    : ~ i k 0
    ~ & == done 0 < k len {
        : i b # i . p + off k
        ? & >= b 48 <= b 55 {
            = r + * r 8 - b 48
            = started 1
        } {
            ? == started 1 { = done 1 } {}
        }
        = k + k 1
    }
    ^ r
}

// Read a NUL-terminated string field starting at absolute offset `pos`,
// at most `maxlen` bytes.
@ __tar_read_cstr * u p i pos i maxlen → String {
    : String out ( string_new )
    : ~ i k 0
    : ~ i done 0
    ~ & == done 0 < k maxlen {
        : i b # i . p + pos k
        ? == b 0 { = done 1 } {
            ( string_push_char out b )
            = k + k 1
        }
    }
    ^ out
}

// Reconstruct a member path: `name` (off 0, 100) joined under `prefix`
// (off 345, 155) with a '/' when prefix is non-empty (USTAR long-path).
@ __tar_read_path * u p i base → String {
    : String name ( __tar_read_cstr p + base 0 100 )
    : String prefix ( __tar_read_cstr p + base 345 155 )
    ? > ( string_len prefix ) 0 {
        : String full ( string_with_cap + + ( string_len prefix ) ( string_len name ) 2 )
        ( string_push_str full ( string_data prefix ) )
        ( string_push_char full 47 )
        ( string_push_str full ( string_data name ) )
        ( string_free name )
        ( string_free prefix )
        ^ full
    } {}
    ( string_free prefix )
    ^ name
}

// Copy `len` bytes from `p[off..off+len)` into a fresh owned Vec.
@ __tar_slice * u p i off i len → ( Vec u ) {
    : i cap ? > len 0 len 1
    : ( Vec u ) out ( vec_with_cap [u] cap )
    : ~ i k 0
    ~ < k len {
        ( vec_push [u] out . p + off k )
        = k + k 1
    }
    ^ out
}

@ __tar_is_zero_block * u p i base → b {
    : ~ i k 0
    ~ < k 512 {
        ? != # i . p + base k 0 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __tar_has_magic * u p i base → b {
    ^ & == # i . p + base 257 117 & == # i . p + base 258 115 & == # i . p + base 259 116 & == # i . p + base 260 97 == # i . p + base 261 114
}

// Verify the header checksum: sum of all 512 bytes with the 8 checksum
// bytes [148,156) counted as ASCII spaces, compared to the stored octal.
@ __tar_verify_chksum * u p i base → b {
    : i stored ( __tar_read_octal p + base 148 8 )
    : ~ i sum 0
    : ~ i k 0
    ~ < k 512 {
        ? & >= k 148 < k 156 {
            = sum + sum 32
        } {
            = sum + sum # i . p + base k
        }
        = k + k 1
    }
    ^ == sum stored
}

// ── Writer ────────────────────────────────────────────────────────────

// Build a 512-byte USTAR header block for `e`.
@ __tar_build_header TarEntry e → ( Vec u ) {
    : ( Vec u ) h ( vec_with_cap [u] 512 )
    ( __tar_zeros h 512 )
    : *u p ( vec_data [u] h )

    : i is_dir ? == . e typeflag 53 1 0
    : i mode ? > . e mode 0 . e mode ? != is_dir 0 493 420
    : i sz ? != is_dir 0 0 ( vec_len [u] . e data )

    ( __tar_put_str p 0 ( string_data . e path ) 100 )
    ( __tar_put_octal p 100 mode 7 )    // mode
    ( __tar_put_octal p 108 0 7 )       // uid
    ( __tar_put_octal p 116 0 7 )       // gid
    ( __tar_put_octal p 124 sz 11 )     // size
    ( __tar_put_octal p 136 . e mtime 11 )  // mtime
    = . p 156 # u ? != is_dir 0 53 48    // typeflag '5' / '0'
    ( __tar_put_str p 257 `ustar` 5 )   // magic (byte 262 stays NUL)
    = . p 263 # u 48                // version "00"
    = . p 264 # u 48

    // Checksum: chksum field as spaces, sum, then "%06o\0 ".
    : ~ i ci 0
    ~ < ci 8 {
        = . p + 148 ci # u 32
        = ci + ci 1
    }
    : ~ i sum 0
    : ~ i si 0
    ~ < si 512 {
        = sum + sum # i . p si
        = si + si 1
    }
    ( __tar_put_octal p 148 sum 6 )
    = . p 154 # u 0
    = . p 155 # u 32
    ^ h
}

@ tar_create ( Vec TarEntry ) entries → !( Vec u ) TarErr {
    : ( Vec u ) out ( vec_new [u] )
    : i n ( vec_len [TarEntry] entries )
    : ~ i i 0
    ~ < i n {
        : ?TarEntry eo ( vec_get [TarEntry] entries i )
        ?? eo {
            T e → {
                ? > ( string_len . e path ) 100 {
                    ( vec_free [u] out )
                    ^ @ !( Vec u ) TarErr { F # TarErr TarPathTooLong }
                } {}
                : ( Vec u ) hdr ( __tar_build_header e )
                ( bytes_extend_bytes out hdr )
                ( vec_free [u] hdr )
                : i is_dir ? == . e typeflag 53 1 0
                ? == is_dir 0 {
                    : i sz ( vec_len [u] . e data )
                    ( bytes_extend_bytes out . e data )
                    ( __tar_zeros out % - 512 % sz 512 512 )
                } {}
            }
            F → {}
        }
        = i + i 1
    }
    ( __tar_zeros out 1024 )    // two terminating zero blocks
    ^ @ !( Vec u ) TarErr { T out }
}

// ── Reader ────────────────────────────────────────────────────────────

@ tar_parse ( Vec u ) archive → !( Vec TarEntry ) TarErr {
    : ( Vec TarEntry ) out ( vec_new [TarEntry] )
    : *u p ( vec_data [u] archive )
    : i total ( vec_len [u] archive )
    : ~ i base 0
    : ~ i done 0
    ~ & == done 0 <= + base 512 total {
        ? ( __tar_is_zero_block p base ) {
            = done 1
        } {
            ? ! ( __tar_has_magic p base ) {
                ( tar_entries_free out )
                ^ @ !( Vec TarEntry ) TarErr { F # TarErr TarBadHeader }
            } {}
            ? ! ( __tar_verify_chksum p base ) {
                ( tar_entries_free out )
                ^ @ !( Vec TarEntry ) TarErr { F # TarErr TarBadChecksum }
            } {}
            : i size ( __tar_read_octal p + base 124 12 )
            : i dstart + base 512
            ? > + dstart size total {
                ( tar_entries_free out )
                ^ @ !( Vec TarEntry ) TarErr { F # TarErr TarTruncated }
            } {}
            : i mode ( __tar_read_octal p + base 100 8 )
            : i mtime ( __tar_read_octal p + base 136 12 )
            : i tflag # i . p + base 156
            : String path ( __tar_read_path p base )
            : ( Vec u ) data ( __tar_slice p dstart size )
            ( vec_push [TarEntry] out @ TarEntry { path mode size mtime tflag data } )
            : i blocks / + size 511 512
            = base + dstart * blocks 512
        }
    }
    ^ @ !( Vec TarEntry ) TarErr { T out }
}

// ── Path-safe extraction ──────────────────────────────────────────────

// True iff `path` is a relative path with no `..` component and no
// leading '/'. Member names from __tar_read_cstr never contain NUL.
@ __tar_path_safe String path → b {
    : i n ( string_len path )
    ? == n 0 { ^ F } {}
    : s d ( string_data path )
    ? == ( nurl_str_get d 0 ) 47 { ^ F } {}    // absolute
    : ~ i k 0
    : ~ i comp_start 0
    : ~ i bad 0
    ~ <= k n {
        : i c ? < k n ( nurl_str_get d k ) 47   // treat end-of-string as '/'
        ? == c 47 {
            ? == - k comp_start 2 {
                ? & == ( nurl_str_get d comp_start ) 46 == ( nurl_str_get d + comp_start 1 ) 46 {
                    = bad 1
                } {}
            } {}
            = comp_start + k 1
        } {}
        = k + k 1
    }
    ^ == bad 0
}

// Directory portion of `full` (everything before the last '/'), or "."
// when there is no separator.
@ __tar_parent_dir String full → String {
    : s d ( string_data full )
    : i n ( string_len full )
    : ~ i last -1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get d k ) 47 { = last k } {}
        = k + k 1
    }
    ? < last 0 { ^ ( string_from `.` ) } {}
    : String out ( string_with_cap + last 1 )
    : ~ i j 0
    ~ < j last {
        ( string_push_char out ( nurl_str_get d j ) )
        = j + j 1
    }
    ^ out
}

@ __tar_join s dir String rel → String {
    : String out ( string_with_cap + + ( nurl_str_len dir ) ( string_len rel ) 2 )
    ( string_push_str out dir )
    ( string_push_char out 47 )
    ( string_push_str out ( string_data rel ) )
    ^ out
}

// Extract `archive` under `dest`. Returns the number of members written.
// Rejects unsafe paths and non-file/dir members (see the security note
// in the module header).
@ tar_unpack ( Vec u ) archive s dest → !i TarErr {
    : !( Vec TarEntry ) TarErr pr ( tar_parse archive )
    ?? pr {
        F e → { ^ @ !i TarErr { F e } }
        T entries → {
            : i n ( vec_len [TarEntry] entries )
            : ~ i count 0
            : ~ i fail 0          // 0 = ok; otherwise set + carry the variant in `ferr`
            : ~ TarErr ferr TarIoError
            : ~ i k 0
            ~ & == fail 0 < k n {
                : ?TarEntry eo ( vec_get [TarEntry] entries k )
                ?? eo {
                    F → {}
                    T e → {
                        ? ! ( __tar_path_safe . e path ) {
                            = fail 1
                            = ferr TarUnsafePath
                        } {
                            : i tflag . e typeflag
                            ? == tflag 53 {
                                : String full ( __tar_join dest . e path )
                                : !v IoErr dr ( dir_create_all ( string_data full ) )
                                ?? dr { T _ → { = count + count 1 } F _ → { = fail 1 = ferr TarIoError } }
                                ( string_free full )
                            } {
                                ? | == tflag 48 == tflag 0 {
                                    : String full ( __tar_join dest . e path )
                                    : String parent ( __tar_parent_dir full )
                                    : !v IoErr pdr ( dir_create_all ( string_data parent ) )
                                    ?? pdr {
                                        T _ → {
                                            : !v IoErr wr ( write_file_bytes ( string_data full ) . e data )
                                            ?? wr { T _ → { = count + count 1 } F _ → { = fail 1 = ferr TarIoError } }
                                        }
                                        F _ → { = fail 1 = ferr TarIoError }
                                    }
                                    ( string_free parent )
                                    ( string_free full )
                                } {
                                    = fail 1
                                    = ferr TarUnsupported
                                }
                            }
                        }
                    }
                }
                = k + k 1
            }
            ( tar_entries_free entries )
            ? != fail 0 {
                ^ @ !i TarErr { F ferr }
            } {}
            ^ @ !i TarErr { T count }
        }
    }
}
