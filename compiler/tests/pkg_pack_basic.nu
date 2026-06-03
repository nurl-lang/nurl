// pkg_pack_basic.nu — offline test for pkg_pack (package a directory tree).
//
// Builds a temp project with a nested source file, an excluded deps/ dir,
// and a dotfile, packs it, then gunzips + tar_parses the result and checks
// membership (dir_list order isn't deterministic, so we assert presence/
// absence, not order).

$ `stdlib/std/fs.nu`
$ `stdlib/ext/pkg_publish.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ ignore_io !v IoErr r → v { ?? r { T _ → {} F _ → {} } }

@ wfile s path s content → v { ( ignore_io ( write_file path content ) ) }

// Is `want` among the parsed entry paths?
@ has_entry ( Vec TarEntry ) ents s want → b {
    : i n ( vec_len [TarEntry] ents )
    : ~ i k 0
    ~ < k n {
        : ?TarEntry eo ( vec_get [TarEntry] ents k )
        ?? eo { T e → { ? != 0 ( nurl_str_eq ( string_data . e path ) want ) { ^ T } {} } F → {} }
        = k + k 1
    }
    ^ F
}

@ pb s label b v → v {
    ( nurl_print label )
    ? v { ( nurl_print `=T\n` ) } { ( nurl_print `=F\n` ) }
}

@ main → i {
    : s root `/tmp/nurl_pack_test`
    ( ignore_io ( dir_remove_all root ) )
    ( ignore_io ( dir_create_all `/tmp/nurl_pack_test/src` ) )
    ( ignore_io ( dir_create_all `/tmp/nurl_pack_test/deps/foo` ) )
    ( wfile `/tmp/nurl_pack_test/nurl.toml` `[package]
name = "demo"
version = "0.1.0"
` )
    ( wfile `/tmp/nurl_pack_test/src/lib.nu` `@ answer -> i { ^ 42 }
` )
    ( wfile `/tmp/nurl_pack_test/deps/foo/junk.nu` `should be excluded
` )
    ( wfile `/tmp/nurl_pack_test/.secret` `excluded dotfile
` )

    : !( Vec u ) PackErr pr ( pkg_pack root )
    ?? pr {
        F e → ( nurl_print ( pack_err_name e ) )
        T gz → {
            ( nurl_print `gz_nonempty=` ) ? > ( vec_len [u] gz ) 0 { ( nurl_print `T\n` ) } { ( nurl_print `F\n` ) }
            : !( Vec u ) CompressErr ur ( gzip_decompress gz )
            ?? ur {
                F e → ( nurl_print ( compress_err_name e ) )
                T raw → {
                    : !( Vec TarEntry ) TarErr tp ( tar_parse raw )
                    ?? tp {
                        F e → ( nurl_print ( tar_err_name e ) )
                        T ents → {
                            ( nurl_print `count=` ) ( nurl_print_int ( vec_len [TarEntry] ents ) ) ( nurl_print `\n` )
                            ( pb `has_nurl.toml` ( has_entry ents `nurl.toml` ) )
                            ( pb `has_src/lib.nu` ( has_entry ents `src/lib.nu` ) )
                            ( pb `excl_deps` ( has_entry ents `deps/foo/junk.nu` ) )
                            ( pb `excl_dotfile` ( has_entry ents `.secret` ) )
                            ( tar_entries_free ents )
                        }
                    }
                    ( vec_free [u] raw )
                }
            }
            ( vec_free [u] gz )
        }
    }
    ( ignore_io ( dir_remove_all root ) )
    ( nurl_print `done\n` )
    ^ 0
}
