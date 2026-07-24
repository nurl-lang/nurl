// packages/hub/src/hub.nu — the front door.
//
//   ( hub_file ref )   → !String String   download one file, return its path
//   ( hub_dir  ref )   → !String String   download a whole repo, return the dir
//   ( hub_ls )         → v                 list what is cached
//   ( hub_rm handle )  → !v String         forget a model, GC unshared blobs
//   ( hub_verify handle ) → !v String      re-hash every blob against its sha
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
    ?? ir { T _ → {} F e → { ( json_free files ) ^ @ !v String { F e } } }
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `name` ( json_str_lit handle ) )
    : b _2 ( json_obj_set j `kind` ( json_str_lit kind ) )
    : b _3 ( json_obj_set j `source` ( json_str_lit source ) )
    : b _4 ( json_obj_set j `rev` ( json_str_lit rev ) )
    : b _5 ( json_obj_set j `size` ( json_int total ) )
    : b _6 ( json_obj_set j `files` files )
    : String txt ( json_stringify j )
    ( json_free j )
    : String mp ( hub_manifest_path root handle )
    : !v IoErr wr ( write_file ( string_data mp ) ( string_data txt ) )
    ( string_free mp )
    ( string_free txt )
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
    ( string_free parent )
    ?? dr { T _ → {} F _ → { ( string_free full ) ^ @ !v String { F ( string_from `hub: cannot create the snapshot subdirectory` ) } } }
    // replace any existing link so a re-fetch is idempotent
    ? ( file_exists ( string_data full ) ) { ( file_delete ( string_data full ) ) } {}
    : String blob ( hub_blob_path root hex )
    : !v IoErr sr ( fs_symlink ( string_data blob ) ( string_data full ) )
    ( string_free blob )
    ( string_free full )
    ?? sr {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `hub: cannot create the snapshot symlink` ) } }
    }
}

// Download one file of a repo (or a direct URL when hf is a passthrough
// ref), returning its blob sha256 hex. `expected` is the published
// sha256 or "" .
@ __hub_get_one String root HubRef r s subpath s expected → !String String {
    : ~ HubRef fr @ HubRef { F ( string_new ) ( string_new ) ( string_new ) ( string_new ) }
    ? . r is_url {
        = fr @ HubRef { T ( string_from ( string_data . r url ) ) ( string_new ) ( string_from `main` ) ( string_new ) }
    } {
        = fr @ HubRef { F ( string_new ) ( string_from ( string_data . r repo ) ) ( string_from ( string_data . r rev ) ) ( string_from subpath ) }
    }
    : String url ( hub_resolve_url fr )
    ( hub_ref_free fr )
    : ~ String staging ( path_basename subpath )
    ? == ( string_len staging ) 0 { ( string_free staging ) = staging ( string_from `download` ) } {}
    : !String String hr ( hub_fetch_blob root ( string_data url ) ( string_data staging ) expected )
    ( string_free url )
    ( string_free staging )
    ^ hr
}

