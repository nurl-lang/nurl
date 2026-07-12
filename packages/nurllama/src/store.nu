// packages/nurllama/src/store.nu — the local model store (~/.nurllama).
//
// Content-addressed, cas-shaped, but streaming end to end — a blob is
// never fully resident:
//
//   <root>/blobs/sha256-<64hex>     the model files, named by content
//   <root>/manifests/<name>         one small JSON per model name
//
// A manifest records { name, url, digest, size } — the name is the
// user-facing handle (`nurllama run <name>`), the digest is the proof.
// Two names may point at the same blob (dedup by content); `rm` only
// deletes a blob once no manifest references it. `verify` re-hashes
// the blob through the incremental sha256 and refuses drift.
//
//   ( nl_store_root )                 → String   $NURLLAMA_HOME | ~/.nurllama
//   ( nl_resolve root nameOrPath )    → ?String  path to a model file
//   ( nl_store_add root name url hex size ) → !v String
//   ( nl_store_list root )            → v        prints the table
//   ( nl_store_rm root name )         → !v String
//   ( nl_store_verify root name )     → !v String
//   ( nl_blob_path root hex ) ( nl_manifest_path root name )
//   ( nl_hash_file path )             → !String String  streaming sha256 hex

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`

@ nl_store_root → String {
    : ?String ov ( env_get `NURLLAMA_HOME` )
    ?? ov {
        T v → { ^ v }
        F → {}
    }
    : String home ( env_var_or `HOME` `.` )
    : String r ( path_join ( string_data home ) `.nurllama` )
    ( string_free home )
    ^ r
}

// Manifest names live on the filesystem: keep [A-Za-z0-9._-], map the
// rest (slashes of repo-style names included) to '_'.
@ __nl_safe_name s name → String {
    : String out ( string_new )
    : i n ( nurl_str_len name )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get name k )
        : b okc | | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122 | | == c 46 == c 95 == c 45
        ( string_push_char out ? okc c 95 )
        = k + k 1
    }
    ^ out
}

@ nl_blob_path String root s hex → String {
    : String bdir ( path_join ( string_data root ) `blobs` )
    : String nm ( string_from `sha256-` )
    ( string_push_str nm hex )
    : String p ( path_join ( string_data bdir ) ( string_data nm ) )
    ( string_free bdir )
    ( string_free nm )
    ^ p
}

@ nl_manifest_path String root s name → String {
    : String mdir ( path_join ( string_data root ) `manifests` )
    : String sn ( __nl_safe_name name )
    : String p ( path_join ( string_data mdir ) ( string_data sn ) )
    ( string_free mdir )
    ( string_free sn )
    ^ p
}

@ nl_store_init String root → !v String {
    : String b ( path_join ( string_data root ) `blobs` )
    : String m ( path_join ( string_data root ) `manifests` )
    : !v IoErr r1 ( dir_create_all ( string_data b ) )
    : !v IoErr r2 ( dir_create_all ( string_data m ) )
    ( string_free b )
    ( string_free m )
    : ~ b ok T
    ?? r1 { T _ → {} F _ → { = ok F } }
    ?? r2 { T _ → {} F _ → { = ok F } }
    ? ok { ^ @ !v String { T 0 } } {}
    : String msg ( string_from `nurllama: cannot create the store at ` )
    ( string_push_str msg ( string_data root ) )
    ^ @ !v String { F msg }
}

// Streaming sha256 of a file — constant memory whatever the size.
@ nl_hash_file s path → !String String {
    : !File IoErr fr ( file_open path )
    ?? fr {
        T f → {
            : *Sha256 h ( sha256_init )
            : ~ b more T
            ~ more {
                : !( Vec u ) IoErr cr ( file_read_chunk f 1048576 )
                ?? cr {
                    T piece → {
                        ? == ( vec_len [u] piece ) 0 { = more F } {
                            ( sha256_update h piece )
                        }
                        ( vec_free [u] piece )
                    }
                    F _ → { = more F }
                }
            }
            ( file_close f )
            : ( Vec u ) dg ( sha256_final h )
            : String hex ( bytes_to_hex dg )
            ( vec_free [u] dg )
            ^ @ !String String { T hex }
        }
        F _ → {
            : String msg ( string_from `nurllama: cannot open ` )
            ( string_push_str msg path )
            ^ @ !String String { F msg }
        }
    }
}

@ nl_store_add String root s name s url s hex i size → !v String {
    : Json j ( json_obj_new )
    : b _s1 ( json_obj_set j `name` ( json_str_lit name ) )
    : b _s2 ( json_obj_set j `url` ( json_str_lit url ) )
    : String dg ( string_from `sha256:` )
    ( string_push_str dg hex )
    : b _s3 ( json_obj_set j `digest` ( json_str_lit ( string_data dg ) ) )
    ( string_free dg )
    : b _s4 ( json_obj_set j `size` ( json_int size ) )
    : b _s5 ( json_obj_set j `format` ( json_str_lit `gguf` ) )
    : String txt ( json_stringify j )
    ( json_free j )
    : String mp ( nl_manifest_path root name )
    : !v IoErr wr ( write_file ( string_data mp ) ( string_data txt ) )
    ( string_free mp )
    ( string_free txt )
    ?? wr {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `nurllama: cannot write the manifest` ) } }
    }
}

// Manifest digest field → bare hex ("" when missing/malformed).
@ __nl_manifest_hex s mpath → String {
    : !String IoErr rr ( read_file mpath )
    ?? rr {
        T txt → {
            : ~ String hex ( string_new )
            : !Json JsonError pj ( json_parse ( string_data txt ) )
            ?? pj {
                T j → {
                    // json_obj_get returns a BORROW — never freed here
                    ?? ( json_obj_get j `digest` ) {
                        T dj → {
                            : s d ( json_str_data dj )
                            ? & != ( nurl_str_starts d `sha256:` ) 0 == ( nurl_str_len d ) 71 {
                                : ~ i k 7
                                ~ < k 71 {
                                    ( string_push_char hex ( nurl_str_get d k ) )
                                    = k + k 1
                                }
                            } {}
                        }
                        F → {}
                    }
                    ( json_free j )
                }
                F _ → {}
            }
            ( string_free txt )
            ^ hex
        }
        F _ → { ^ ( string_new ) }
    }
}

// Resolve a model argument: an existing file path wins; otherwise the
// store's manifest name → blob path. None = unknown.
@ nl_resolve String root s arg → ?String {
    ? ( file_exists arg ) { ^ @ ?String { T ( string_from arg ) } } {}
    : String mp ( nl_manifest_path root arg )
    : String hex ( __nl_manifest_hex ( string_data mp ) )
    ( string_free mp )
    ? == ( string_len hex ) 64 {} {
        ( string_free hex )
        ^ @ ?String { F }
    }
    : String bp ( nl_blob_path root ( string_data hex ) )
    ( string_free hex )
    ? ( file_exists ( string_data bp ) ) { ^ @ ?String { T bp } } {}
    ( string_free bp )
    ^ @ ?String { F }
}

@ nl_store_list String root → v {
    : String mdir ( path_join ( string_data root ) `manifests` )
    : !( Vec String ) IoErr lr ( dir_list ( string_data mdir ) )
    ?? lr {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String mp ( path_join ( string_data mdir ) ( string_data nm ) )
                        : String hex ( __nl_manifest_hex ( string_data mp ) )
                        : ~ i bsz -1
                        ? == ( string_len hex ) 64 {
                            : String bp ( nl_blob_path root ( string_data hex ) )
                            ?? ( file_size ( string_data bp ) ) {
                                T sz → { = bsz sz }
                                F _ → {}
                            }
                            ( string_free bp )
                        } {}
                        : String ln ( string_from ( string_data nm ) )
                        : ~ i pad - 32 ( string_len ln )
                        ~ > pad 0 {
                            ( string_push_char ln 32 )
                            = pad - pad 1
                        }
                        ? >= bsz 0 {
                            : String hs ( progress_human bsz )
                            ( string_push_str ln ( string_data hs ) )
                            ( string_free hs )
                            ( string_push_str ln `  sha256:` )
                            : String short ( string_substr hex 0 12 )
                            ( string_push_str ln ( string_data short ) )
                            ( string_free short )
                        } {
                            ( string_push_str ln `MISSING BLOB` )
                        }
                        ( nurl_print ( string_data ln ) )
                        ( nurl_print `\n` )
                        ( string_free ln )
                        ( string_free hex )
                        ( string_free mp )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ( string_free mdir )
}

// True when any OTHER manifest still references blob `hex`.
@ __nl_blob_shared String root s hex s except_name → b {
    : String mdir ( path_join ( string_data root ) `manifests` )
    : String keep ( __nl_safe_name except_name )
    : ~ b shared F
    : !( Vec String ) IoErr lr ( dir_list ( string_data mdir ) )
    ?? lr {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( string_eq nm keep ) {} {
                            : String mp ( path_join ( string_data mdir ) ( string_data nm ) )
                            : String ohex ( __nl_manifest_hex ( string_data mp ) )
                            ? ( nurl_str_eq ( string_data ohex ) hex ) { = shared T } {}
                            ( string_free ohex )
                            ( string_free mp )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ( string_free keep )
    ( string_free mdir )
    ^ shared
}

@ nl_store_rm String root s name → !v String {
    : String mp ( nl_manifest_path root name )
    ? ( file_exists ( string_data mp ) ) {} {
        ( string_free mp )
        ^ @ !v String { F ( string_from `nurllama: no such model in the store` ) }
    }
    : String hex ( __nl_manifest_hex ( string_data mp ) )
    : !v IoErr dr ( file_delete ( string_data mp ) )
    ( string_free mp )
    ?? dr {
        T _ → {}
        F _ → {
            ( string_free hex )
            ^ @ !v String { F ( string_from `nurllama: cannot remove the manifest` ) }
        }
    }
    // drop the blob only when no other name still points at it
    ? == ( string_len hex ) 64 {
        ? ( __nl_blob_shared root ( string_data hex ) name ) {} {
            : String bp ( nl_blob_path root ( string_data hex ) )
            ( file_delete ( string_data bp ) )
            ( string_free bp )
        }
    } {}
    ( string_free hex )
    ^ @ !v String { T 0 }
}

// Re-hash the blob and compare with the manifest digest — the store's
// integrity loop (mirrors cas_get's refuse-on-mismatch, streaming).
@ nl_store_verify String root s name → !v String {
    : String mp ( nl_manifest_path root name )
    : String hex ( __nl_manifest_hex ( string_data mp ) )
    ( string_free mp )
    ? == ( string_len hex ) 64 {} {
        ( string_free hex )
        ^ @ !v String { F ( string_from `nurllama: no such model (or a malformed manifest)` ) }
    }
    : String bp ( nl_blob_path root ( string_data hex ) )
    : !String String hr ( nl_hash_file ( string_data bp ) )
    ( string_free bp )
    ?? hr {
        T got → {
            : b okh ( string_eq got hex )
            ( string_free got )
            ( string_free hex )
            ? okh { ^ @ !v String { T 0 } } {}
            ^ @ !v String { F ( string_from `nurllama: INTEGRITY FAILURE — blob does not hash to its manifest digest` ) }
        }
        F e → {
            ( string_free hex )
            ^ @ !v String { F e }
        }
    }
}
