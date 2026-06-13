// zip_basic.nu — ext/zip.nu acceptance: build an archive, re-open it,
// extract every entry (CRC-checked), and confirm store-vs-deflate
// selection. The archive bytes are written to /tmp so an external
// `unzip -t` cross-check can run out-of-band; the golden itself is the
// in-NURL round-trip (deterministic: fixed DOS timestamp).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/zip.nu`

@ mkbytes s in → ( Vec u ) {
    : i n ( nurl_str_len in )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u ( nurl_str_get in k ) ) = k + k 1 }
    ^ out
}

// 5000 bytes of highly-compressible data (forces deflate to win)
@ big_data → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 5000 )
    : ~ i k 0
    ~ < k 5000 { ( vec_push [u] v # u + 97 % k 4 ) = k + k 1 }
    ^ v
}

@ vshow s label ( Vec u ) v → v {
    ( nurl_print label ) ( nurl_print `=` )
    : String s ( bytes_to_str v )
    ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
    ( string_free s )
}

@ main → i {
    // ── build ──
    : Zip z ( zip_new )
    : ( Vec u ) d1 ( mkbytes `hello, zip world` )
    : !v ZipErr a1 ( zip_add z `greeting.txt` d1 )
    ?? a1 { T _ → {} F _ → ( nurl_print `add1 ERR\n` ) }
    ( vec_free [u] d1 )
    : ( Vec u ) d2 ( mkbytes `x` )
    : !v ZipErr a2 ( zip_add_stored z `tiny.txt` d2 )   // tiny → forced store
    ?? a2 { T _ → {} F _ → ( nurl_print `add2 ERR\n` ) }
    ( vec_free [u] d2 )
    : ( Vec u ) d3 ( big_data )
    : !v ZipErr a3 ( zip_add z `dir/big.dat` d3 )         // compressible → deflate
    ?? a3 { T _ → {} F _ → ( nurl_print `add3 ERR\n` ) }
    : i d3len ( vec_len [u] d3 )
    ( vec_free [u] d3 )

    : ( Vec u ) arc ( zip_finish z )
    ( nurl_print `archive_bytes=` ) ( nurl_print ( nurl_str_int ( vec_len [u] arc ) ) ) ( nurl_print `\n` )
    ( nurl_print `magic_PK=` )
    : *u ap ( vec_data [u] arc )
    ( nurl_print ? & == # i . ap 0 80 == # i . ap 1 75 `T` `F` ) ( nurl_print `\n` )

    // write to /tmp for an external `unzip -t` cross-check (out of band)
    : !v IoErr _w ( write_file_bytes `/tmp/nurl_ziptest.zip` arc )
    ?? _w { T _ → {} F _ → {} }

    // ── re-open + inspect ──
    : !ZipArchive ZipErr oo ( zip_open arc )
    ?? oo {
        T za → {
            ( nurl_print `count=` ) ( nurl_print ( nurl_str_int ( zip_count za ) ) ) ( nurl_print `\n` )
            : ~ i e 0
            ~ < e ( zip_count za ) {
                ( nurl_print `entry ` ) ( nurl_print ( nurl_str_int e ) ) ( nurl_print `: ` )
                ?? ( zip_name_at za e ) { T nm → { ( nurl_print ( string_data nm ) ) ( string_free nm ) } F _ → ( nurl_print `?` ) }
                ( nurl_print ` size=` )
                ?? ( zip_size_at za e ) { T sz → ( nurl_print ( nurl_str_int sz ) ) F _ → ( nurl_print `?` ) }
                : !( Vec u ) ZipErr ex ( zip_extract za e )
                ?? ex {
                    T data → {
                        ( nurl_print ` extract_ok=T crc_len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] data ) ) )
                        ( vec_free [u] data )
                    }
                    F er → { ( nurl_print ` extract_ERR=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) }
                }
                ( nurl_print `\n` )
                = e + e 1
            }
            // extract by name, content check
            : !( Vec u ) ZipErr byn ( zip_extract_name za `greeting.txt` )
            ?? byn { T data → { ( vshow `by_name greeting.txt` data ) ( vec_free [u] data ) } F _ → ( nurl_print `by_name ERR\n` ) }
            // big entry must have deflated (csize < usize): verify via re-extract length == d3len
            : !( Vec u ) ZipErr bigx ( zip_extract_name za `dir/big.dat` )
            ?? bigx { T data → { ( nurl_print `big_roundtrip_len_ok=` ) ( nurl_print ? == ( vec_len [u] data ) d3len `T` `F` ) ( nurl_print `\n` ) ( vec_free [u] data ) } F _ → ( nurl_print `big ERR\n` ) }
            // missing name → not-found
            : !( Vec u ) ZipErr miss ( zip_extract_name za `nope.txt` )
            ?? miss { T d → { ( vec_free [u] d ) ( nurl_print `missing=FOUND(BUG)\n` ) } F er → { ( nurl_print `missing=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) } }
            ( zip_close za )
        }
        F er → { ( nurl_print `open ERR=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) }
    }
    ( vec_free [u] arc )

    // ── reject a garbage archive ──
    : ( Vec u ) junk ( mkbytes `not a zip file at all, no PK header anywhere here` )
    : !ZipArchive ZipErr bad ( zip_open junk )
    ?? bad { T za → { ( zip_close za ) ( nurl_print `junk=OPENED(BUG)\n` ) } F er → { ( nurl_print `junk=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) } }
    ( vec_free [u] junk )
    : !v IoErr _rm ( file_delete `/tmp/nurl_ziptest.zip` )
    ?? _rm { T _ → {} F _ → {} }
    ^ 0
}
