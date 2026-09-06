// anomaly/store.nu — persistence (milestone M3).
//
// On-disk layout, one directory per model under the store root:
//
//   <root>/<name>/
//     metadata.json            M1 metadata (feature order, scaler, versions…)
//     data.jsonl               raw ingested points, one JSON record per line
//                              (raw records — not projected vectors — so a
//                              retrain can pick up new categories/columns)
//     version_<v>.forest       one binary forest blob per trained version
//     autoencoder.json         the trained autoencoder, if any
//     scores.bin               cached per-point verdicts (epoch-stamped)
//
// The forest blob ("ANOMFOR1") is a little-endian dump of the iforest node
// arena plus the version's decision offset/margin. Loading re-validates
// every structural invariant (lengths, index ranges, node-count caps), so a
// corrupt or truncated blob comes back as None — never undefined behaviour.
//
// Writes are atomic: serialise to `<file>.tmp`, then rename(2) over the
// final name, so a crash mid-write can't leave a half-written model.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/sort.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/autoenc.nu`
$ `deps/iforest/src/iforest.nu`

// Refuse to load blobs claiming more than this many arena nodes / trees /
// name bytes — bounds untrusted counts before any allocation.
: i ANOM_BLOB_MAX_NODES 200000000
: i ANOM_BLOB_MAX_TREES 100000
: i ANOM_BLOB_MAX_NAME 4096

// ── Bounded little-endian reader over an untrusted byte buffer ────────

: BlobRd {
    ( Vec u ) buf
    i pos
    b ok
}

@ __an_rd_new ( Vec u ) buf → *BlobRd {
    : *BlobRd rd # *BlobRd ( nurl_malloc Z BlobRd )
    = . rd buf buf
    = . rd pos 0
    = . rd ok T
    ^ rd
}

@ __an_rd_u64 * BlobRd rd → i {
    ?? ( bytes_read_u64_le . rd buf . rd pos ) {
        T x → {
            = . rd pos + . rd pos 8
            ^ # i x
        }
        F _ → {
            = . rd ok F
            ^ 0
        }
    }
}

@ __an_rd_f64 * BlobRd rd → f {
    ?? ( bytes_read_f64_le . rd buf . rd pos ) {
        T x → {
            = . rd pos + . rd pos 8
            ^ x
        }
        F _ → {
            = . rd ok F
            ^ 0.0
        }
    }
}

// ── VerModel ⇄ bytes ──────────────────────────────────────────────────

