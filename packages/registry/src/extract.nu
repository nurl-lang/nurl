// registry/extract.nu — read files out of a published .tar.gz in memory.
//
// Powers the package page (README.md render, [package].repository from
// nurl.toml) and the /files/<name>/<version>/<relpath> asset route
// (README-referenced images served straight from the tarball). Nothing
// here touches the filesystem — gunzip + tar_parse over bytes.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/toml.nu`

// Normalize a tarball member path for matching: strip a leading "./".
@ __rx_member_norm s path → String {
    : String out ( string_from path )
    ? ( string_starts_with out `./` ) {
        : String cut ( string_new )
        : i n ( nurl_str_len path )
        : ~ i k 2
        ~ < k n {
            ( string_push_char cut ( nurl_str_get path k ) )
            = k + k 1
        }
        ( string_free out )
        ^ cut
    } {}
    ^ out
}

// Case-insensitive ASCII equality of two C strings.
@ __rx_str_eq_ci s a s b → b {
    : i n ( nurl_str_len a )
    ? != n ( nurl_str_len b ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : ~ i ca ( nurl_str_get a k )
        : ~ i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Reject dotted / absolute / traversal segments; "" when unsafe, the
// normalized path otherwise. (Mirrors the Worker's normalizeRelPath.)
@ reg_relpath_norm s rel → String {
    : String raw ( string_from rel )
    : ( Vec String ) segs ( string_split raw `/` )
    ( string_free raw )
    : String out ( string_new )
    : i n ( vec_len [String] segs )
    : ~ i k 0
    : ~ b bad F
    : ~ b first T
    ~ < k n {
        : ?String so ( vec_get [String] segs k )
        ?? so {
            T seg → {
                : s sd ( string_data seg )
                : i sl ( nurl_str_len sd )
                ? == sl 0 { = bad T } {}  // "//" or leading "/"
                ? > sl 0 { ? == ( nurl_str_get sd 0 ) 46 { = bad T } {} } {}  // ".", "..", dotfiles
                ? ! bad {
                    ? ! first { ( string_push_char out 47 ) } {}
                    ( string_push_str out sd )
                    = first F
                } {}
                ( string_free seg )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free [String] segs )
    ? bad {
        ( string_free out )
        ^ ( string_new )
    } {}
    ^ out
}

// Extract one member (path match after "./"-normalization, exact) from a
// gzipped tarball. Empty Vec when absent or the archive is malformed.
@ reg_targz_member ( Vec u ) gz s relpath → ( Vec u ) {
    : ~ ( Vec u ) out ( vec_new [u] )
    : !( Vec u ) CompressErr dr ( gzip_decompress gz )
    ?? dr {
        F _ → ^ out
        T raw → {
            : !( Vec TarEntry ) TarErr tr ( tar_parse raw )
            ( vec_free [u] raw )
            ?? tr {
                F _ → ^ out
                T ents → {
                    : i n ( vec_len [TarEntry] ents )
                    : ~ i k 0
                    : ~ b found F
                    ~ < k n {
                        : ?TarEntry eo ( vec_get [TarEntry] ents k )
                        ?? eo {
                            T e → {
                                ? & ! found == . e typeflag 48 {
                                    : String norm ( __rx_member_norm ( string_data . e path ) )
                                    ? != 0 ( nurl_str_eq ( string_data norm ) relpath ) {
                                        ( vec_free [u] out )
                                        = out ( vec_clone [u] . e data )
                                        = found T
                                    } {}
                                    ( string_free norm )
                                } {}
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                    ( tar_entries_free ents )
                }
            }
        }
    }
    ^ out
}

// Root-level README.md (any case), as a String; "" when absent.
@ reg_targz_readme ( Vec u ) gz → String {
    : ~ String out ( string_new )
    : !( Vec u ) CompressErr dr ( gzip_decompress gz )
    ?? dr {
        F _ → ^ out
        T raw → {
            : !( Vec TarEntry ) TarErr tr ( tar_parse raw )
            ( vec_free [u] raw )
            ?? tr {
                F _ → ^ out
                T ents → {
                    : i n ( vec_len [TarEntry] ents )
                    : ~ i k 0
                    : ~ b found F
                    ~ < k n {
                        : ?TarEntry eo ( vec_get [TarEntry] ents k )
                        ?? eo {
                            T e → {
                                ? & ! found == . e typeflag 48 {
                                    : String norm ( __rx_member_norm ( string_data . e path ) )
                                    ? ( __rx_str_eq_ci ( string_data norm ) `readme.md` ) {
                                        ( string_free out )
                                        = out ( bytes_to_str . e data )
                                        = found T
                                    } {}
                                    ( string_free norm )
                                } {}
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                    ( tar_entries_free ents )
                }
            }
        }
    }
    ^ out
}

// [package].repository from the tarball's root nurl.toml; "" when absent.
@ reg_targz_repository ( Vec u ) gz → String {
    : ( Vec u ) manifest ( reg_targz_member gz `nurl.toml` )
    ? == ( vec_len [u] manifest ) 0 {
        ( vec_free [u] manifest )
        ^ ( string_new )
    } {}
    : String text ( bytes_to_str manifest )
    ( vec_free [u] manifest )
    : ~ String out ( string_new )
    ?? ( toml_parse ( string_data text ) ) {
        T root → {
            : ?TomlValue rv ( toml_get_path root `package.repository` )
            ?? rv {
                T repo → {
                    : ?String rs ( toml_as_str repo )
                    ?? rs {
                        T sv → {
                            ( string_free out )
                            = out sv
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( toml_value_free root )
        }
        F _ → {}
    }
    ( string_free text )
    ^ out
}
