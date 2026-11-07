// packages/hub/src/hub.nu — the front door.
//
//   ( hub_file ref )   → !String String   download one file, return its path
//   ( hub_dir  ref )   → !String String   download a whole repo, return the dir
//   ( hub_ls )         → v                 list what is cached
//   ( hub_rm handle )  → !v String         forget a model, GC unshared blobs
//   ( hub_verify handle ) → !v String      re-hash every blob against its sha
//
// hub_file_opts / hub_dir_opts / hub_get_opts take a HubOpts (pull.nu:
// files at once, connections per file, chunk size); the plain calls use
// hub_opts_default ($HUB_JOBS, $HUB_CONNS, $HUB_CHUNK, else 2 × 8, 32 MiB).
//
// hub_dir materialises a model directory the Hugging Face way: each file
// is a symlink under models/<repo>/snapshots/<rev>/ pointing at its
// content-addressed blob, so an existing loader opens a real directory
// and two revisions that share a file share the bytes on disk.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/ext/json.nu`
$ `store.nu`
$ `hf.nu`
$ `pull.nu`

// This package is multiple files (store / hf / pull / hub). Following the
// ecosystem convention for a CONSUMED library, a source file does not
// `$`-import its siblings — the entry point (this package's main.nu / tests,
// or a consumer) imports every file, so a consumer can `$ deps/hub/src/*.nu`
// without a src/-relative path breaking against its own build root.

// canonical handle for a ref: the URL, or org/repo@rev[/subpath]
@ __hub_handle HubRef r → String {
    ? . r is_url { ^ ( string_from ( string_data . r url ) ) } {}
    : String h ( string_from ( string_data . r repo ) )
    ( string_push_char h 64 )
    ( string_push_str h ( string_data . r rev ) )
    ? > ( string_len . r subpath ) 0 {
        ( string_push_char h 47 )
        ( string_push_str h ( string_data . r subpath ) )
    } {}
    ^ h
}

// Write a manifest. `files` is a Json array (ownership moves in).
@ __hub_write_manifest String root s handle s kind s source s rev Json files i total → !v String {
    : !v String ir ( hub_store_init root )
    ?? ir { T _ → {} F e → { ^ @ !v String { F e } } }
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `name` ( json_str_lit handle ) )
    : b _2 ( json_obj_set j `kind` ( json_str_lit kind ) )
    : b _3 ( json_obj_set j `source` ( json_str_lit source ) )
    : b _4 ( json_obj_set j `rev` ( json_str_lit rev ) )
    : b _5 ( json_obj_set j `size` ( json_int total ) )
    : b _6 ( json_obj_set j `files` files )
    : String txt ( json_stringify j )
    : String mp ( hub_manifest_path root handle )
    : !v IoErr wr ( write_file ( string_data mp ) ( string_data txt ) )
    ?? wr {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `hub: cannot write the manifest` ) } }
    }
}

// Point snapshot/<relpath> at blobs/sha256-<hex> (absolute target).
@ __hub_link_blob String root s snapdir s relpath s hex → !v String {
    : String full ( path_join snapdir relpath )
    : String parent ( path_dirname ( string_data full ) )
    : !v IoErr dr ( dir_create_all ( string_data parent ) )
    ?? dr { T _ → {} F _ → { ^ @ !v String { F ( string_from `hub: cannot create the snapshot subdirectory` ) } } }
    // replace any existing link so a re-fetch is idempotent
    ? ( file_exists ( string_data full ) ) { ( file_delete ( string_data full ) ) } {}
    : String blob ( hub_blob_path root hex )
    : !v IoErr sr ( fs_symlink ( string_data blob ) ( string_data full ) )
    ?? sr {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `hub: cannot create the snapshot symlink` ) } }
    }
}