@ __an_blob_push_ivec ( Vec u ) out ( Vec i ) xs → v {
    : i n ( vec_len [i] xs )
    ( bytes_push_u64_le out # u64 n )
    : *i dp ( vec_data [i] xs )
    : ~ i k 0
    ~ < k n {
        ( bytes_push_u64_le out # u64 . dp k )
        = k + k 1
    }
}

@ __an_blob_push_fvec ( Vec u ) out ( Vec f ) xs → v {
    : i n ( vec_len [f] xs )
    ( bytes_push_u64_le out # u64 n )
    : *f dp ( vec_data [f] xs )
    : ~ i k 0
    ~ < k n {
        ( bytes_push_f64_le out . dp k )
        = k + k 1
    }
}

// Read `want` i64s (a count-prefixed vector whose count must equal `want`).
@ __an_blob_read_ivec * BlobRd rd i want → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i n ( __an_rd_u64 rd )
    ? == n want {} { = . rd ok F ^ out }
    ( vec_reserve [i] out n )
    : ~ i k 0
    ~ & . rd ok < k n {
        ( vec_push [i] out ( __an_rd_u64 rd ) )
        = k + k 1
    }
    ^ out
}

@ __an_blob_read_fvec * BlobRd rd i want → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : i n ( __an_rd_u64 rd )
    ? == n want {} { = . rd ok F ^ out }
    ( vec_reserve [f] out n )
    : ~ i k 0
    ~ & . rd ok < k n {
        ( vec_push [f] out ( __an_rd_f64 rd ) )
        = k + k 1
    }
    ^ out
}

// Serialise one trained version (forest + offset + margin) to owned bytes.
@ vermodel_to_bytes VerModel vm → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out `ANOMFOR1` )
    : i nlen ( string_len . vm vname )
    ( bytes_push_u64_le out # u64 nlen )
    ( bytes_extend_str out ( string_data . vm vname ) )
    ( bytes_push_f64_le out . vm offset )
    ( bytes_push_f64_le out . vm margin )

    : IForest fo . vm forest
    ( bytes_push_u64_le out # u64 . fo n_trees )
    ( bytes_push_u64_le out # u64 . fo sample_size )
    ( bytes_push_f64_le out . fo c_psi )
    ( bytes_push_u64_le out # u64 . fo n_cols )
    ( __an_blob_push_ivec out . fo roots )
    : i n_nodes ( vec_len [i] . fo feature )
    ( bytes_push_u64_le out # u64 n_nodes )
    ( __an_blob_push_ivec out . fo feature )
    ( __an_blob_push_fvec out . fo split )
    ( __an_blob_push_ivec out . fo left )
    ( __an_blob_push_ivec out . fo right )
    ( __an_blob_push_ivec out . fo size )
    ^ out
}

// Every node index in xs must lie in [-1, n_nodes).
@ __an_blob_idx_ok ( Vec i ) xs i n_nodes → b {
    : i n ( vec_len [i] xs )
    : *i dp ( vec_data [i] xs )
    : ~ i k 0
    ~ < k n {
        : i x . dp k
        ? || < x -1 >= x n_nodes { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Parse a forest blob. None on any structural violation: bad magic, short
// buffer, absurd counts, mismatched array lengths, out-of-range indices.
@ vermodel_from_bytes ( Vec u ) buf → ?VerModel {
    : ( Vec u ) magic ( bytes_from_str `ANOMFOR1` )
    : b magic_ok ( bytes_starts_with buf magic )
    ( vec_free [u] magic )
    ? magic_ok {} { ^ @ ?VerModel { F } }

    : *BlobRd rd ( __an_rd_new buf )
    = . rd pos 8

    : i nlen ( __an_rd_u64 rd )
    ? || < nlen 0 > nlen ANOM_BLOB_MAX_NAME { = . rd ok F } {}
    : ~ String vname ( string_new )
    ? . rd ok {
        : i n ( vec_len [u] buf )
        ? > + . rd pos nlen n { = . rd ok F } {
            : *u bp ( vec_data [u] buf )
            : i base + # i bp . rd pos
            ( string_free vname )
            = vname ( string_from_bytes # *u base nlen )
            = . rd pos + . rd pos nlen
        }
    } {}

    : f off ( __an_rd_f64 rd )
    : f margin ( __an_rd_f64 rd )
    : i n_trees ( __an_rd_u64 rd )
    : i sample_size ( __an_rd_u64 rd )
    : f c_psi ( __an_rd_f64 rd )
    : i n_cols ( __an_rd_u64 rd )
    ? || < n_trees 0 > n_trees ANOM_BLOB_MAX_TREES { = . rd ok F } {}
    ? || < sample_size 0 || < n_cols 0 > n_cols ANOM_BLOB_MAX_NODES { = . rd ok F } {}

    : ( Vec i ) roots ( __an_blob_read_ivec rd n_trees )
    : i n_nodes ( __an_rd_u64 rd )
    ? || < n_nodes 0 > n_nodes ANOM_BLOB_MAX_NODES { = . rd ok F } {}
    : ~ i safe_nodes n_nodes
    ? . rd ok {} { = safe_nodes 0 }
    : ( Vec i ) feature ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec f ) split ( __an_blob_read_fvec rd safe_nodes )
    : ( Vec i ) left ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec i ) right ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec i ) size ( __an_blob_read_ivec rd safe_nodes )

    // Trailing garbage after a well-formed body is also a corrupt file.
    ? == . rd pos ( vec_len [u] buf ) {} { = . rd ok F }

    : ~ b ok . rd ok
    ( nurl_free rd )
    ? ok {
        ? ( __an_blob_idx_ok roots safe_nodes ) {} { = ok F }
        ? ( __an_blob_idx_ok left safe_nodes ) {} { = ok F }
        ? ( __an_blob_idx_ok right safe_nodes ) {} { = ok F }
        // feature must be in [-1, n_cols); leaves (-1) have no split.
        ? ( __an_blob_idx_ok feature n_cols ) {} { = ok F }
    } {}

    ? ok {} {
        ( string_free vname )
        ( vec_free [i] roots )
        ( vec_free [i] feature )
        ( vec_free [f] split )
        ( vec_free [i] left )
        ( vec_free [i] right )
        ( vec_free [i] size )
        ^ @ ?VerModel { F }
    }
    : IForest fo @ IForest { n_trees sample_size c_psi n_cols roots feature split left right size }
    ^ @ ?VerModel { T @ VerModel { vname fo off margin n_cols T } }
}

// ── File store backend ────────────────────────────────────────────────

: Store {
    String root
}

@ store_open s root → Store {
    ^ @ Store { ( string_from root ) }
}

@ store_free Store st → v {
    ( string_free . st root )
}

@ __an_model_dir Store st s name → String {
    : String p ( string_from ( string_data . st root ) )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ __an_model_file Store st s name s file → String {
    : String p ( __an_model_dir st name )
    ( string_push_char p 47 )
    ( string_push_str p file )
    ^ p
}

@ __an_forest_file Store st s name s vname → String {
    : String p ( __an_model_dir st name )
    ( string_push_str p `/version_` )
    ( string_push_str p vname )
    ( string_push_str p `.forest` )
    ^ p
}

// Write bytes atomically: <path>.tmp, then rename over <path>.
@ __an_write_atomic s path ( Vec u ) data → b {
    : String tmp ( string_from path )
    ( string_push_str tmp `.tmp` )
    : !v IoErr wr ( write_file_bytes ( string_data tmp ) data )
    : ~ b ok T
    ?? wr { T _ → {} F _ → { = ok F } }
    ? ok {
        : !v IoErr mv ( fs_rename ( string_data tmp ) path )
        ?? mv { T _ → {} F _ → { = ok F } }
    } {}
    ( string_free tmp )
    ^ ok
}

// A model exists iff its metadata file does.
@ store_exists Store st s name → b {
    : String p ( __an_model_file st name `metadata.json` )
    : b there ( file_exists ( string_data p ) )
    ( string_free p )
    ^ there
}

// Sorted names of every model in the store (dirs with a metadata.json).
@ store_list Store st → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : !( Vec String ) IoErr r ( dir_list ( string_data . st root ) )
    ?? r {
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] entries k ) {
                    T e → {
                        ? ( store_exists st ( string_data e ) ) {
                            ( vec_push [String] out ( string_from ( string_data e ) ) )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] entries \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ( sort_by [String] out \ String a String b → i { ( nurl_str_cmp ( string_data a ) ( string_data b ) ) } )
    ^ out
}

// Persist metadata (creates the model directory as needed).
@ store_save_meta Store st s name * Meta m → b {
    : String d ( __an_model_dir st name )
    : !v IoErr mk ( dir_create_all ( string_data d ) )
    : ~ b ok T
    ?? mk { T _ → {} F _ → { = ok F } }
    ? ok {
        : String txt ( meta_to_json_str m )
        : ( Vec u ) data ( bytes_from_str ( string_data txt ) )
        : String p ( __an_model_file st name `metadata.json` )
        = ok ( __an_write_atomic ( string_data p ) data )
        ( string_free p )
        ( vec_free [u] data )
        ( string_free txt )
    } {}
    ( string_free d )
    ^ ok
}

@ store_load_meta Store st s name → ?*Meta {
    : String p ( __an_model_file st name `metadata.json` )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r {
        T txt → {
            : ?*Meta m ( meta_from_json_str ( string_data txt ) )
            ( string_free txt )
            ^ m
        }
        F _ → { ^ @ ?*Meta { F } }
    }
}

// Persist one trained version's forest blob.
@ store_save_forest Store st s name VerModel vm → b {
    : String d ( __an_model_dir st name )
    : !v IoErr mk ( dir_create_all ( string_data d ) )
    : ~ b ok T
    ?? mk { T _ → {} F _ → { = ok F } }
    ? ok {
        : ( Vec u ) blob ( vermodel_to_bytes vm )
        : String p ( __an_forest_file st name ( string_data . vm vname ) )
        = ok ( __an_write_atomic ( string_data p ) blob )
        ( string_free p )
        ( vec_free [u] blob )
    } {}
    ( string_free d )
    ^ ok
}

// Persist / load the autoencoder version (one JSON per model).
@ store_save_ae Store st s name AeModel ae → b {
    : String d ( __an_model_dir st name )
    : !v IoErr mk ( dir_create_all ( string_data d ) )
    : ~ b ok T
    ?? mk { T _ → {} F _ → { = ok F } }
    ? ok {
        : String txt ( ae_to_json_str ae )
        : ( Vec u ) data ( bytes_from_str ( string_data txt ) )
        : String p ( __an_model_file st name `autoencoder.json` )
        = ok ( __an_write_atomic ( string_data p ) data )
        ( string_free p )
        ( vec_free [u] data )
        ( string_free txt )
    } {}
    ( string_free d )
    ^ ok
}

@ store_load_ae Store st s name → ?AeModel {
    : String p ( __an_model_file st name `autoencoder.json` )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r {
        T txt → {
            : ?AeModel m ( ae_from_json_str ( string_data txt ) )
            ( string_free txt )
            ^ m
        }
        F _ → { ^ @ ?AeModel { F } }
    }
}

// Load one version's forest; None if absent or corrupt. The blob's
// embedded version name must match the requested one — a renamed or
// content-tampered file is treated as corrupt, not trusted.
@ store_load_forest Store st s name s vname → ?VerModel {
    : String p ( __an_forest_file st name vname )
    : !( Vec u ) IoErr r ( read_file_bytes ( string_data p ) )
    ( string_free p )
    ?? r {
        T blob → {
            : ?VerModel vm ( vermodel_from_bytes blob )
            ( vec_free [u] blob )
            ?? vm {
                T got → {
                    ? == ( nurl_str_eq ( string_data . got vname ) vname ) 1 {
                        ^ @ ?VerModel { T got }
                    } {
                        ( anom_vermodel_free got )
                        ^ @ ?VerModel { F }
                    }
                }
                F _ → { ^ @ ?VerModel { F } }
            }
        }
        F _ → { ^ @ ?VerModel { F } }
    }
}

// Remove a trained version's blob (used by reset). Missing file is fine.
@ store_delete_forest Store st s name s vname → v {
    : String p ( __an_forest_file st name vname )
    : !v IoErr r ( file_delete ( string_data p ) )
    ?? r { T _ → {} F _ → {} }
    ( string_free p )
}

// Delete a model entirely (directory and everything in it).
@ store_delete Store st s name → b {
    : String d ( __an_model_dir st name )
    : !v IoErr r ( dir_remove_all ( string_data d ) )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ( string_free d )
    ^ ok
}

// ── Scored-verdict cache (scores.bin) ─────────────────────────────────
//
// Re-scoring a stored ring is pure recomputation: the same point against
// the same forests yields the same verdict every time. The dashboard's
// anomaly scan used to pay for that recomputation on every visit, one HTTP
// round trip AND one full model load per point, which is what made a
// 5000-point scan a minutes-long progress bar.
//
// The cache is a ring-aligned array of verdicts stamped with the model's
// `score_epoch` (prep.nu). Anything that can change a verdict — a retrain,
// a new autoencoder, a margin edit, a version toggled, a reset — bumps the
// epoch, and the whole cache is stale by construction; there is no
// per-entry invalidation rule to get wrong.
//
// Alignment survives ring eviction because rows are keyed on the LIFETIME
// point counter, not the ring index: `base_seen` is the lifetime index of
// row 0, so a ring row `j` of a ring of length L at counter S sits at cache
// index `S - L + j - base_seen`. Rows outside [0, nrows) are simply misses.
//
//   "ANOMSCR2" | u64 epoch | u64 base_seen
//              | u64 nver  | nver × (u64 len, bytes)
//              | u64 nrows | nrows × (f64 score, f64 severity, u64 state, u64 present, u64 flagged)
//
// `state` is 0 for a row never scored under this epoch, 1 for a scored
// verdict and 2 for "the model was not ready for this point". `present` and
// `flagged` are bitmasks over `vnames`, so a version that produced no
// verdict (a timevector window longer than the ring prefix) stays
// distinguishable from one that produced a clean verdict.
: i ANOM_SC_UNSCORED 0
: i ANOM_SC_SCORED 1
: i ANOM_SC_NOT_READY 2

// Refuse a cache claiming more rows/versions than a model could hold.
: i ANOM_SC_MAX_ROWS 100000000
: i ANOM_SC_MAX_VERS 64

: ScoreCache {
    i epoch
    i base_seen
    ( Vec String ) vnames
    ( Vec i ) state
    ( Vec f ) score
    ( Vec f ) severity
    ( Vec i ) present
    ( Vec i ) flagged
}

@ scorecache_new i epoch i base_seen → ScoreCache {
    ^ @ ScoreCache {
        epoch base_seen ( vec_new [String] )
        ( vec_new [i] ) ( vec_new [f] ) ( vec_new [f] ) ( vec_new [i] ) ( vec_new [i] )
    }
}

@ scorecache_free ScoreCache c → v {
    ( vec_free_with [String] . c vnames \ String x → v { ( string_free x ) } )
    ( vec_free [i] . c state )
    ( vec_free [f] . c score )
    ( vec_free [f] . c severity )
    ( vec_free [i] . c present )
    ( vec_free [i] . c flagged )
}

@ scorecache_rows ScoreCache c → i {
    ^ ( vec_len [i] . c state )
}

// Grow to `n` rows, every new row unscored.
@ scorecache_resize ScoreCache c i n → v {
    ~ < ( vec_len [i] . c state ) n {
        ( vec_push [i] . c state ANOM_SC_UNSCORED )
        ( vec_push [f] . c score 0.0 )
        ( vec_push [f] . c severity 0.0 )
        ( vec_push [i] . c present 0 )
        ( vec_push [i] . c flagged 0 )
    }
}

@ scorecache_set ScoreCache c i at i state f score f severity i present i flagged → v {
    : b _a ( vec_set [i] . c state at state )
    : b _b ( vec_set [f] . c score at score )
    : b _s ( vec_set [f] . c severity at severity )
    : b _c ( vec_set [i] . c present at present )
    : b _d ( vec_set [i] . c flagged at flagged )
}

// Do the cached version names still match the live ones, in order?
@ scorecache_vnames_match ScoreCache c ( Vec String ) live → b {
    : i n ( vec_len [String] live )
    ? == n ( vec_len [String] . c vnames ) {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : ~ b same F
        ?? ( vec_get [String] live k ) {
            T a → {
                ?? ( vec_get [String] . c vnames k ) {
                    T b2 → { = same == ( nurl_str_eq ( string_data a ) ( string_data b2 ) ) 1 }
                    F _ → {}
                }
            }
            F _ → {}
        }
        ? same {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __an_sc_file Store st s name → String {
    ^ ( __an_model_file st name `scores.bin` )
}

@ store_save_scores Store st s name ScoreCache c → b {
    : String d ( __an_model_dir st name )
    : !v IoErr mk ( dir_create_all ( string_data d ) )
    ( string_free d )
    : ~ b ok T
    ?? mk { T _ → {} F _ → { = ok F } }
    ? ok {} { ^ F }

    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out `ANOMSCR2` )
    ( bytes_push_u64_le out # u64 . c epoch )
    ( bytes_push_u64_le out # u64 . c base_seen )
    : i nv ( vec_len [String] . c vnames )
    ( bytes_push_u64_le out # u64 nv )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [String] . c vnames k ) {
            T nm → {
                ( bytes_push_u64_le out # u64 ( string_len nm ) )
                ( bytes_extend_str out ( string_data nm ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nr ( vec_len [i] . c state )
    ( bytes_push_u64_le out # u64 nr )
    : *i stp ( vec_data [i] . c state )
    : *f scp ( vec_data [f] . c score )
    : *f svp ( vec_data [f] . c severity )
    : *i prp ( vec_data [i] . c present )
    : *i flp ( vec_data [i] . c flagged )
    = k 0
    ~ < k nr {
        ( bytes_push_f64_le out . scp k )
        ( bytes_push_f64_le out . svp k )
        ( bytes_push_u64_le out # u64 . stp k )
        ( bytes_push_u64_le out # u64 . prp k )
        ( bytes_push_u64_le out # u64 . flp k )
        = k + k 1
    }
    : String p ( __an_sc_file st name )
    = ok ( __an_write_atomic ( string_data p ) out )
    ( string_free p )
    ( vec_free [u] out )
    ^ ok
}

// Load the cache; None when absent, truncated or structurally impossible.
// A rejected cache costs a rescan, never a wrong verdict.
@ store_load_scores Store st s name → ?ScoreCache {
    : String p ( __an_sc_file st name )
    : !( Vec u ) IoErr r ( read_file_bytes ( string_data p ) )
    ( string_free p )
    ?? r {
        T buf → {
            // ANOMSCR1 aggregated by minimum decision value; 2 by the
            // most severe version. An old cache is a miss, never a
            // wrong number.
            : ( Vec u ) magic ( bytes_from_str `ANOMSCR2` )
            : b magic_ok ( bytes_starts_with buf magic )
            ( vec_free [u] magic )
            ? magic_ok {} {
                ( vec_free [u] buf )
                ^ @ ?ScoreCache { F }
            }
            : *BlobRd rd ( __an_rd_new buf )
            = . rd pos 8
            : i epoch ( __an_rd_u64 rd )
            : i base ( __an_rd_u64 rd )
            : i nv ( __an_rd_u64 rd )
            ? || < nv 0 > nv ANOM_SC_MAX_VERS { = . rd ok F } {}
            : ScoreCache c ( scorecache_new epoch base )
            : ~ i k 0
            ~ & . rd ok < k nv {
                : i nlen ( __an_rd_u64 rd )
                ? || < nlen 0 > nlen ANOM_BLOB_MAX_NAME { = . rd ok F } {
                    : i n ( vec_len [u] buf )
                    ? > + . rd pos nlen n { = . rd ok F } {
                        : *u bp ( vec_data [u] buf )
                        : i base2 + # i bp . rd pos
                        ( vec_push [String] . c vnames ( string_from_bytes # *u base2 nlen ) )
                        = . rd pos + . rd pos nlen
                    }
                }
                = k + k 1
            }
            : i nr ( __an_rd_u64 rd )
            ? || < nr 0 > nr ANOM_SC_MAX_ROWS { = . rd ok F } {}
            : ~ i safe nr
            ? . rd ok {} { = safe 0 }
            ( vec_reserve [i] . c state safe )
            ( vec_reserve [f] . c score safe )
            ( vec_reserve [f] . c severity safe )
            ( vec_reserve [i] . c present safe )
            ( vec_reserve [i] . c flagged safe )
            = k 0
            ~ & . rd ok < k safe {
                ( vec_push [f] . c score ( __an_rd_f64 rd ) )
                ( vec_push [f] . c severity ( __an_rd_f64 rd ) )
                ( vec_push [i] . c state ( __an_rd_u64 rd ) )
                ( vec_push [i] . c present ( __an_rd_u64 rd ) )
                ( vec_push [i] . c flagged ( __an_rd_u64 rd ) )
                = k + k 1
            }
            // Trailing garbage after a well-formed body is corruption too.
            ? == . rd pos ( vec_len [u] buf ) {} { = . rd ok F }
            : b good . rd ok
            ( nurl_free rd )
            ( vec_free [u] buf )
            ? good { ^ @ ?ScoreCache { T c } } {}
            ( scorecache_free c )
            ^ @ ?ScoreCache { F }
        }
        F _ → { ^ @ ?ScoreCache { F } }
    }
}

@ store_delete_scores Store st s name → v {
    : String p ( __an_sc_file st name )
    : !v IoErr r ( file_delete ( string_data p ) )
    ?? r { T _ → {} F _ → {} }
    ( string_free p )
}

// ── Raw point log (data.jsonl) ────────────────────────────────────────
//
// One compact JSON record per line, in ingest order, each carrying its
// server-side `timestamp` (unix seconds) alongside the raw client fields.
// Stored raw so retraining can re-encode with newly-learned categories.

// Append one line (the record's compact JSON, no newline).
@ store_append_point Store st s name s line → b {
    : String p ( __an_model_file st name `data.jsonl` )
    : String txt ( string_from line )
    ( string_push_char txt 10 )
    : !v IoErr r ( append_file ( string_data p ) ( string_data txt ) )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ( string_free txt )
    ( string_free p )
    ^ ok
}

// Rewrite the whole log (ring eviction / reset).
@ store_write_points Store st s name ( Vec String ) lines → b {
    : String all ( string_new )
    : i n ( vec_len [String] lines )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] lines k ) {
            T l → {
                ( string_push_str all ( string_data l ) )
                ( string_push_char all 10 )
            }
            F _ → {}
        }
        = k + k 1
    }
    : ( Vec u ) data ( bytes_from_str ( string_data all ) )
    : String p ( __an_model_file st name `data.jsonl` )
    : b ok ( __an_write_atomic ( string_data p ) data )
    ( string_free p )
    ( vec_free [u] data )
    ( string_free all )
    ^ ok
}

// Load the log as owned lines (empty vec if the file doesn't exist).
@ store_load_points Store st s name → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String p ( __an_model_file st name `data.jsonl` )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r {
        T txt → {
            : ( Vec String ) lines ( string_split txt `\n` )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] lines k ) {
                    T l → {
                        ? > ( string_len l ) 0 {
                            ( vec_push [String] out ( string_from ( string_data l ) ) )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
            ( string_free txt )
        }
        F _ → {}
    }
    ^ out
}

// ── Labels (labels.jsonl) ─────────────────────────────────────────────
//
// What a reader said about a stored point: that a flagged row was a
// false positive, or that it was the real thing. Keyed by the point's
// LIFETIME sequence number (Meta.n_seen space, see the score cache
// above), not its ring index, so a label survives eviction and never
// lands on the row that took a shifted slot. One JSON record per line,
// appended, last write wins on replay — the label `none` withdraws an
// earlier one. Labels change no verdict, so they never bump the epoch;
// their first reader is calibration, which leaves the false positives
// out of the set a margin is fitted on.

: s ANOM_LABEL_FP `false_positive`
: s ANOM_LABEL_OK `confirmed`
: s ANOM_LABEL_NONE `none`

: Label {
    i seq  // lifetime sequence number of the point
    i ts  // the point's own timestamp
    String label  // ANOM_LABEL_*
    String by  // who said so (a principal's name, an API key's id, or empty)
    i at  // when (unix seconds)
    String note
}

@ label_free Label l → v {
    ( string_free . l label )
    ( string_free . l by )
    ( string_free . l note )
}

@ labels_free ( Vec Label ) ls → v {
    ( vec_free_with [Label] ls \ Label l → v { ( label_free l ) } )
}

// Is `s` a label a reader may give?
@ label_known s name → b {
    ? == ( nurl_str_eq name ANOM_LABEL_FP ) 1 { ^ T } {}
    ? == ( nurl_str_eq name ANOM_LABEL_OK ) 1 { ^ T } {}
    ? == ( nurl_str_eq name ANOM_LABEL_NONE ) 1 { ^ T } {}
    ^ F
}

@ label_to_json Label l → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `seq` ( json_int . l seq ) )
    ( json_obj_set o `timestamp` ( json_int . l ts ) )
    ( json_obj_set o `label` ( json_str_lit ( string_data . l label ) ) )
    ( json_obj_set o `by` ( json_str_lit ( string_data . l by ) ) )
    ( json_obj_set o `at` ( json_int . l at ) )
    ( json_obj_set o `note` ( json_str_lit ( string_data . l note ) ) )
    ^ o
}

@ __an_label_str Json o s key → String {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } { ^ ( string_new ) } }
        F _ → { ^ ( string_new ) }
    }
}

@ __an_label_int Json o s key → i {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } { ^ -1 } }
        F _ → { ^ -1 }
    }
}

// Append one label. Returns F when the record could not be written.
@ store_append_label Store st s name Label l → b {
    : Json o ( label_to_json l )
    : String txt ( json_stringify o )
    ( json_free o )
    ( string_push_char txt 10 )
    : String p ( __an_model_file st name `labels.jsonl` )
    : !v IoErr r ( append_file ( string_data p ) ( string_data txt ) )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ( string_free p )
    ( string_free txt )
    ^ ok
}

// The labels in force: one per sequence number, the last written; a
// `none` removes the entry. Ascending by seq is not promised — a reader
// wanting the ring order joins on seq (model_label_map). Empty when the
// file does not exist; a line that does not parse is skipped.
@ store_load_labels Store st s name → ( Vec Label ) {
    : ( Vec Label ) out ( vec_new [Label] )
    : String p ( __an_model_file st name `labels.jsonl` )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r {
        T txt → {
            : ( Vec String ) lines ( string_split txt `\n` )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] lines k ) {
                    T l → {
                        ? > ( string_len l ) 0 {
                            : !Json JsonError jr ( json_parse ( string_data l ) )
                            ?? jr {
                                T j → {
                                    ? ( json_is_obj j ) {
                                        : i seq ( __an_label_int j `seq` )
                                        : String lab ( __an_label_str j `label` )
                                        ? & >= seq 0 ( label_known ( string_data lab ) ) {
                                            // Drop what an earlier line said about this seq.
                                            : ~ i q 0
                                            ~ < q ( vec_len [Label] out ) {
                                                : ~ b same F
                                                ?? ( vec_get [Label] out q ) { T e → { = same == . e seq seq } F _ → {} }
                                                ? same {
                                                    ?? ( vec_remove [Label] out q ) { T e → { ( label_free e ) } F _ → {} }
                                                } { = q + q 1 }
                                            }
                                            ? == ( nurl_str_eq ( string_data lab ) ANOM_LABEL_NONE ) 1 {
                                                ( string_free lab )
                                            } {
                                                ( vec_push [Label] out @ Label {
                                                    seq
                                                    ( __an_label_int j `timestamp` )
                                                    lab
                                                    ( __an_label_str j `by` )
                                                    ( __an_label_int j `at` )
                                                    ( __an_label_str j `note` )
                                                } )
                                            }
                                        } { ( string_free lab ) }
                                    } {}
                                    ( json_free j )
                                }
                                F _ → {}
                            }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
            ( string_free txt )
        }
        F _ → {}
    }
    ^ out
}

@ store_delete_labels Store st s name → v {
    : String p ( __an_model_file st name `labels.jsonl` )
    : !v IoErr r ( file_delete ( string_data p ) )
    ?? r { T _ → {} F _ → {} }
    ( string_free p )
}
