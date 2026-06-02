// tar_basic.nu — offline acceptance test for stdlib/ext/tar.nu.
//
// Coverage:
//   1. In-memory round-trip: create (file with embedded NUL + dir +
//      nested file) → tar_create → tar_parse; paths / sizes / data match.
//   2. gzip composition: gzip_compress ∘ tar_create round-trips back
//      through gzip_decompress ∘ tar_parse (the registry `.tar.gz` shape).
//   3. Header checksum tamper → TarBadChecksum.
//   4. Path-safety: an archive carrying `../evil` → TarUnsafePath on
//      unpack; nothing is written.
//   5. Happy-path unpack to a temp dir, then read the file back (binary,
//      embedded NUL preserved end-to-end through write_file_bytes).

$ `stdlib/ext/tar.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ println_i s prefix i v → v {
    ( nurl_print prefix )
    ( nurl_print_int v )
}

@ println_s s prefix s v → v {
    ( nurl_print prefix )
    ( nurl_print v )
    ( nurl_print `\n` )
}

// "HI\0J" — 4 bytes including an embedded NUL.
@ make_payload → ( Vec u ) {
    : ( Vec u ) d ( vec_new [u] )
    ( vec_push [u] d # u 72 )
    ( vec_push [u] d # u 73 )
    ( vec_push [u] d # u 0 )
    ( vec_push [u] d # u 74 )
    ^ d
}

@ main → i {
    // ── 1. in-memory round-trip ──────────────────────────────────
    ( nurl_print `── round-trip ──\n` )
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    ( vec_push [TarEntry] ents ( tar_entry_file `readme.txt` ( make_payload ) ) )
    ( vec_push [TarEntry] ents ( tar_entry_dir `src` ) )
    ( vec_push [TarEntry] ents ( tar_entry_file `src/lib.nu` ( make_payload ) ) )

    : !( Vec u ) TarErr cr ( tar_create ents )
    ?? cr {
        F e → ( println_s `create_err=` ( tar_err_name e ) )
        T arc → {
            ( println_i `archive_len=` ( vec_len [u] arc ) )
            ( nurl_print `\n` )
            : !( Vec TarEntry ) TarErr pr ( tar_parse arc )
            ?? pr {
                F e → ( println_s `parse_err=` ( tar_err_name e ) )
                T got → {
                    ( println_i `entry_count=` ( vec_len [TarEntry] got ) )
                    ( nurl_print `\n` )
                    : ?TarEntry e0 ( vec_get [TarEntry] got 0 )
                    ?? e0 {
                        T e → {
                            ( println_s `name0=` ( string_data . e path ) )
                            ( println_i `size0=` . e size )
                            ( nurl_print `\n` )
                            ( println_i `data0_len=` ( vec_len [u] . e data ) )
                            ( nurl_print `\n` )
                        }
                        F → {}
                    }
                    : ?TarEntry e2 ( vec_get [TarEntry] got 2 )
                    ?? e2 {
                        T e → ( println_s `name2=` ( string_data . e path ) )
                        F → {}
                    }
                    ( tar_entries_free got )
                }
            }

            // ── 2. gzip composition ──────────────────────────────
            ( nurl_print `── gzip ──\n` )
            : !( Vec u ) CompressErr gz ( gzip_compress arc )
            ?? gz {
                F e → ( println_s `gzip_err=` ( compress_err_name e ) )
                T gzbytes → {
                    : !( Vec u ) CompressErr uz ( gzip_decompress gzbytes )
                    ?? uz {
                        F e → ( println_s `gunzip_err=` ( compress_err_name e ) )
                        T raw → {
                            : !( Vec TarEntry ) TarErr pr2 ( tar_parse raw )
                            ?? pr2 {
                                F e → ( println_s `gz_parse_err=` ( tar_err_name e ) )
                                T got2 → {
                                    ( println_i `gz_entry_count=` ( vec_len [TarEntry] got2 ) )
                                    ( nurl_print `\n` )
                                    ( tar_entries_free got2 )
                                }
                            }
                            ( vec_free [u] raw )
                        }
                    }
                    ( vec_free [u] gzbytes )
                }
            }

            // ── 3. checksum tamper ───────────────────────────────
            ( nurl_print `── tamper ──\n` )
            : *u tp ( vec_data [u] arc )
            = . tp 0 # u 88    // corrupt the name byte; checksum no longer matches
            : !( Vec TarEntry ) TarErr pr3 ( tar_parse arc )
            ?? pr3 {
                F e → ( println_s `tamper=` ( tar_err_name e ) )
                T bad → { ( nurl_print `tamper=ACCEPTED(bug)\n` ) ( tar_entries_free bad ) }
            }
            ( vec_free [u] arc )
        }
    }
    ( tar_entries_free ents )

    // ── 4. path-safety: ../evil is rejected on unpack ────────────
    ( nurl_print `── unsafe path ──\n` )
    : ( Vec TarEntry ) evil ( vec_new [TarEntry] )
    ( vec_push [TarEntry] evil ( tar_entry_file `../evil.txt` ( make_payload ) ) )
    : !( Vec u ) TarErr ec ( tar_create evil )
    ?? ec {
        F e → ( println_s `evil_create_err=` ( tar_err_name e ) )
        T earc → {
            : !i TarErr ur ( tar_unpack earc `/tmp/nurl_tar_test_unsafe` )
            ?? ur {
                F e → ( println_s `unsafe=` ( tar_err_name e ) )
                T cnt → ( println_i `unsafe=ACCEPTED(bug) count=` cnt )
            }
            ( vec_free [u] earc )
        }
    }
    ( tar_entries_free evil )

    // ── 5. happy-path unpack + read back (binary, embedded NUL) ──
    ( nurl_print `── unpack ──\n` )
    : ( Vec TarEntry ) good ( vec_new [TarEntry] )
    ( vec_push [TarEntry] good ( tar_entry_dir `pkg` ) )
    ( vec_push [TarEntry] good ( tar_entry_file `pkg/data.bin` ( make_payload ) ) )
    : !( Vec u ) TarErr gc ( tar_create good )
    ?? gc {
        F e → ( println_s `good_create_err=` ( tar_err_name e ) )
        T garc → {
            : !v IoErr rm ( dir_remove_all `/tmp/nurl_tar_test` )
            ?? rm { T _ → {} F _ → {} }
            : !i TarErr up ( tar_unpack garc `/tmp/nurl_tar_test` )
            ?? up {
                F e → ( println_s `unpack_err=` ( tar_err_name e ) )
                T cnt → {
                    ( println_i `unpacked=` cnt )
                    ( nurl_print `\n` )
                    : !( Vec u ) IoErr rb ( read_file_bytes `/tmp/nurl_tar_test/pkg/data.bin` )
                    ?? rb {
                        F _ → ( nurl_print `readback=ERR\n` )
                        T back → {
                            ( println_i `readback_len=` ( vec_len [u] back ) )
                            ( nurl_print `\n` )
                            : *u bp ( vec_data [u] back )
                            ( println_i `readback_nul_at2=` # i . bp 2 )
                            ( nurl_print `\n` )
                            ( vec_free [u] back )
                        }
                    }
                }
            }
            : !v IoErr rm2 ( dir_remove_all `/tmp/nurl_tar_test` )
            ?? rm2 { T _ → {} F _ → {} }
            ( vec_free [u] garc )
        }
    }
    ( tar_entries_free good )
    ( nurl_print `done\n` )
    ^ 0
}