@ hub_dir s ref → !String String {
    : HubRef r ( hub_ref_parse ref )
    ? . r is_url {
        ( hub_ref_free r )
        ^ @ !String String { F ( string_from `hub: a whole-directory fetch needs an org/repo, not a URL` ) }
    } {}
    ? == ( string_len . r repo ) 0 {
        ( hub_ref_free r )
        ^ @ !String String { F ( string_from `hub: could not read an org/repo out of the ref` ) }
    } {}
    ? > ( string_len . r subpath ) 0 {
        ( hub_ref_free r )
        ^ @ !String String { F ( string_from `hub: that ref names a single file — use hub_file` ) }
    } {}

    : !v String ir ( hub_store_init ( hub_store_root ) )
    ?? ir { T _ → {} F e → { ( hub_ref_free r ) ^ @ !String String { F e } } }
    : String root ( hub_store_root )

    : !( Vec HubFile ) String tr ( hub_hf_tree r )
    : ~ ( Vec HubFile ) files ( vec_new [HubFile] )
    ?? tr {
        T v → { = files v }
        F e → { ( string_free root ) ( hub_ref_free r ) ^ @ !String String { F e } }
    }

    : String snapdir ( hub_snapshot_dir root ( string_data . r repo ) ( string_data . r rev ) )
    : !v IoErr sd ( dir_create_all ( string_data snapdir ) )
    ?? sd { T _ → {} F _ → {
            ( string_free snapdir ) ( string_free root )
            ( vec_free_with [HubFile] files \ HubFile f → v { ( hub_file_free f ) } )
            ( hub_ref_free r )
            ^ @ !String String { F ( string_from `hub: cannot create the snapshot directory` ) }
        } }

    : Json farr ( json_arr_new )
    : ~ i total 0
    : ~ b ok T
    : ~ String err ( string_new )
    : i nf ( vec_len [HubFile] files )
    : ~ i k 0
    ~ & < k nf ok {
        ?? ( vec_get [HubFile] files k ) {
            T hf → {
                : !String String gr ( __hub_get_one root r ( string_data . hf path ) ( string_data . hf sha ) )
                ?? gr {
                    T hex → {
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
                            F e → { = ok F ( string_free err ) = err e }
                        }
                        ( string_free hex )
                    }
                    F e → { = ok F ( string_free err ) = err e }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [HubFile] files \ HubFile f → v { ( hub_file_free f ) } )

    ? ok {} {
        ( json_free farr )
        ( string_free snapdir ) ( string_free root )
        ( hub_ref_free r )
        ^ @ !String String { F err }
    }
    ( string_free err )

    : String handle ( __hub_handle r )
    : !v String mw ( __hub_write_manifest root ( string_data handle ) `repo` ( string_data . r repo ) ( string_data . r rev ) farr total )
    ( string_free handle )
    ( string_free root )
    ( hub_ref_free r )
    ?? mw {
        T _ → { ^ @ !String String { T snapdir } }
        F e → { ( string_free snapdir ) ^ @ !String String { F e } }
    }
}

@ hub_file s ref → !String String {
    : HubRef r ( hub_ref_parse ref )
    : !v String ir ( hub_store_init ( hub_store_root ) )
    ?? ir { T _ → {} F e → { ( hub_ref_free r ) ^ @ !String String { F e } } }
    : String root ( hub_store_root )

    // direct URL: no repo listing, no external sha anchor
    ? . r is_url {
        : ~ String base ( path_basename ( string_data . r url ) )
        ? == ( string_len base ) 0 { ( string_free base ) = base ( string_from `download` ) } {}
        : !String String gr ( __hub_get_one root r `` `` )
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
                ( string_free handle )
                ( string_free base )
                : String bp ( hub_blob_path root ( string_data hex ) )
                ( string_free hex ) ( string_free root ) ( hub_ref_free r )
                ?? mw { T _ → {} F e → { ( string_free bp ) ^ @ !String String { F e } } }
                ^ @ !String String { T bp }
            }
            F e → {
                ( string_free base ) ( string_free root ) ( hub_ref_free r )
                ^ @ !String String { F e }
            }
        }
    } {}

    // HF file ref: subpath required
    ? == ( string_len . r subpath ) 0 {
        ( string_free root ) ( hub_ref_free r )
        ^ @ !String String { F ( string_from `hub: that ref names a whole repository — use hub_dir` ) }
    } {}

    // look up the published sha256 for this one file (best effort)
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
                            ( string_free expected )
                            = expected ( string_from ( string_data . hf sha ) )
                            = fsize . hf size
                            = lfs . hf lfs
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [HubFile] files \ HubFile f → v { ( hub_file_free f ) } )
        }
        F → {}
    }

    : !String String gr ( __hub_get_one root r ( string_data . r subpath ) ( string_data expected ) )
    ( string_free expected )
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
            ( string_free handle )
            : String bp ( hub_blob_path root ( string_data hex ) )
            ( string_free hex ) ( string_free root ) ( hub_ref_free r )
            ?? mw { T _ → {} F e → { ( string_free bp ) ^ @ !String String { F e } } }
            ^ @ !String String { T bp }
        }
        F e → {
            ( string_free root ) ( hub_ref_free r )
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
                                ( string_free hs )
                                ( string_push_str ln `  ` )
                                ( string_push_int ln nfiles )
                                ( string_push_str ln ` file(s)` )
                                ( nurl_print ( string_data ln ) )
                                ( nurl_print `\n` )
                                ( string_free ln )
                                ( json_free j )
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → { ( nurl_print `(no models cached)\n` ) }
    }
    ( string_free mdir )
    ( string_free root )
}

