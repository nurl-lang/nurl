// compress_basic.nu — round-trip + error coverage for the zlib + zstd
// bindings shipped in stdlib/ext/compress.nu.

$ `stdlib/core/string.nu`
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

@ print_outcome s tag b round_trip_ok i compressed_len i decompressed_len → v {
    ( nurl_print tag )
    ( nurl_print ` round_trip=` )
    ( nurl_print ? round_trip_ok `T` `F` )
    ( nurl_print ` comp_len=` )
    ( nurl_print ( nurl_str_int compressed_len ) )
    ( nurl_print ` decomp_len=` )
    ( nurl_print ( nurl_str_int decompressed_len ) )
    ( nurl_print `\n` )
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

    // ── zlib round trip ────────────────────────────────────────────
    : !( Vec u ) CompressErr cz ( zlib_compress input )
    ?? cz {
        T comp → {
            : i clen ( vec_len [u] comp )
            : !( Vec u ) CompressErr dz ( zlib_decompress comp )
            ?? dz {
                T decomp → {
                    : i dlen ( vec_len [u] decomp )
                    : b ok ( vec_eq_bytes input decomp )
                    ( print_outcome `zlib` ok clen dlen )
                    ( vec_free [u] decomp )
                }
                F e → {
                    ( nurl_print `zlib decompress failed: ` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( vec_free [u] comp )
        }
        F e → {
            ( nurl_print `zlib compress failed: ` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
        }
    }

    // ── zstd round trip ────────────────────────────────────────────
    : !( Vec u ) CompressErr cs ( zstd_compress input )
    ?? cs {
        T comp → {
            : i clen ( vec_len [u] comp )
            : !( Vec u ) CompressErr ds ( zstd_decompress comp )
            ?? ds {
                T decomp → {
                    : i dlen ( vec_len [u] decomp )
                    : b ok ( vec_eq_bytes input decomp )
                    ( print_outcome `zstd` ok clen dlen )
                    ( vec_free [u] decomp )
                }
                F e → {
                    ( nurl_print `zstd decompress failed: ` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( vec_free [u] comp )
        }
        F e → {
            ( nurl_print `zstd compress failed: ` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` )
        }
    }

    // ── Empty input passes through ─────────────────────────────────
    : ( Vec u ) empty ( vec_new [u] )
    : !( Vec u ) CompressErr ez ( zlib_compress empty )
    ?? ez {
        T e → { ( nurl_print `zlib empty ok len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] e ) ) ) ( nurl_print `\n` ) ( vec_free [u] e ) }
        F _ → ( nurl_print `zlib empty err\n` )
    }
    : !( Vec u ) CompressErr est ( zstd_compress empty )
    ?? est {
        T e → { ( nurl_print `zstd empty ok len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] e ) ) ) ( nurl_print `\n` ) ( vec_free [u] e ) }
        F _ → ( nurl_print `zstd empty err\n` )
    }
    ( vec_free [u] empty )

    // ── Decompress garbage returns CompressData ────────────────────
    : ( Vec u ) bad ( vec_with_cap [u] 8 )
    ( vec_push [u] bad # u 1 )
    ( vec_push [u] bad # u 2 )
    ( vec_push [u] bad # u 3 )
    ( vec_push [u] bad # u 4 )
    : !( Vec u ) CompressErr dbz ( zlib_decompress bad )
    ?? dbz {
        T v → { ( nurl_print `zlib bad: unexpected ok\n` ) ( vec_free [u] v ) }
        F e → { ( nurl_print `zlib bad err=` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` ) }
    }
    : !( Vec u ) CompressErr dbs ( zstd_decompress bad )
    ?? dbs {
        T v → { ( nurl_print `zstd bad: unexpected ok\n` ) ( vec_free [u] v ) }
        F e → { ( nurl_print `zstd bad err=` ) ( nurl_print ( compress_err_name e ) ) ( nurl_print `\n` ) }
    }
    ( vec_free [u] bad )

    ( vec_free [u] input )
    ( nurl_print `orig_len=` ) ( nurl_print ( nurl_str_int orig_len ) ) ( nurl_print `\n` )
    ^ 0
}
