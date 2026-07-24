// packages/hub/src/store.nu — the shared, content-addressed model cache
// (~/.nurl/models). Shaped like Hugging Face's own hub cache:
//
//   <root>/blobs/sha256-<64hex>              every file, named by content
//   <root>/models/<org>--<repo>/snapshots/<rev>/   a symlink farm = a
//                                            real "model directory"
//   <root>/manifests/<handle>                one small JSON per handle
//
// A manifest is deliberately uniform across the single-file and the
// whole-repo case — a lone GGUF is just a repo with one file:
//
//   { name, kind: "file"|"repo", source, rev, size,
//     files: [ { path, sha, size, lfs } ] }
//
// The sha of a file IS its blob address, so two handles that share a
// file share the bytes; `rm` drops a blob only once no manifest still
// references it, and `verify` re-hashes every blob against its recorded
// sha and refuses drift. The symlink farm lives in hub.nu; this file
// owns the blob layer and the manifest.
//
//   ( hub_store_root )                  → String  $NURL_MODELS | $HUB_HOME | ~/.nurl/models
//   ( hub_store_init root )             → !v String
//   ( hub_blob_path root hex )          → String  blobs/sha256-<hex>
//   ( hub_manifest_path root name )     → String
//   ( hub_hash_file path )              → !String String  streaming sha256
//   ( hub_store_verify root name )      → !v String

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`

@ hub_store_root → String {
    : ?String ov ( env_get `NURL_MODELS` )
    ?? ov {
        T v → { ^ v }
        F → {}
    }
    : ?String ov2 ( env_get `HUB_HOME` )
    ?? ov2 {
        T v → { ^ v }
        F → {}
    }
    : String home ( env_var_or `HOME` `.` )
    : String base ( path_join ( string_data home ) `.nurl` )
    ( string_free home )
    : String r ( path_join ( string_data base ) `models` )
    ( string_free base )
    ^ r
}

// Handle names live on the filesystem: keep [A-Za-z0-9._-], map the
// rest (the slash of an org/repo name included) to '_'.
@ _hub_safe_name s name → String {
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

@ hub_blob_path String root s hex → String {
    : String bdir ( path_join ( string_data root ) `blobs` )
    : String nm ( string_from `sha256-` )
    ( string_push_str nm hex )
    : String p ( path_join ( string_data bdir ) ( string_data nm ) )
    ( string_free bdir )
    ( string_free nm )
    ^ p
}

@ hub_manifest_path String root s name → String {
    : String mdir ( path_join ( string_data root ) `manifests` )
    : String sn ( _hub_safe_name name )
    : String p ( path_join ( string_data mdir ) ( string_data sn ) )
    ( string_free mdir )
    ( string_free sn )
    ^ p
}

// The materialised model directory for a repo handle:
//   models/<safe-repo>/snapshots/<rev>
@ hub_snapshot_dir String root s repo s rev → String {
    : String mroot ( path_join ( string_data root ) `models` )
    : String sr ( _hub_safe_name repo )
    : String rdir ( path_join ( string_data mroot ) ( string_data sr ) )
    ( string_free mroot )
    ( string_free sr )
    : String snaps ( path_join ( string_data rdir ) `snapshots` )
    ( string_free rdir )
    : String d ( path_join ( string_data snaps ) rev )
    ( string_free snaps )
    ^ d
}

@ hub_store_init String root → !v String {
    : String b ( path_join ( string_data root ) `blobs` )
    : String m ( path_join ( string_data root ) `manifests` )
    : String md ( path_join ( string_data root ) `models` )
    : !v IoErr r1 ( dir_create_all ( string_data b ) )
    : !v IoErr r2 ( dir_create_all ( string_data m ) )
    : !v IoErr r3 ( dir_create_all ( string_data md ) )
    ( string_free b )
    ( string_free m )
    ( string_free md )
    : ~ b ok T
    ?? r1 { T _ → {} F _ → { = ok F } }
    ?? r2 { T _ → {} F _ → { = ok F } }
    ?? r3 { T _ → {} F _ → { = ok F } }
    ? ok { ^ @ !v String { T 0 } } {}
    : String msg ( string_from `hub: cannot create the cache at ` )
    ( string_push_str msg ( string_data root ) )
    ^ @ !v String { F msg }
}

// Streaming sha256 of a file — constant memory whatever the size.
@ hub_hash_file s path → !String String {
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
            : String msg ( string_from `hub: cannot open ` )
            ( string_push_str msg path )
            ^ @ !String String { F msg }
        }
    }
}

// ---- manifest read helpers -------------------------------------------

// Read a manifest into its parsed Json (owned) — None when absent/bad.
@ hub_manifest_read String root s name → ?Json {
    : String mp ( hub_manifest_path root name )
    : !String IoErr rr ( read_file ( string_data mp ) )
    ( string_free mp )
    ?? rr {
        T txt → {
            : !Json JsonError pj ( json_parse ( string_data txt ) )
            ( string_free txt )
            ?? pj {
                T j → { ^ @ ?Json { T j } }
                F _ → { ^ @ ?Json { F } }
            }
        }
        F _ → { ^ @ ?Json { F } }
    }
}

// Does the manifest exist on disk?
@ hub_manifest_exists String root s name → b {
    : String mp ( hub_manifest_path root name )
    : b e ( file_exists ( string_data mp ) )
    ( string_free mp )
    ^ e
}

// Collect every blob sha referenced by a manifest into `out` (a Vec of
// owned hex Strings). `j` is the parsed manifest (borrow, not freed).
@ _hub_manifest_shas Json j ( Vec String ) out → v {
    ?? ( json_obj_get j `files` ) {
        T fa → {
            : i n ( json_arr_len fa )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get fa k ) {
                    T fe → {
                        ?? ( json_obj_get fe `sha` ) {
                            T sj → {
                                : s sd ( json_str_data sj )
                                ? == ( nurl_str_len sd ) 64 {
                                    ( vec_push [String] out ( string_from sd ) )
                                } {}
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
}

// True when any manifest OTHER than `except_name` references blob `hex`.
@ _hub_blob_shared String root s hex s except_name → b {
    : String mdir ( path_join ( string_data root ) `manifests` )
    : String keep ( _hub_safe_name except_name )
    : ~ b shared F
    : !( Vec String ) IoErr lr ( dir_list ( string_data mdir ) )
    ?? lr {
        T names → {
            : ~ i k 0
            ~ & < k ( vec_len [String] names ) ! shared {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( string_eq nm keep ) {} {
                            : String mp ( path_join ( string_data mdir ) ( string_data nm ) )
                            : !String IoErr rr ( read_file ( string_data mp ) )
                            ?? rr {
                                T txt → {
                                    : !Json JsonError pj ( json_parse ( string_data txt ) )
                                    ?? pj {
                                        T j → {
                                            : ( Vec String ) shas ( vec_new [String] )
                                            ( _hub_manifest_shas j shas )
                                            : ~ i s2 0
                                            ~ < s2 ( vec_len [String] shas ) {
                                                ?? ( vec_get [String] shas s2 ) {
                                                    T sh → { ? ( nurl_str_eq ( string_data sh ) hex ) { = shared T } {} }
                                                    F → {}
                                                }
                                                = s2 + s2 1
                                            }
                                            ( vec_free_with [String] shas \ String s → v { ( string_free s ) } )
                                            ( json_free j )
                                        }
                                        F _ → {}
                                    }
                                    ( string_free txt )
                                }
                                F _ → {}
                            }
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

// Re-hash every blob a handle references and compare to the recorded
// sha — the cache's integrity loop, streaming and constant-memory.
@ hub_store_verify String root s name → !v String {
    ?? ( hub_manifest_read root name ) {
        T j → {
            : ~ b ok T
            : ~ String bad ( string_new )
            ?? ( json_obj_get j `files` ) {
                T fa → {
                    : i n ( json_arr_len fa )
                    : ~ i k 0
                    ~ & < k n ok {
                        ?? ( json_arr_get fa k ) {
                            T fe → {
                                : ~ String sha ( string_new )
                                ?? ( json_obj_get fe `sha` ) {
                                    T sj → { ( string_free sha ) = sha ( string_from ( json_str_data sj ) ) }
                                    F → {}
                                }
                                ? == ( string_len sha ) 64 {
                                    : String bp ( hub_blob_path root ( string_data sha ) )
                                    ? ( file_exists ( string_data bp ) ) {
                                        : !String String hr ( hub_hash_file ( string_data bp ) )
                                        ?? hr {
                                            T got → {
                                                ? ( string_eq got sha ) {} {
                                                    = ok F
                                                    ( string_free bad )
                                                    = bad ( string_from `hub: INTEGRITY FAILURE — a blob does not hash to its recorded sha256` )
                                                }
                                                ( string_free got )
                                            }
                                            F e → { = ok F ( string_free bad ) = bad e }
                                        }
                                    } {
                                        = ok F
                                        ( string_free bad )
                                        = bad ( string_from `hub: a referenced blob is missing from the cache` )
                                    }
                                    ( string_free bp )
                                } {}
                                ( string_free sha )
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                }
                F → {}
            }
            ( json_free j )
            ? ok { ( string_free bad ) ^ @ !v String { T 0 } } {}
            ^ @ !v String { F bad }
        }
        F → { ^ @ !v String { F ( string_from `hub: no such model in the cache` ) } }
    }
}
