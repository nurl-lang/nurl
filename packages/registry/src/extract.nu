// registry/extract.nu — read files out of a published .tar.gz in memory.
//
// Powers the package page (README.md render, [package].repository from
// nurl.toml) and the /files/<name>/<version>/<relpath> asset route
// (README-referenced images served straight from the tarball). Nothing
// here touches the filesystem — gunzip + tar_parse over bytes.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/nurldoc.nu`

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

// Every regular file in the tarball, in archive order, as a Json array
// [ { "path", "size" } ] for the files page. Empty array when the archive
// is malformed. tar_parse reconstructs USTAR prefix long paths already.
@ reg_targz_list ( Vec u ) gz → Json {
    : Json arr ( json_arr_new )
    : !( Vec u ) CompressErr dr ( gzip_decompress gz )
    ?? dr {
        F _ → ^ arr
        T raw → {
            : !( Vec TarEntry ) TarErr tr ( tar_parse raw )
            ( vec_free [u] raw )
            ?? tr {
                F _ → ^ arr
                T ents → {
                    : i n ( vec_len [TarEntry] ents )
                    : ~ i k 0
                    ~ < k n {
                        : ?TarEntry eo ( vec_get [TarEntry] ents k )
                        ?? eo {
                            T e → {
                                ? == . e typeflag 48 {
                                    : String norm ( __rx_member_norm ( string_data . e path ) )
                                    : Json row ( json_obj_new )
                                    : b _p ( json_obj_set row `path` ( json_str_lit ( string_data norm ) ) )
                                    : b _s ( json_obj_set row `size` ( json_int ( vec_len [u] . e data ) ) )
                                    : b _r ( json_arr_push arr row )
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
    ^ arr
}

// One [package] string scalar from the tarball's root nurl.toml, by its
// toml_get_path path (e.g. `package.repository`); "" when absent.
@ __rx_targz_pkg_str ( Vec u ) gz s path → String {
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
            : ?TomlValue rv ( toml_get_path root path )
            ?? rv {
                T tv → {
                    : ?String rs ( toml_as_str tv )
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

// [package].repository from the tarball's root nurl.toml; "" when absent.
@ reg_targz_repository ( Vec u ) gz → String {
    ^ ( __rx_targz_pkg_str gz `package.repository` )
}

// The README's first prose paragraph: heading lines and leading blanks
// skipped, following non-empty lines joined (newline → space). The
// pitch a README opens with is exactly what a search row wants.
@ __rx_readme_first_para String md → String {
    : String out ( string_with_cap 128 )
    : s raw ( string_data md )
    : i n ( string_len md )
    : ~ i k 0
    : ~ b started F
    : ~ b done F
    ~ & ! done < k n {
        // line bounds
        : i ls k
        : ~ i le k
        ~ & < le n != ( nurl_str_get raw le ) 10 { = le + le 1 }
        // first non-ws byte
        : ~ i sp ls
        ~ & < sp le | == ( nurl_str_get raw sp ) 32 == ( nurl_str_get raw sp ) 9 { = sp + sp 1 }
        : b blank == sp le
        : b heading & ! blank == ( nurl_str_get raw sp ) 35
        ? | blank heading {
            ? started { = done T } {}
        } {
            ? started { ( string_push_char out 32 ) } {}
            : ~ i j sp
            ~ < j le {
                : i c ( nurl_str_get raw j )
                // drop bold markers `**`
                ? & == c 42 & < + j 1 le == ( nurl_str_get raw + j 1 ) 42 { = j + j 2 } {
                    ( string_push_char out c )
                    = j + j 1
                }
            }
            = started T
        }
        = k ? < le n + le 1 le
    }
    ^ out
}

// [package].description, or — when the manifest omits one — the README's
// first paragraph. Capped at 500 bytes (search metadata, not a README) —
// mirrors the Worker's extractManifestDescription.
@ reg_targz_description ( Vec u ) gz → String {
    : ~ String raw ( __rx_targz_pkg_str gz `package.description` )
    ? == ( string_len raw ) 0 {
        : String md ( reg_targz_readme gz )
        ? > ( string_len md ) 0 {
            ( string_free raw )
            = raw ( __rx_readme_first_para md )
        } {}
        ( string_free md )
    } {}
    ? <= ( string_len raw ) 500 { ^ raw } {}
    : String cut ( string_substr raw 0 500 )
    ( string_free raw )
    ^ cut
}

// ── API documentation (nurldoc over the tarball's src/*.nu) ───────────

// The basename after the last '/' of a member path.
@ __rx_basename s path → String {
    : i n ( nurl_str_len path )
    : ~ i start 0
    : ~ i k 0
    ~ < k n { ? == ( nurl_str_get path k ) 47 { = start + k 1 } {} = k + k 1 }
    : String out ( string_with_cap - n start )
    = k start
    ~ < k n { ( string_push_char out ( nurl_str_get path k ) ) = k + k 1 }
    ^ out
}

// Rendered API docs (Markdown) for every src/*.nu in the tarball, in
// archive order, each run through nurldoc. "" when the archive is
// malformed or has no src modules.
@ reg_targz_api_md ( Vec u ) gz → String {
    : String md ( string_new )
    : !( Vec u ) CompressErr dr ( gzip_decompress gz )
    ?? dr {
        F _ → ^ md
        T raw → {
            : !( Vec TarEntry ) TarErr tr ( tar_parse raw )
            ( vec_free [u] raw )
            ?? tr {
                F _ → ^ md
                T ents → {
                    : i n ( vec_len [TarEntry] ents )
                    : ~ i k 0
                    ~ < k n {
                        : ?TarEntry eo ( vec_get [TarEntry] ents k )
                        ?? eo {
                            T e → {
                                ? == . e typeflag 48 {
                                    : String norm ( __rx_member_norm ( string_data . e path ) )
                                    ? & ( string_starts_with norm `src/` ) ( string_ends_with norm `.nu` ) {
                                        : String base ( __rx_basename ( string_data norm ) )
                                        : String content ( bytes_to_str . e data )
                                        : String one ( nurldoc_render ( string_data content ) ( string_data base ) )
                                        ? > ( string_len md ) 0 { ( string_push_str md `\n\n---\n\n` ) } {}
                                        ( string_push_str md ( string_data one ) )
                                        ( string_free one ) ( string_free content ) ( string_free base )
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
    ^ md
}