// The one call a consumer wants: turn a model argument into a usable local
// path, fetching it if need be. An argument that already names an existing
// file or directory is passed straight through (so a local model keeps
// working); otherwise it is a Hugging Face ref — a single file (a URL, or a
// ref with a subpath) resolves through hub_file, a bare org/repo through
// hub_dir. `embed serve BAAI/bge-m3` and `embed serve ./my-model` both just
// work.
@ hub_get s ref → !String String {
    ? != ( nurl_path_type ref ) 0 {
        ^ @ !String String { T ( string_from ref ) }
    } {}
    : HubRef r ( hub_ref_parse ref )
    : ~ b isfile F
    ? . r is_url { = isfile T } {}
    ? > ( string_len . r subpath ) 0 { = isfile T } {}
    ( hub_ref_free r )
    ? isfile { ^ ( hub_file ref ) } {}
    ^ ( hub_dir ref )
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
                ( json_free j ) ( string_free handle ) ( hub_ref_free r ) ( string_free root )
                ^ @ ?String { T d }
            } {}
            // file kind: the single file entry's sha → blob path
            : ~ String bp ( string_new )
            ?? ( json_obj_get j `files` ) {
                T fa → {
                    ?? ( json_arr_get fa 0 ) {
                        T fe → {
                            ?? ( json_obj_get fe `sha` ) {
                                T sj → { ( string_free bp ) = bp ( hub_blob_path root ( json_str_data sj ) ) }
                                F → {}
                            }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j ) ( string_free handle ) ( hub_ref_free r ) ( string_free root )
            ? > ( string_len bp ) 0 { ^ @ ?String { T bp } } {}
            ( string_free bp )
            ^ @ ?String { F }
        }
        F → {
            ( string_free handle ) ( hub_ref_free r ) ( string_free root )
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
    ( hub_ref_free rf )
    : !v String r ( hub_store_verify root ( string_data handle ) )
    ( string_free handle )
    ( string_free root )
    ^ r
}

@ hub_rm s ref → !v String {
    : String root ( hub_store_root )
    : HubRef rf ( hub_ref_parse ref )
    : String handle ( __hub_handle rf )
    ( hub_ref_free rf )
    ? ( hub_manifest_exists root ( string_data handle ) ) {} {
        ( string_free handle )
        ( string_free root )
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
            ( string_free mp )
            : ~ i k 0
            ~ < k ( vec_len [String] shas ) {
                ?? ( vec_get [String] shas k ) {
                    T sh → {
                        ? ( _hub_blob_shared root ( string_data sh ) ( string_data handle ) ) {} {
                            : String bp ( hub_blob_path root ( string_data sh ) )
                            ( file_delete ( string_data bp ) )
                            ( string_free bp )
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
                ( string_free snap )
            } {}
            ( vec_free_with [String] shas \ String s → v { ( string_free s ) } )
            ( json_free j )
        }
        F → {}
    }
    ( string_free handle )
    ( string_free root )
    ^ @ !v String { T 0 }
}
