// store_test.nu — M3 unit tests: forest blob round-trip (bit-exact scores),
// file store save/load/list/delete, corrupt/truncated blob rejection.
// Uses the directory in $ANOMALY_TEST_DIR (default ./anomaly_store_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( pline label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( pline label )
        = g_fail + g_fail 1
    }
}

@ make_data → ( Vec f ) {
    : Rng g ( rng_seed 7 )
    : ( Vec f ) data ( vec_with_cap [f] 416 )
    : ~ i k 0
    ~ < k 200 {
        ( vec_push [f] data - * ( rng_u01 g ) 2.0 1.0 )
        ( vec_push [f] data - * ( rng_u01 g ) 2.0 1.0 )
        = k + k 1
    }
    = k 0
    ~ < k 8 {
        ( vec_push [f] data + 8.0 ( rng_u01 g ) )
        ( vec_push [f] data + 8.0 ( rng_u01 g ) )
        = k + k 1
    }
    ( rng_free g )
    ^ data
}

@ train_one ( Vec f ) scaled → VerModel {
    : VerCfg cfg @ VerCfg { ( string_from `short_term` ) 180 0 0 0 100 256 -1.0 0.1 T }
    : VerModel vm ( anom_train_version scaled 208 2 cfg )
    ( _an_vercfg_free cfg )
    ^ vm
}

// ── 1. Blob round-trip is bit-exact ───────────────────────────────────

@ test_blob_roundtrip → v {
    : ( Vec f ) data ( make_data )
    : Scaler sc ( scaler_fit data 208 2 )
    ( scaler_apply_matrix sc data 208 2 )
    : VerModel vm ( train_one data )

    : ( Vec u ) blob ( vermodel_to_bytes vm )
    ( check > ( vec_len [u] blob ) 64 `blob: non-trivial size` )
    : ?VerModel back ( vermodel_from_bytes blob )
    ?? back {
        T vm2 → {
            ( check == ( nurl_str_eq ( string_data . vm2 vname ) `short_term` ) 1 `blob: vname survives` )
            ( check == . vm2 offset . vm offset `blob: offset bit-exact` )
            ( check == . vm2 margin . vm margin `blob: margin bit-exact` )
            // Every row scores bit-identically through the reloaded forest.
            : ~ b same T
            : ~ i r 0
            ~ < r 208 {
                ? == ( anom_decision_row vm data r ) ( anom_decision_row vm2 data r ) {} { = same F }
                = r + r 1
            }
            ( check same `blob: all 208 scores bit-exact after reload` )
            ( anom_vermodel_free vm2 )
        }
        F _ → { ( check F `blob: parses back` ) }
    }
    ( vec_free [u] blob )
    ( anom_vermodel_free vm )
    ( scaler_free sc )
    ( vec_free [f] data )
}

// ── 2. Corrupt / truncated blobs are rejected cleanly ─────────────────