// The download of one file of a repo (or of a direct URL when `r` is a
// passthrough ref). `expected` is the published sha256 or "", `size` the
// listed size or 0.
@ __hub_job String root HubRef r s subpath s expected i size → HubJob {
    : ~ HubRef fr @ HubRef { F ( string_new ) ( string_new ) ( string_new ) ( string_new ) }
    : ~ String name ( string_new )
    ? . r is_url {
        = fr @ HubRef { T ( string_from ( string_data . r url ) ) ( string_new ) ( string_from `main` ) ( string_new ) }
        = name ( path_basename ( string_data . r url ) )
    } {
        = fr @ HubRef { F ( string_new ) ( string_from ( string_data . r repo ) ) ( string_from ( string_data . r rev ) ) ( string_from subpath ) }
        = name ( path_basename subpath )
    }
    : String url ( hub_resolve_url fr )
    : String stage ( hub_stage_name ( string_data url ) ( string_data name ) expected )
    // hub 0.2 staged a file as blobs/<basename>.part. Its bytes are taken
    // over only where the published sha256 will check them.
    : ~ String legacy ( string_new )
    ? & == ( nurl_str_len expected ) 64 > ( string_len name ) 0 {
        : String old ( _hub_safe_name ( string_data name ) )
        = legacy ( _hub_part_path root ( string_data old ) )
    } {}
    ^ @ HubJob { url stage legacy ( string_from expected ) size }
}

// Fetch one job alone; → its sha256 hex.
@ __hub_get_one String root HubJob jb HubOpts o s label → !String String {
    : ( Vec HubJob ) jobs ( vec_new [HubJob] )
    ( vec_push [HubJob] jobs @ HubJob { ( string_from ( string_data . jb url ) ) ( string_from ( string_data . jb stage ) ) ( string_from ( string_data . jb legacy ) ) ( string_from ( string_data . jb expected ) ) . jb size } )
    ?? ( hub_fetch_all root jobs o label ) {
        T hexes → {
            ?? ( vec_get [String] hexes 0 ) {
                T h → { ^ @ !String String { T ( string_from ( string_data h ) ) } }
                F → { ^ @ !String String { F ( string_from `hub: the download returned nothing` ) } }
            }
        }
        F e → { ^ @ !String String { F e } }
    }
}

@ hub_dir s ref → !String String { ^ ( hub_dir_opts ref ( hub_opts_default ) ) }

// hub_dir with explicit transfer options: `. o jobs` files at once, each
// over up to `. o conns` connections.
@ hub_dir_opts s ref HubOpts o → !String String {
    : HubRef r ( hub_ref_parse ref )
    ? . r is_url {
        ^ @ !String String { F ( string_from `hub: a whole-directory fetch needs an org/repo, not a URL` ) }
    } {}
    ? == ( string_len . r repo ) 0 {
        ^ @ !String String { F ( string_from `hub: could not read an org/repo out of the ref` ) }
    } {}
    ? > ( string_len . r subpath ) 0 {
        ^ @ !String String { F ( string_from `hub: that ref names a single file — use hub_file` ) }
    } {}

    : !v String ir ( hub_store_init ( hub_store_root ) )
    ?? ir { T _ → {} F e → { ^ @ !String String { F e } } }
    : String root ( hub_store_root )

    : !( Vec HubFile ) String tr ( hub_hf_tree r )
    : ~ ( Vec HubFile ) files ( vec_new [HubFile] )
    ?? tr {
        T v → { = files v }
        F e → { ^ @ !String String { F e } }
    }

    : String snapdir ( hub_snapshot_dir root ( string_data . r repo ) ( string_data . r rev ) )
    : !v IoErr sd ( dir_create_all ( string_data snapdir ) )
    ?? sd { T _ → {} F _ → {
            ^ @ !String String { F ( string_from `hub: cannot create the snapshot directory` ) }
        } }

    // One download per staging name: two paths with one sha256 share it.
    : i nf ( vec_len [HubFile] files )
    : ( Vec HubJob ) jobs ( vec_new [HubJob] )
    : ( Vec i ) which ( vec_new [i] )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [HubFile] files k ) {
            T hf → {
                : HubJob jb ( __hub_job root r ( string_data . hf path ) ( string_data . hf sha ) . hf size )
                : ~ i at -1
                : ~ i q 0
                ~ & < q ( vec_len [HubJob] jobs ) < at 0 {
                    ?? ( vec_get [HubJob] jobs q ) {
                        T o2 → { ? ( string_eq . o2 stage . jb stage ) { = at q } {} }
                        F → {}
                    }
                    = q + q 1
                }
                ? < at 0 {
                    = at ( vec_len [HubJob] jobs )
                    ( vec_push [HubJob] jobs jb )
                } {}
                ( vec_push [i] which at )
            }
            F → { ( vec_push [i] which -1 ) }
        }
        = k + k 1
    }

    : !( Vec String ) String fr ( hub_fetch_all root jobs o ( string_data . r repo ) )
    : ~ ( Vec String ) hexes ( vec_new [String] )
    ?? fr {
        T v → { = hexes v }
        F e → { ^ @ !String String { F e } }
    }

    : Json farr ( json_arr_new )
    : ~ i total 0
    = k 0
    ~ < k nf {
        ?? ( vec_get [HubFile] files k ) {
            T hf → {
                : i at ( vec_at [i] which k )
                : ~ String hex ( string_new )
                ?? ( vec_get [String] hexes at ) { T h → { = hex ( string_from ( string_data h ) ) } F → {} }
                : !v String lr ( __hub_link_blob root ( string_data snapdir ) ( string_data . hf path ) ( string_data hex ) )
                ?? lr {
                    T _ → {
                        : Json fe ( json_obj_new )
                        : b _a ( json_obj_set fe `path` ( json_str_lit ( string_data . hf path ) ) )
                        : b _b ( json_obj_set fe `sha` ( json_str_lit ( string_data hex ) ) )
                        : b _c ( json_obj_set fe `size` ( json_int . hf size ) )
                        : b _d ( json_obj_set fe `lfs` ( json_bool . hf lfs ) )
                        : b _e ( json_arr_push farr fe )
                        = total + total . hf size
                    }
                    F e → { ^ @ !String String { F e } }
                }
            }
            F → {}
        }
        = k + k 1
    }

    : String handle ( __hub_handle r )
    : !v String mw ( __hub_write_manifest root ( string_data handle ) `repo` ( string_data . r repo ) ( string_data . r rev ) farr total )
    ?? mw {
        T _ → { ^ @ !String String { T snapdir } }
        F e → { ^ @ !String String { F e } }
    }
}

