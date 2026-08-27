// nurlbox/hash.nu — digests and encodings.
//
// md5sum / sha1sum / sha256sum / sha512sum / base64 / cksum / crc32.
//
// Every digest here is the shipped pure-NURL implementation from the
// stdlib — no OpenSSL, no libcrypto, nothing to link. The `-c` check
// mode reads the same format it writes, so `sha256sum * > SUMS` and
// `sha256sum -c SUMS` round-trip.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_md5.nu`
$ `stdlib/std/hash_sha1.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/deflate.nu`
$ `bx.nu`

: i HASH_MD5 0
: i HASH_SHA1 1
: i HASH_SHA256 2
: i HASH_SHA512 3

@ __hash_of i kind ( Vec u ) data → ( Vec u ) {
    ? == kind HASH_MD5 { ^ ( md5_pure data ) } {}
    ? == kind HASH_SHA1 { ^ ( sha1_pure data ) } {}
    ? == kind HASH_SHA256 { ^ ( sha256_pure data ) } {}
    ^ ( sha512_pure data )
}

@ __hex_of ( Vec u ) digest → String {
    : String out ( string_with_cap * 2 ( vec_len [u] digest ) )
    : i n ( vec_len [u] digest )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [u] digest i ) {
            T b → {
                : i v & 255 # i b
                ( string_push_char out ( nurl_str_get `0123456789abcdef` >> v 4 ) )
                ( string_push_char out ( nurl_str_get `0123456789abcdef` & v 15 ) )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ out
}

// The digest of one input, or None when it could not be read.
@ __hash_file i kind s path → ?String {
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp path ok )
    ? ! ok {
        ( vec_free [u] data )
        ^ @ ?String { F # String 0 }
    } {}
    : ( Vec u ) digest ( __hash_of kind data )
    : String hex ( __hex_of digest )
    ( vec_free [u] digest )
    ( vec_free [u] data )
    ^ @ ?String { T hex }
}

// `-c`: read `HEX  NAME` lines and re-hash each named file.
@ __hash_check i kind s listfile b quiet b status → i {
    ?? ( bx_reader listfile ) {
        F _ → { ^ 1 }
        T br → {
            : String line ( string_new )
            : ~ i rc 0
            : ~ i bad 0
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_into br line ) {
                    : i n ( string_len line )
                    ? > n 0 {
                        // `HEX  NAME` (two spaces) or `HEX *NAME` for the
                        // binary form; both are in the wild.
                        : ~ i sp 0
                        ~ & < sp n != ( string_get line sp ) 32 { = sp + sp 1 }
                        ? >= sp n {
                            ( bx_err_at listfile `improperly formatted checksum line` )
                            = rc 1
                        } {
                            : String want ( string_substr line 0 sp )
                            : ~ i nb sp
                            ~ & < nb n | == ( string_get line nb ) 32 == ( string_get line nb ) 42 { = nb + nb 1 }
                            : String name ( string_substr line nb - n nb )
                            ?? ( __hash_file kind ( string_data name ) ) {
                                T got → {
                                    : b okline ( string_eq got want )
                                    ? ! status {
                                        ? | ! quiet ! okline {
                                            ( nurl_print ( string_data name ) )
                                            ( nurl_print ? okline `: OK\n` `: FAILED\n` )
                                        } {}
                                    } {}
                                    ? ! okline { = bad + bad 1 = rc 1 } {}
                                    ( string_free got )
                                }
                                F _ → {
                                    = rc 1
                                    = bad + bad 1
                                }
                            }
                            ( string_free want )
                            ( string_free name )
                        }
                    } {}
                } { = more F }
            }
            ? & > bad 0 ! status {
                ( nurl_eprint ( bx_name ) )
                ( nurl_eprint `: WARNING: ` )
                ( nurl_eprint ( nurl_str_int bad ) )
                ( nurl_eprint ` of the computed checksums did NOT match\n` )
            } {}
            ( string_free line )
            ( bufreader_close br )
            ^ rc
        }
    }
}

