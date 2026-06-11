// compress_gzip.nu — round-trip + wire-format checks for the gzip
// helpers in stdlib/ext/compress.nu (RFC 1952 file format via the
// runtime.c §22 bridge over libz's streaming API).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/compress.nu`

@ vec_eq_bytes ( Vec u ) a ( Vec u ) b → b {
    : i na ( vec_len [u] a )
    : i nb ( vec_len [u] b )
    ? != na nb { ^ F } {}
    : *u pa ( vec_data [u] a )
    : *u pb ( vec_data [u] b )
    : ~ i k 0
    ~ < k na {
        ? != # i . pa k # i . pb k { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ make_input → ( Vec u ) {
    : ( Vec u ) buf ( vec_with_cap [u] 1024 )
    : s sample `the quick brown fox jumps over the lazy dog. `
    : ~ i k 0
    ~ < k 16 {
        ( bytes_extend_str buf sample )
        = k + k 1
    }
    ^ buf
}

@ main → i {
    : ( Vec u ) input ( make_input )
    : i orig_len ( vec_len [u] input )

    // ── gzip round trip ────────────────────────────────────────────
    : !( Vec u ) CompressErr cz ( gzip_compress input )
    ?? cz {
        T comp → {
            : i clen ( vec_len [u] comp )
            // RFC 1952 §2.2: bytes 0..1 are the gzip magic (1f 8b);
            // byte 2 = compression method (8 = deflate).
            : *u cp ( vec_data [u] comp )
            : i m0 # i . cp 0
            : i m1 # i . cp 1
            : i m2 # i . cp 2
            ( nurl_print `gzip magic=` )
            ( nurl_print ( nurl_str_int m0 ) ) ( nurl_print `,` )
            ( nurl_print ( nurl_str_int m1 ) ) ( nurl_print `,` )
            ( nurl_print ( nurl_str_int m2 ) ) ( nurl_print `\n` )
            : !( Vec u ) CompressErr dz ( gzip_decompress comp )
            ?? dz {
                T decomp → {
                    : i dlen ( vec_len [u] decomp )
                    : b ok ( vec_eq_bytes input decomp )
                    ( nurl_print `gzip round_trip=` )
                    ( nurl_print ? ok `T` `F` )
                    ( nurl_print ` comp_len_gt_18=` )
                    ( nurl_print ? > clen 18 `T` `F` )
                    ( nurl_print ` decomp_len=` )
                    ( nurl_print ( nurl_str_int dlen ) )
                    ( nurl_print `\n` )
                    ( vec_free [u] decomp )
                }
                F e → {
                    ( nurl_print `gzip decompress failed: ` )
                    ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( vec_free [u] comp )
        }
        F e → {
            ( nurl_print `gzip compress failed: ` )
            ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
        }
    }

    // ── Level override (0 = store-only) ─────────────────────────────
    : !( Vec u ) CompressErr c0 ( gzip_compress_at input 0 )
    ?? c0 {
        T comp → {
            : !( Vec u ) CompressErr d0 ( gzip_decompress comp )
            ?? d0 {
                T decomp → {
                    : b ok ( vec_eq_bytes input decomp )
                    ( nurl_print `gzip lvl0 round_trip=` )
                    ( nurl_print ? ok `T` `F` ) ( nurl_print `\n` )
                    ( vec_free [u] decomp )
                }
                F _ → ( nurl_print `gzip lvl0 decompress err\n` )
            }
            ( vec_free [u] comp )
        }
        F _ → ( nurl_print `gzip lvl0 compress err\n` )
    }

    // ── Empty input passes through ──────────────────────────────────
    : ( Vec u ) empty ( vec_new [u] )
    : !( Vec u ) CompressErr ge ( gzip_compress empty )
    ?? ge {
        T e → {
            ( nurl_print `gzip empty ok len=` )
            ( nurl_print ( nurl_str_int ( vec_len [u] e ) ) )
            ( nurl_print `\n` )
            ( vec_free [u] e )
        }
        F _ → ( nurl_print `gzip empty err\n` )
    }
    ( vec_free [u] empty )

    // ── Auto-detect: gzip_decompress accepts a zlib-format stream ──
    // (windowBits=15+32 enables auto gzip/zlib detection in libz.)
    : !( Vec u ) CompressErr zc ( zlib_compress input )
    ?? zc {
        T comp → {
            : !( Vec u ) CompressErr dz ( gzip_decompress comp )
            ?? dz {
                T decomp → {
                    : b ok ( vec_eq_bytes input decomp )
                    ( nurl_print `gzip accepts zlib=` )
                    ( nurl_print ? ok `T` `F` ) ( nurl_print `\n` )
                    ( vec_free [u] decomp )
                }
                F _ → ( nurl_print `gzip rejected zlib\n` )
            }
            ( vec_free [u] comp )
        }
        F _ → ( nurl_print `zlib compress err\n` )
    }

    // ── Decompress garbage returns CompressData ────────────────────
    : ( Vec u ) bad ( vec_with_cap [u] 8 )
    ( vec_push [u] bad # u 1 )
    ( vec_push [u] bad # u 2 )
    ( vec_push [u] bad # u 3 )
    ( vec_push [u] bad # u 4 )
    : !( Vec u ) CompressErr dbz ( gzip_decompress bad )
    ?? dbz {
        T v → { ( nurl_print `gzip bad: unexpected ok\n` ) ( vec_free [u] v ) }
        F e → {
            ( nurl_print `gzip bad err=` )
            ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
        }
    }
    ( vec_free [u] bad )

    ( vec_free [u] input )
    ( nurl_print `orig_len=` )
    ( nurl_print ( nurl_str_int orig_len ) ) ( nurl_print `\n` )
    ^ 0
}