@ test_blob_corruption → v {
    : ( Vec f ) data ( make_data )
    : Scaler sc ( scaler_fit data 208 2 )
    ( scaler_apply_matrix sc data 208 2 )
    : VerModel vm ( train_one data )
    : ( Vec u ) blob ( vermodel_to_bytes vm )
    : i blen ( vec_len [u] blob )

    // Truncations at assorted depths (header, name, arrays, last byte).
    : ~ i rejected 0
    : ~ i tried 0
    : ( Vec i ) cuts ( vec_new [i] )
    ( vec_push [i] cuts 0 )
    ( vec_push [i] cuts 4 )
    ( vec_push [i] cuts 9 )
    ( vec_push [i] cuts 40 )
    ( vec_push [i] cuts / blen 2 )
    ( vec_push [i] cuts - blen 1 )
    : ~ i k 0
    ~ < k ( vec_len [i] cuts ) {
        ?? ( vec_get [i] cuts k ) {
            T cut → {
                : ( Vec u ) part ( bytes_slice blob 0 cut )
                = tried + tried 1
                : ?VerModel r ( vermodel_from_bytes part )
                ?? r { T bad → { ( anom_vermodel_free bad ) } F _ → { = rejected + rejected 1 } }
                ( vec_free [u] part )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check == rejected tried `corrupt: every truncation rejected` )
    ( vec_free [i] cuts )

    // Flip one byte inside the node arrays: must be rejected (index check)
    // — flip a root index high byte to shoot it out of range.
    : ( Vec u ) mut ( vec_clone [u] blob )
    // roots array starts at 8 (magic) + 8 (len) + 10 (name) + 16 + 32 = 74;
    // +8 count prefix, second-highest byte of root[0]:
    : i at + 74 14
    ?? ( vec_get [u] mut at ) {
        T old → { ( vec_set [u] mut at # u 255 ) }
        F _ → {}
    }
    : ?VerModel r2 ( vermodel_from_bytes mut )
    ?? r2 { T bad → { ( anom_vermodel_free bad ) ( check F `corrupt: out-of-range index rejected` ) } F _ → { ( check T `corrupt: out-of-range index rejected` ) } }
    ( vec_free [u] mut )

    // Trailing garbage after a valid body: rejected.
    : ( Vec u ) padded ( vec_clone [u] blob )
    ( vec_push [u] padded # u 0 )
    : ?VerModel r3 ( vermodel_from_bytes padded )
    ?? r3 { T bad → { ( anom_vermodel_free bad ) ( check F `corrupt: trailing garbage rejected` ) } F _ → { ( check T `corrupt: trailing garbage rejected` ) } }
    ( vec_free [u] padded )

    ( vec_free [u] blob )
    ( anom_vermodel_free vm )
    ( scaler_free sc )
    ( vec_free [f] data )
}

// ── 3. File store: save / load / exists / list / delete ──────────────

@ test_store → v {
    : ~ String root ( string_from `./anomaly_store_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    : ( Vec String ) empty ( store_list st )
    ( check == ( vec_len [String] empty ) 0 `store: empty list on fresh root` )
    ( vec_free_with [String] empty \ String x → v { ( string_free x ) } )

    // Build a model: meta + one trained version.
    : *Meta m ( meta_new `sensor_a` `2026-07-03T00:00:00Z` )
    : ( Vec f ) data ( make_data )
    : Scaler sc ( scaler_fit data 208 2 )
    ( meta_set_scaler m sc )
    ( scaler_apply_matrix sc data 208 2 )
    : VerModel vm ( train_one data )

    ( check ( store_save_meta st `sensor_a` m ) `store: meta saved` )
    ( check ( store_save_forest st `sensor_a` vm ) `store: forest saved` )
    ( check ( store_exists st `sensor_a` ) `store: exists` )
    ( check == ( store_exists st `nope` ) F `store: missing model absent` )

    : ( Vec String ) names ( store_list st )
    ( check == ( vec_len [String] names ) 1 `store: list has 1 model` )
    ?? ( vec_get [String] names 0 ) {
        T n0 → { ( check == ( nurl_str_eq ( string_data n0 ) `sensor_a` ) 1 `store: listed name` ) }
        F _ → {}
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )

    // Reload: metadata equal, forest scores bit-exact.
    : ?*Meta m2o ( store_load_meta st `sensor_a` )
    ?? m2o {
        T m2 → {
            : String s1 ( meta_to_json_str m )
            : String s2 ( meta_to_json_str m2 )
            ( check ( string_eq s1 s2 ) `store: metadata survives round-trip` )
            ( string_free s1 )
            ( string_free s2 )
            ( meta_free m2 )
        }
        F _ → { ( check F `store: metadata loads` ) }
    }
    : ?VerModel vm2o ( store_load_forest st `sensor_a` `short_term` )
    ?? vm2o {
        T vm2 → {
            : ~ b same T
            : ~ i r 0
            ~ < r 208 {
                ? == ( anom_decision_row vm data r ) ( anom_decision_row vm2 data r ) {} { = same F }
                = r + r 1
            }
            ( check same `store: reloaded forest scores bit-exact` )
            ( anom_vermodel_free vm2 )
        }
        F _ → { ( check F `store: forest loads` ) }
    }
    // Missing version → None.
    : ?VerModel nov ( store_load_forest st `sensor_a` `daily` )
    ?? nov { T bad → { ( anom_vermodel_free bad ) ( check F `store: missing version None` ) } F _ → { ( check T `store: missing version None` ) } }

    // Labels: append, replay with last write winning, withdraw, delete.
    : Label l1 @ Label { 7 100 ( string_from ANOM_LABEL_FP ) ( string_from `a` ) 1 ( string_from `n1` ) }
    : Label l2 @ Label { 9 102 ( string_from ANOM_LABEL_OK ) ( string_from `b` ) 2 ( string_new ) }
    : Label l3 @ Label { 7 100 ( string_from ANOM_LABEL_OK ) ( string_from `c` ) 3 ( string_from `n3` ) }
    ( check ( store_append_label st `sensor_a` l1 ) `labels: append` )
    ( check ( store_append_label st `sensor_a` l2 ) `labels: append another` )
    ( check ( store_append_label st `sensor_a` l3 ) `labels: rewrite the first` )
    ( label_free l1 )
    ( label_free l2 )
    ( label_free l3 )
    : ( Vec Label ) lls ( store_load_labels st `sensor_a` )
    ( check == ( vec_len [Label] lls ) 2 `labels: one entry per sequence` )
    : ~ b lw F
    : ~ i q 0
    ~ < q ( vec_len [Label] lls ) {
        ?? ( vec_get [Label] lls q ) {
            T l → {
                ? == . l seq 7 {
                    = lw & == ( nurl_str_eq ( string_data . l label ) ANOM_LABEL_OK ) 1
                    & == ( nurl_str_eq ( string_data . l by ) `c` ) 1
                    & == . l at 3 == ( nurl_str_eq ( string_data . l note ) `n3` ) 1
                } {}
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check lw `labels: the last write wins, whole record` )
    ( labels_free lls )
    : Label l4 @ Label { 9 102 ( string_from ANOM_LABEL_NONE ) ( string_from `b` ) 4 ( string_new ) }
    ( check ( store_append_label st `sensor_a` l4 ) `labels: withdraw` )
    ( label_free l4 )
    : ( Vec Label ) lls2 ( store_load_labels st `sensor_a` )
    ( check == ( vec_len [Label] lls2 ) 1 `labels: none removes the entry` )
    ( labels_free lls2 )
    ( store_delete_labels st `sensor_a` )
    : ( Vec Label ) lls3 ( store_load_labels st `sensor_a` )
    ( check == ( vec_len [Label] lls3 ) 0 `labels: deleted file loads empty` )
    ( labels_free lls3 )
    ( check ( label_known ANOM_LABEL_FP ) `labels: false_positive is known` )
    ( check ! ( label_known `maybe` ) `labels: maybe is not` )

    // Point log: append, load, rewrite.
    ( store_append_point st `sensor_a` `{"temp":1,"timestamp":100}` )
    ( store_append_point st `sensor_a` `{"temp":2,"timestamp":101}` )
    : ( Vec String ) pts ( store_load_points st `sensor_a` )
    ( check == ( vec_len [String] pts ) 2 `store: point log appends + loads` )
    ( vec_free_with [String] pts \ String x → v { ( string_free x ) } )
    : ( Vec String ) one ( vec_new [String] )
    ( vec_push [String] one ( string_from `{"temp":3,"timestamp":102}` ) )
    ( store_write_points st `sensor_a` one )
    ( vec_free_with [String] one \ String x → v { ( string_free x ) } )
    : ( Vec String ) pts2 ( store_load_points st `sensor_a` )
    ( check == ( vec_len [String] pts2 ) 1 `store: point log rewrite` )
    ( vec_free_with [String] pts2 \ String x → v { ( string_free x ) } )

    // Corrupt the forest file on disk: load returns None.
    : String fpath ( string_from ( string_data root ) )
    ( string_push_str fpath `/sensor_a/version_short_term.forest` )
    : !( Vec u ) IoErr fraw ( read_file_bytes ( string_data fpath ) )
    ?? fraw {
        T fb → {
            ( vec_set [u] fb 20 # u 254 )
            : !v IoErr wr ( write_file_bytes ( string_data fpath ) fb )
            ?? wr { T _ → {} F _ → {} }
            ( vec_free [u] fb )
            : ?VerModel cv ( store_load_forest st `sensor_a` `short_term` )
            ?? cv { T bad → { ( anom_vermodel_free bad ) ( check F `store: on-disk corruption rejected` ) } F _ → { ( check T `store: on-disk corruption rejected` ) } }
        }
        F _ → { ( check F `store: forest file readable for tamper test` ) }
    }
    ( string_free fpath )

    // Delete removes everything.
    ( check ( store_delete st `sensor_a` ) `store: delete` )
    ( check == ( store_exists st `sensor_a` ) F `store: gone after delete` )

    ( anom_vermodel_free vm )
    ( scaler_free sc )
    ( vec_free [f] data )
    ( meta_free m )
    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )
}

@ main → i {
    ( test_blob_roundtrip )
    ( test_blob_corruption )
    ( test_store )
    : String summary ( string_from `store_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