@ bx_sum i kind ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `cbtsw` `check=c,binary=b,text=t,status=s,warn=w` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? ( bx_has o `c` ) {
            : ~ i i 0
            ~ < i ? > nops 0 nops 1 {
                : i one ( __hash_check kind ? > nops 0 ( bx_operand o i ) `-` F ( bx_has o `s` ) )
                ? != one 0 { = rc 1 } {}
                = i + i 1
            }
        } {
            : ~ i i 0
            ~ < i ? > nops 0 nops 1 {
                : s p ? > nops 0 ( bx_operand o i ) `-`
                ?? ( __hash_file kind p ) {
                    T hex → {
                        : String out ( string_new )
                        ( string_push_bytes out # *u ( string_data hex ) ( string_len hex ) )
                        ( string_push_str out `  ` )
                        ( string_push_str out p )
                        ( string_push_char out 10 )
                        ( bx_write out )
                        ( string_free out )
                        ( string_free hex )
                    }
                    F _ → { = rc 1 }
                }
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_md5sum ( Vec String ) argv → i { ^ ( bx_sum HASH_MD5 argv ) }

@ ap_sha1sum ( Vec String ) argv → i { ^ ( bx_sum HASH_SHA1 argv ) }

@ ap_sha256sum ( Vec String ) argv → i { ^ ( bx_sum HASH_SHA256 argv ) }

@ ap_sha512sum ( Vec String ) argv → i { ^ ( bx_sum HASH_SHA512 argv ) }

// ── base64 ────────────────────────────────────────────────────────

@ ap_base64 ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `dw:` `decode=d,wrap=w` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : s path ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        : ~ b ok T
        : ( Vec u ) data ( bx_slurp path ok )
        ? ! ok { = rc 1 } {
            ? ( bx_has o `d` ) {
                // Whitespace is not data: a wrapped encoding must decode.
                : String packed ( string_new )
                : i n ( vec_len [u] data )
                : ~ i i 0
                ~ < i n {
                    ?? ( vec_get [u] data i ) {
                        T b → {
                            : i c & 255 # i b
                            ? ! | == c 10 | == c 13 | == c 32 == c 9 { ( string_push_char packed c ) } {}
                        }
                        F _ → {}
                    }
                    = i + i 1
                }
                ?? ( b64_decode_vec ( string_data packed ) ) {
                    T raw → {
                        ( bx_write_bytes raw )
                        ( vec_free [u] raw )
                    }
                    F _ → {
                        ( bx_err `invalid input` )
                        = rc 1
                    }
                }
                ( string_free packed )
            } {
                : String enc ( b64_encode_vec data )
                : i width ? ( bx_has o `w` ) ( nurl_str_to_int ( bx_val o `w` ) ) 76
                : String out ( string_new )
                : i n ( string_len enc )
                ? <= width 0 {
                    ( string_push_bytes out # *u ( string_data enc ) n )
                    ( string_push_char out 10 )
                } {
                    : ~ i i 0
                    ~ < i n {
                        : i take ? < - n i width - n i width
                        ( string_push_bytes out # *u + # i ( string_data enc ) i take )
                        ( string_push_char out 10 )
                        = i + i take
                    }
                }
                ( bx_write out )
                ( string_free out )
                ( string_free enc )
            }
        }
        ( vec_free [u] data )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── cksum / crc32 ─────────────────────────────────────────────────

// POSIX cksum is NOT crc32: a different polynomial order, the length
// folded in at the end, and no final inversion of the same shape. It is
// its own algorithm and gets its own table.
@ __cksum_table → ( Vec i ) {
    : ( Vec i ) t ( vec_new [i] )
    : ~ i n 0
    ~ < n 256 {
        : ~ i c << n 24
        : ~ i k 0
        ~ < k 8 {
            = c ? != 0 & c 2147483648 & ^^ << c 1 79764919 4294967295 & << c 1 4294967295
            = k + k 1
        }
        ( vec_push [i] t & c 4294967295 )
        = n + n 1
    }
    ^ t
}

@ __cksum ( Vec u ) data → i {
    : ( Vec i ) tbl ( __cksum_table )
    : ~ i crc 0
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i i 0
    ~ < i n {
        : i b & 255 # i . p i
        : i idx & 255 ^^ >> crc 24 b
        : ~ i tv 0
        ?? ( vec_get [i] tbl idx ) { T x → { = tv x } F _ → {} }
        = crc & ^^ << crc 8 tv 4294967295
        = i + i 1
    }
    // The length is appended, low byte first, then the whole thing is
    // complemented — that trailing step is what makes cksum cksum.
    : ~ i len n
    ~ != len 0 {
        : i idx & 255 ^^ >> crc 24 & len 255
        : ~ i tv 0
        ?? ( vec_get [i] tbl idx ) { T x → { = tv x } F _ → {} }
        = crc & ^^ << crc 8 tv 4294967295
        = len >> len 8
    }
    ( vec_free [i] tbl )
    ^ & ~ crc 4294967295
}

@ ap_cksum ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : ~ i i 0
        ~ < i ? > nops 0 nops 1 {
            : s p ? > nops 0 ( bx_operand o i ) `-`
            : ~ b ok T
            : ( Vec u ) data ( bx_slurp p ok )
            ? ok {
                : String out ( string_new )
                ( string_push_int out ( __cksum data ) )
                ( string_push_char out 32 )
                ( string_push_int out ( vec_len [u] data ) )
                ? > nops 0 {
                    ( string_push_char out 32 )
                    ( string_push_str out p )
                } {}
                ( string_push_char out 10 )
                ( bx_write out )
                ( string_free out )
            } { = rc 1 }
            ( vec_free [u] data )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_crc32 ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : ~ i i 0
        ~ < i ? > nops 0 nops 1 {
            : s p ? > nops 0 ( bx_operand o i ) `-`
            : ~ b ok T
            : ( Vec u ) data ( bx_slurp p ok )
            ? ok {
                : String out ( string_new )
                // busybox prints crc32 as eight lowercase hex digits;
                // cksum prints its own checksum in decimal. Two tools,
                // two conventions, both long-standing.
                : i v ( crc32 data )
                : ~ i sh 28
                ~ >= sh 0 {
                    ( string_push_char out ( nurl_str_get `0123456789abcdef` & 15 >> v sh ) )
                    = sh - sh 4
                }
                ? > nops 0 {
                    ( string_push_char out 32 )
                    ( string_push_str out p )
                } {}
                ( string_push_char out 10 )
                ( bx_write out )
                ( string_free out )
            } { = rc 1 }
            ( vec_free [u] data )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}
