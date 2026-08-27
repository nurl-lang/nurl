// nurlbox/archive.nu — tar, gzip, gunzip, zcat.
//
// Both formats are the shipped pure-NURL implementations —
// `stdlib/ext/tar.nu` and `stdlib/ext/compress.nu` over
// `stdlib/std/deflate.nu` — so an image carrying these applets links
// nothing beyond libc: no libz, no libarchive.
//
// Whole-archive: an archive is read into memory, transformed and
// written back. tar's own format is a stream and could be processed as
// one; this is the honest limit of the current implementation and the
// reason a multi-gigabyte tarball is not this tool's job yet.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/compress.nu`
$ `bx.nu`

// ── gzip / gunzip / zcat ──────────────────────────────────────────

@ __gz_name s path → String {
    : String out ( string_from path )
    ( string_push_str out `.gz` )
    ^ out
}

// `x.gz` → `x`, `x.tgz` → `x.tar`, anything else keeps its name.
@ __gz_strip s path → String {
    : i n ( nurl_str_len path )
    ? & > n 3 != 0 ( nurl_str_ends path `.gz` ) { ^ ( string_from ( nurl_str_slice path 0 - n 3 ) ) } {}
    ? & > n 4 != 0 ( nurl_str_ends path `.tgz` ) {
        : String out ( string_from ( nurl_str_slice path 0 - n 4 ) )
        ( string_push_str out `.tar` )
        ^ out
    } {}
    ? & > n 2 != 0 ( nurl_str_ends path `.z` ) { ^ ( string_from ( nurl_str_slice path 0 - n 2 ) ) } {}
    ^ ( string_from path )
}

