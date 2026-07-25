// zip64_read.nu — ext/zip.nu reads a ZIP64 central directory.
//
// The writer still refuses to emit zip64, so the fixture is a genuine
// zip64 archive embedded as hex: both entries have their central-record
// csize / usize / local-header-offset saturated to 0xFFFFFFFF with the
// real 64-bit values in a 0x0001 extra, and the EOCD carries the
// 0xFFFF / 0xFFFFFFFF markers that send a reader to the EOCD64 record
// via the locator. (Verified independently: Python's zipfile opens and
// checksums this same byte string.)
//
// Also covers the zero-copy path — zip_data_off must address stored
// bytes in place, which is what makes an mmap-backed multi-GB archive
// readable without loading it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/zip.nu`

@ z64_hex → String {
    : String s ( string_new )
    ( string_push_str s `504b03042d000000000000002100acba0af80b0000000b00000005000000612e74787468656c6c6f207a69703634504b` )
    ( string_push_str s `03042d0000000000000021008cce0e104000000040000000090000006469722f622e62696e000102030405060708090a` )
    ( string_push_str s `0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a` )
    ( string_push_str s `3b3c3d3e3f504b01022d002d000000000000002100acba0af8ffffffffffffffff05001c0000000000000000000000ff` )
    ( string_push_str s `ffffff612e747874010018000b000000000000000b000000000000000000000000000000504b01022d002d0000000000` )
    ( string_push_str s `000021008cce0e10ffffffffffffffff09001c0000000000000000000000ffffffff6469722f622e62696e0100180040` )
    ( string_push_str s `0000000000000040000000000000002e00000000000000504b06062c000000000000002d002d00000000000000000002` )
    ( string_push_str s `000000000000000200000000000000a2000000000000009500000000000000504b060700000000370100000000000001` )
    ( string_push_str s `000000504b050600000000ffffffffffffffffffffffff0000` )
    ^ s
}

@ show_entry ZipArchive za i e → v {
    ( nurl_print `entry ` ) ( nurl_print ( nurl_str_int e ) ) ( nurl_print `: ` )
    ?? ( zip_name_at za e ) { T nm → { ( nurl_print ( string_data nm ) ) ( string_free nm ) } F _ → ( nurl_print `?` ) }
    ( nurl_print ` size=` )
    ?? ( zip_size_at za e ) { T sz → ( nurl_print ( nurl_str_int sz ) ) F _ → ( nurl_print `?` ) }
    ( nurl_print ` csize=` )
    ?? ( zip_csize_at za e ) { T sz → ( nurl_print ( nurl_str_int sz ) ) F _ → ( nurl_print `?` ) }
    ( nurl_print ` method=` )
    ?? ( zip_method_at za e ) { T m → ( nurl_print ( nurl_str_int m ) ) F _ → ( nurl_print `?` ) }
    ( nurl_print `\n` )
}

@ main → i {
    : String hex ( z64_hex )
    : !( Vec u ) ParseErr hb ( bytes_from_hex ( string_data hex ) )
    ( string_free hex )
    : ( Vec u ) arc ?? hb { T v → v F _ → ( vec_new [u] ) }
    ( nurl_print `arc_len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] arc ) ) ) ( nurl_print `\n` )

    : !ZipArchive ZipErr oo ( zip_open arc )
    ?? oo {
        T za → {
            ( nurl_print `count=` ) ( nurl_print ( nurl_str_int ( zip_count za ) ) ) ( nurl_print `\n` )
            : ~ i e 0
            ~ < e ( zip_count za ) { ( show_entry za e ) = e + e 1 }

            // crc-checked extraction through the zip64 offsets
            : !( Vec u ) ZipErr x1 ( zip_extract_name za `a.txt` )
            ?? x1 {
                T d → {
                    : String s ( bytes_to_str d )
                    ( nurl_print `a.txt=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
                    ( string_free s ) ( vec_free [u] d )
                }
                F er → { ( nurl_print `a.txt ERR=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) }
            }
            : !( Vec u ) ZipErr x2 ( zip_extract_name za `dir/b.bin` )
            ?? x2 {
                T d → {
                    ( nurl_print `b.bin_len=` ) ( nurl_print ( nurl_str_int ( vec_len [u] d ) ) )
                    : *u dp ( vec_data [u] d )
                    ( nurl_print ` b0=` ) ( nurl_print ( nurl_str_int # i . dp 0 ) )
                    ( nurl_print ` b63=` ) ( nurl_print ( nurl_str_int # i . dp 63 ) )
                    ( nurl_print `\n` )
                    ( vec_free [u] d )
                }
                F er → { ( nurl_print `b.bin ERR=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) }
            }

            // zero-copy: read the stored bytes straight out of the source
            : i idx ( zip_find za `a.txt` )
            ( nurl_print `find_a=` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            : i doff ( zip_data_off za idx )
            : *u ap ( vec_data [u] arc )
            ( nurl_print `inplace=` )
            : ~ i k 0
            ~ < k 11 { : String ch ( string_new ) ( string_push_char ch # i . ap + doff k ) ( nurl_print ( string_data ch ) ) ( string_free ch ) = k + k 1 }
            ( nurl_print `\n` )
            ( nurl_print `find_missing=` ) ( nurl_print ( nurl_str_int ( zip_find za `nope` ) ) ) ( nurl_print `\n` )
            ( zip_close za )
        }
        F er → { ( nurl_print `open ERR=` ) ( nurl_print ( zip_err_name # ZipErr er ) ) ( nurl_print `\n` ) }
    }
    ( vec_free [u] arc )
    ^ 0
}