@ hub_file s ref → !String String { ^ ( hub_file_opts ref ( hub_opts_default ) ) }

// hub_file with explicit transfer options (`. o conns` connections).
@ hub_file_opts s ref HubOpts o → !String String {
    : HubRef r ( hub_ref_parse ref )
    : !v String ir ( hub_store_init ( hub_store_root ) )
    ?? ir { T _ → {} F e → { ^ @ !String String { F e } } }
    : String root ( hub_store_root )

    // direct URL: no repo listing, no external sha anchor
    ? . r is_url {
        : ~ String base ( path_basename ( string_data . r url ) )
        ? == ( string_len base ) 0 { = base ( string_from `download` ) } {}
        : HubJob jb ( __hub_job root r `` `` 0 )
        : !String String gr ( __hub_get_one root jb o ( string_data base ) )
        ?? gr {
            T hex → {
                : Json farr ( json_arr_new )
                : Json fe ( json_obj_new )
                : b _a ( json_obj_set fe `path` ( json_str_lit ( string_data base ) ) )
                : b _b ( json_obj_set fe `sha` ( json_str_lit ( string_data hex ) ) )
                : ~ i sz 0
                ?? ( file_size ( string_data ( hub_blob_path root ( string_data hex ) ) ) ) { T v → { = sz v } F → {} }
                : b _c ( json_obj_set fe `size` ( json_int sz ) )
                : b _d ( json_obj_set fe `lfs` ( json_bool F ) )
                : b _e ( json_arr_push farr fe )
                : String handle ( __hub_handle r )
                : !v String mw ( __hub_write_manifest root ( string_data handle ) `file` ( string_data . r url ) `main` farr sz )
                : String bp ( hub_blob_path root ( string_data hex ) )
                ?? mw { T _ → {} F e → { ^ @ !String String { F e } } }
                ^ @ !String String { T bp }
            }
            F e → {
                ^ @ !String String { F e }
            }
        }
    } {}

    // HF file ref: subpath required
    ? == ( string_len . r subpath ) 0 {
        ^ @ !String String { F ( string_from `hub: that ref names a whole repository — use hub_dir` ) }
    } {}

    // look up the published sha256 and size of this one file (best effort)
    : ~ String expected ( string_new )
    : ~ i fsize 0
    : ~ b lfs F
    ?? ( hub_hf_tree r ) {
        T files → {
            : ~ i k 0
            ~ < k ( vec_len [HubFile] files ) {
                ?? ( vec_get [HubFile] files k ) {
                    T hf → {
                        ? ( nurl_str_eq ( string_data . hf path ) ( string_data . r subpath ) ) {
                            = expected ( string_from ( string_data . hf sha ) )
                            = fsize . hf size
                            = lfs . hf lfs
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }

    : HubJob jb ( __hub_job root r ( string_data . r subpath ) ( string_data expected ) fsize )
    : String label ( path_basename ( string_data . r subpath ) )
    : !String String gr ( __hub_get_one root jb o ( string_data label ) )
    ?? gr {
        T hex → {
            : Json farr ( json_arr_new )
            : Json fe ( json_obj_new )
            : b _a ( json_obj_set fe `path` ( json_str_lit ( string_data . r subpath ) ) )
            : b _b ( json_obj_set fe `sha` ( json_str_lit ( string_data hex ) ) )
            : b _c ( json_obj_set fe `size` ( json_int fsize ) )
            : b _d ( json_obj_set fe `lfs` ( json_bool lfs ) )
            : b _e ( json_arr_push farr fe )
            : String handle ( __hub_handle r )
            : !v String mw ( __hub_write_manifest root ( string_data handle ) `file` ( string_data . r repo ) ( string_data . r rev ) farr fsize )
            : String bp ( hub_blob_path root ( string_data hex ) )
            ?? mw { T _ → {} F e → { ^ @ !String String { F e } } }
            ^ @ !String String { T bp }
        }
        F e → {
            ^ @ !String String { F e }
        }
    }
}

// ---- listing / removal -----------------------------------------------

@ hub_ls → v {
    : String root ( hub_store_root )
    : String mdir ( path_join ( string_data root ) `manifests` )
    : !( Vec String ) IoErr lr ( dir_list ( string_data mdir ) )
    ?? lr {
        T names → {
            ? == ( vec_len [String] names ) 0 { ( nurl_print `(no models cached)\n` ) } {}
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ?? ( hub_manifest_read root ( string_data nm ) ) {
                            T j → {
                                : ~ s hn ``
                                ?? ( json_obj_get j `name` ) { T v → { = hn ( json_str_data v ) } F → {} }
                                : ~ s kind ``
                                ?? ( json_obj_get j `kind` ) { T v → { = kind ( json_str_data v ) } F → {} }
                                : ~ i sz 0
                                ?? ( json_obj_get j `size` ) { T v → { ?? ( json_num_as_i v ) { T n → { = sz n } F → {} } } F → {} }
                                : ~ i nfiles 0
                                ?? ( json_obj_get j `files` ) { T v → { = nfiles ( json_arr_len v ) } F → {} }
                                : String ln ( string_from hn )
                                : ~ i pad - 44 ( string_len ln )
                                ~ > pad 0 { ( string_push_char ln 32 ) = pad - pad 1 }
                                ( string_push_str ln `[` ) ( string_push_str ln kind ) ( string_push_str ln `] ` )
                                : String hs ( progress_human sz )
                                ( string_push_str ln ( string_data hs ) )
                                ( string_push_str ln `  ` )
                                ( string_push_int ln nfiles )
                                ( string_push_str ln ` file(s)` )
                                ( nurl_print ( string_data ln ) )
                                ( nurl_print `\n` )
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F _ → { ( nurl_print `(no models cached)\n` ) }
    }
}

// The one call a consumer wants: turn a model argument into a usable local
// path, fetching it if need be. An argument that already names an existing
// file or directory is passed straight through (so a local model keeps
// working); otherwise it is a Hugging Face ref — a single file (a URL, or a
// ref with a subpath) resolves through hub_file, a bare org/repo through
// hub_dir. `embed serve BAAI/bge-m3` and `embed serve ./my-model` both just
// work.
@ hub_get s ref → !String String { ^ ( hub_get_opts ref ( hub_opts_default ) ) }

// hub_get with explicit transfer options.
@ hub_get_opts s ref HubOpts o → !String String {
    ? != ( nurl_path_type ref ) 0 {
        ^ @ !String String { T ( string_from ref ) }
    } {}
    : HubRef r ( hub_ref_parse ref )
    : ~ b isfile F
    ? . r is_url { = isfile T } {}
    ? > ( string_len . r subpath ) 0 { = isfile T } {}
    ? isfile { ^ ( hub_file_opts ref o ) } {}
    ^ ( hub_dir_opts ref o )
}

// Resolve a ref to its local path WITHOUT fetching — the blob path for a
// cached file, the snapshot dir for a cached repo. None when not cached.
@ hub_path s ref → ?String {
    : String root ( hub_store_root )
    : HubRef r ( hub_ref_parse ref )
    : String handle ( __hub_handle r )
    ?? ( hub_manifest_read root ( string_data handle ) ) {
        T j → {
            : ~ s kind ``
            ?? ( json_obj_get j `kind` ) { T v → { = kind ( json_str_data v ) } F → {} }
            ? ( nurl_str_eq kind `repo` ) {
                : ~ s rev ``
                ?? ( json_obj_get j `rev` ) { T v → { = rev ( json_str_data v ) } F → {} }
                : String d ( hub_snapshot_dir root ( string_data . r repo ) rev )
                ^ @ ?String { T d }
            } {}
            // file kind: the single file entry's sha → blob path
            : ~ String bp ( string_new )
            ?? ( json_obj_get j `files` ) {
                T fa → {
                    ?? ( json_arr_get fa 0 ) {
                        T fe → {
                            ?? ( json_obj_get fe `sha` ) {
                                T sj → { = bp ( hub_blob_path root ( json_str_data sj ) ) }
                                F → {}
                            }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ? > ( string_len bp ) 0 { ^ @ ?String { T bp } } {}
            ^ @ ?String { F }
        }
        F → {
            ^ @ ?String { F }
        }
    }
}

// verify/rm accept a ref and canonicalize it to a handle, so the same
// ref that was pulled (`org/repo`) matches its stored handle (`org/repo@main`).
@ hub_verify s ref → !v String {
    : String root ( hub_store_root )
    : HubRef rf ( hub_ref_parse ref )
    : String handle ( __hub_handle rf )
    : !v String r ( hub_store_verify root ( string_data handle ) )
    ^ r
}

@ hub_rm s ref → !v String {
    : String root ( hub_store_root )
    : HubRef rf ( hub_ref_parse ref )
    : String handle ( __hub_handle rf )
    ? ( hub_manifest_exists root ( string_data handle ) ) {} {
        ^ @ !v String { F ( string_from `hub: no such model in the cache` ) }
    }
    // collect this handle's blobs, drop each that no other manifest shares
    ?? ( hub_manifest_read root ( string_data handle ) ) {
        T j → {
            : ( Vec String ) shas ( vec_new [String] )
            ( _hub_manifest_shas j shas )
            : ~ s rev ``
            ?? ( json_obj_get j `rev` ) { T v → { = rev ( json_str_data v ) } F → {} }
            : ~ s kind ``
            ?? ( json_obj_get j `kind` ) { T v → { = kind ( json_str_data v ) } F → {} }
            : ~ s repo ``
            ?? ( json_obj_get j `source` ) { T v → { = repo ( json_str_data v ) } F → {} }
            // remove the manifest first so the shared check ignores it
            : String mp ( hub_manifest_path root ( string_data handle ) )
            ( file_delete ( string_data mp ) )
            : ~ i k 0
            ~ < k ( vec_len [String] shas ) {
                ?? ( vec_get [String] shas k ) {
                    T sh → {
                        ? ( _hub_blob_shared root ( string_data sh ) ( string_data handle ) ) {} {
                            : String bp ( hub_blob_path root ( string_data sh ) )
                            ( file_delete ( string_data bp ) )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            // drop the snapshot symlink farm for a repo
            ? ( nurl_str_eq kind `repo` ) {
                : String snap ( hub_snapshot_dir root repo rev )
                ( dir_remove_all ( string_data snap ) )
            } {}
        }
        F → {}
    }
    ^ @ !v String { T 0 }
}