@ ap_gzip ( Vec String ) argv → i {
    : s me ( bx_name )
    : BxOpts o ( bx_getopt argv 1 `cdfktnq123456789` `stdout=c,decompress=d,force=f,keep=k,test=t,quiet=q` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ b decompress | ( bx_has o `d` ) | ( bx_streq me `gunzip` ) ( bx_streq me `zcat` )
        : ~ b to_stdout | ( bx_has o `c` ) ( bx_streq me `zcat` )
        : b keep ( bx_has o `k` )
        : b test ( bx_has o `t` )
        ? test { = decompress T = to_stdout T } {}
        : i nops ( bx_operand_count o )
        ? == nops 0 { = to_stdout T } {}
        : ~ i i 0
        ~ < i ? > nops 0 nops 1 {
            : s p ? > nops 0 ( bx_operand o i ) `-`
            ? ( bx_is_stdin p ) { = to_stdout T } {}
            : ~ b ok T
            : ( Vec u ) data ( bx_slurp p ok )
            ? ok {
                : !( Vec u ) CompressErr r ? decompress ( gzip_decompress data ) ( gzip_compress data )
                ?? r {
                    F e → {
                        ( bx_err_at p ( compress_err_name e ) )
                        = rc 1
                    }
                    T outbytes → {
                        ? test {} {
                            ? to_stdout {
                                ( bx_write_bytes outbytes )
                            } {
                                : String target ? decompress ( __gz_strip p ) ( __gz_name p )
                                ?? ( write_file_bytes ( string_data target ) outbytes ) {
                                    T _ → {
                                        // The original goes, unless -k:
                                        // that is what makes `gzip x`
                                        // leave only `x.gz`.
                                        ? ! keep {
                                            ?? ( file_delete p ) { T _ → {} F _ → {} }
                                        } {}
                                    }
                                    F e2 → {
                                        ( bx_err_at ( string_data target ) ( bx_ioerr e2 ) )
                                        = rc 1
                                    }
                                }
                                ( string_free target )
                            }
                        }
                        ( vec_free [u] outbytes )
                    }
                }
            } { = rc 1 }
            ( vec_free [u] data )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── tar ───────────────────────────────────────────────────────────

// Walk `path` into `entries`, depth first, names relative to the tar's
// own root. Directories are emitted before their contents so an
// extractor that creates as it goes never meets a missing parent.
@ __tar_collect s path ( Vec TarEntry ) entries inout i rc → v {
    ?? ( fs_lstat path ) {
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            = rc 1
        }
        T st → {
            ? ( stat_is_dir st ) {
                : String dirname ( string_from path )
                ( string_push_char dirname 47 )
                ( vec_push [TarEntry] entries @ TarEntry {
                    dirname ( stat_mode_bits st ) 0 . st mtime 53 ( vec_new [u] )
                } )
                ?? ( dir_list path ) {
                    T names → {
                        ( sort_by [String] names \ String a String b → i { ^ ( cmp_string a b ) } )
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String sub ( path_join path ( bx_at names k ) )
                            ( __tar_collect ( string_data sub ) entries rc )
                            ( string_free sub )
                            = k + k 1
                        }
                        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    }
                    F e2 → {
                        ( bx_err_at path ( bx_ioerr e2 ) )
                        = rc 1
                    }
                }
            } {
                ? ( stat_is_symlink st ) {
                    // A symlink is stored as what it points at, because
                    // the stdlib's tar writer knows two type flags. Said
                    // out loud rather than silently storing the target's
                    // bytes under the link's name.
                    ( bx_err_at path `symlink stored as a regular file` )
                    ?? ( read_file_bytes path ) {
                        T data → {
                            ( vec_push [TarEntry] entries @ TarEntry {
                                ( string_from path ) ( stat_mode_bits st ) ( vec_len [u] data ) . st mtime 48 data
                            } )
                        }
                        F _ → {}
                    }
                } {
                    ?? ( read_file_bytes path ) {
                        T data → {
                            ( vec_push [TarEntry] entries @ TarEntry {
                                ( string_from path ) ( stat_mode_bits st ) ( vec_len [u] data ) . st mtime 48 data
                            } )
                        }
                        F e3 → {
                            ( bx_err_at path ( bx_ioerr e3 ) )
                            = rc 1
                        }
                    }
                }
            }
        }
    }
}

@ __tar_list ( Vec TarEntry ) entries b verbose → v {
    : i n ( vec_len [TarEntry] entries )
    : String out ( string_new )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [TarEntry] entries i ) {
            T e → {
                ? verbose {
                    : FileStat st @ FileStat {
                        | . e mode ? == . e typeflag 53 16384 32768
                        . e size . e mtime 0 0 0 1 0 0 0 0 0 0 0 0 0
                    }
                    : String modes ( stat_mode_string st )
                    ( string_push_bytes out # *u ( string_data modes ) ( string_len modes ) )
                    ( string_free modes )
                    ( string_push_str out ` 0/0 ` )
                    ( string_push_int out . e size )
                    ( string_push_char out 32 )
                } {}
                ( string_push_bytes out # *u ( string_data . e path ) ( string_len . e path ) )
                ( string_push_char out 10 )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( bx_write out )
    ( string_free out )
}

@ ap_tar ( Vec String ) argv → i {
    // `tar cf x.tar dir` — the leading bundle with no dash is the
    // historical spelling and still the common one.
    : ( Vec String ) av ( vec_new [String] )
    : i argn ( vec_len [String] argv )
    ( vec_push [String] av ( string_from ( bx_at argv 0 ) ) )
    : ~ i ai 1
    ? & > argn 1 != 45 ( nurl_str_get ( bx_at argv 1 ) 0 ) {
        : String dashed ( string_from `-` )
        ( string_push_str dashed ( bx_at argv 1 ) )
        ( vec_push [String] av dashed )
        = ai 2
    } {}
    ~ < ai argn {
        ( vec_push [String] av ( string_from ( bx_at argv ai ) ) )
        = ai + ai 1
    }
    : BxOpts o ( bx_getopt av 1 `cxtvf:C:zOkp` `create=c,extract=x,list=t,verbose=v,file=f,directory=C,gzip=z,to-stdout=O,keep-old-files=k` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b create ( bx_has o `c` )
        : b extract ( bx_has o `x` )
        : b list ( bx_has o `t` )
        : b verbose ( bx_has o `v` )
        : b gz ( bx_has o `z` )
        : s file ? ( bx_has o `f` ) ( bx_val o `f` ) `-`
        : s chdir ? ( bx_has o `C` ) ( bx_val o `C` ) ``
        ? ! | create | extract list {
            ( bx_err `you must specify one of -c, -x or -t` )
            = rc 1
        } {
            ? create {
                : ( Vec TarEntry ) entries ( vec_new [TarEntry] )
                : i nops ( bx_operand_count o )
                : ~ i i 0
                ~ < i nops {
                    ( __tar_collect ( bx_operand o i ) entries rc )
                    = i + i 1
                }
                ? verbose { ( __tar_list entries F ) } {}
                ?? ( tar_create entries ) {
                    T raw → {
                        : ~ b wrote F
                        ? gz {
                            ?? ( gzip_compress raw ) {
                                T z → {
                                    = wrote ( __tar_emit file z )
                                    ( vec_free [u] z )
                                }
                                F e → {
                                    ( bx_err ( compress_err_name e ) )
                                    = rc 1
                                }
                            }
                        } { = wrote ( __tar_emit file raw ) }
                        ? ! wrote { = rc 1 } {}
                        ( vec_free [u] raw )
                    }
                    F e2 → {
                        ( bx_err ( tar_err_name e2 ) )
                        = rc 1
                    }
                }
                ( tar_entries_free entries )
            } {
                : ~ b ok T
                : ( Vec u ) raw ( bx_slurp file ok )
                ? ! ok { = rc 1 } {
                    // A gzip member starts 1f 8b; `-z` is then a
                    // formality rather than a requirement, which is what
                    // every modern tar does.
                    : i n ( vec_len [u] raw )
                    : *u p ( vec_data [u] raw )
                    : b looks_gz & >= n 2 & == 31 & 255 # i . p 0 == 139 & 255 # i . p 1
                    : ( Vec u ) plain ( vec_new [u] )
                    : ~ b have T
                    ? | gz looks_gz {
                        ?? ( gzip_decompress raw ) {
                            T d → { ( vec_extend [u] plain d ) ( vec_free [u] d ) }
                            F e → {
                                ( bx_err ( compress_err_name e ) )
                                = rc 1
                                = have F
                            }
                        }
                    } { ( vec_extend [u] plain raw ) }
                    ? have {
                        ?? ( tar_parse plain ) {
                            F e2 → {
                                ( bx_err ( tar_err_name e2 ) )
                                = rc 1
                            }
                            T entries → {
                                ? list {
                                    ( __tar_list entries verbose )
                                } {
                                    ? verbose { ( __tar_list entries F ) } {}
                                    : s dest ? > ( nurl_str_len chdir ) 0 chdir `.`
                                    ?? ( tar_unpack plain dest ) {
                                        T _ → {}
                                        F e3 → {
                                            ( bx_err ( tar_err_name e3 ) )
                                            = rc 1
                                        }
                                    }
                                }
                                ( tar_entries_free entries )
                            }
                        }
                    } {}
                    ( vec_free [u] plain )
                }
                ( vec_free [u] raw )
            }
        }
    }
    ( bx_opts_free o )
    ( vec_free_with [String] av \ String x → v { ( string_free x ) } )
    ^ rc
}

@ __tar_emit s file ( Vec u ) data → b {
    ? ( bx_is_stdin file ) {
        ( bx_write_bytes data )
        ^ T
    } {}
    ?? ( write_file_bytes file data ) {
        T _ → { ^ T }
        F e → {
            ( bx_err_at file ( bx_ioerr e ) )
            ^ F
        }
    }
}
