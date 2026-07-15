// model_test.nu — M2 unit tests: version kernel over iforest, decision
// conventions, contamination pinning, batch report parity, determinism.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`

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

// 200 2-D points near the origin + 8 far-away outliers (deterministic).
// Outliers occupy the LAST 8 row indices (200..207).
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

@ test_cfg f contamination f margin → VerCfg {
    ^ @ VerCfg { ( string_from `test` ) 0 0 100 256 contamination margin T }
}

// ── Outlier separation, margin rule, report parity ────────────────────

@ test_batch_outliers → v {
    : ( Vec f ) data ( make_data )
    : VerCfg cfg ( test_cfg -1.0 0.1 )
    : BatchReport rep ( anomaly_batch data 208 2 cfg )

    ( check == . rep total_rows 208 `batch: total_rows` )

    // Every injected outlier (rows 200..207) must be flagged...
    : ~ i outliers_hit 0
    : i nh ( vec_len [i] . rep anomaly_indices )
    : ~ i k 0
    ~ < k nh {
        ?? ( vec_get [i] . rep anomaly_indices k ) {
            T idx → { ? >= idx 200 { = outliers_hit + outliers_hit 1 } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( check == outliers_hit 8 `batch: all 8 injected outliers flagged` )
    // ...with few false positives (allow < 5% of the normals).
    ( check < - . rep anomaly_count 8 10 `batch: few false positives` )
    ( check . rep has_anomalies `batch: has_anomalies` )

    // anomaly_percentage = count / total * 100.
    : f want / * # f . rep anomaly_count 100.0 208.0
    ( check < ( float_abs - . rep anomaly_percentage want ) 0.000001 `batch: percentage parity` )

    // Outlier scores are far more negative than a typical normal score.
    : ~ f df_norm 0.0
    ?? ( vec_get [f] . rep scores 0 ) { T x → { = df_norm x } F _ → {} }
    : ~ f df_out 0.0
    ?? ( vec_get [f] . rep scores 207 ) { T x → { = df_out x } F _ → {} }
    ( check < df_out df_norm `batch: outlier df below normal df` )
    ( check <= df_out -0.1 `batch: outlier crosses the margin` )

    ( anomaly_report_free rep )
    ( _an_vercfg_free cfg )
    ( vec_free [f] data )
}

// ── Determinism: fixed seed ⇒ identical scores ────────────────────────

@ test_determinism → v {
    : ( Vec f ) data ( make_data )
    : VerCfg cfg1 ( test_cfg -1.0 0.1 )
    : VerCfg cfg2 ( test_cfg -1.0 0.1 )
    : BatchReport r1 ( anomaly_batch data 208 2 cfg1 )
    : BatchReport r2 ( anomaly_batch data 208 2 cfg2 )
    : ~ b same T
    : i n ( vec_len [f] . r1 scores )
    ? == n ( vec_len [f] . r2 scores ) {} { = same F }
    : *f a ( vec_data [f] . r1 scores )
    : *f b2 ( vec_data [f] . r2 scores )
    : ~ i k 0
    ~ < k n {
        ? == . a k . b2 k {} { = same F }
        = k + k 1
    }
    ( check same `determinism: two trainings give byte-identical scores` )
    ( anomaly_report_free r1 )
    ( anomaly_report_free r2 )
    ( _an_vercfg_free cfg1 )
    ( _an_vercfg_free cfg2 )
    ( vec_free [f] data )
}

// ── Contamination pinning ─────────────────────────────────────────────
//
// With contamination = c and margin = 0, offset_ sits at the 100*c
// percentile of training score_samples, so ~c of the training rows come
// out with decision_function < 0.

@ test_contamination → v {
    : ( Vec f ) data ( make_data )
    : VerCfg cfg ( test_cfg 0.05 0.0 )
    : BatchReport rep ( anomaly_batch data 208 2 cfg )
    // 5% of 208 ≈ 10.4 — allow slack for score ties around the cut.
    ( check >= . rep anomaly_count 6 `contamination: >= 6 of 208 flagged` )
    ( check <= . rep anomaly_count 16 `contamination: <= 16 of 208 flagged` )
    ( anomaly_report_free rep )
    ( _an_vercfg_free cfg )
    ( vec_free [f] data )

    // auto ⇒ offset pinned at exactly -0.5.
    : ( Vec f ) data2 ( make_data )
    : VerCfg cfg2 ( test_cfg -1.0 0.0 )
    : Scaler sc ( scaler_fit data2 208 2 )
    ( scaler_apply_matrix sc data2 208 2 )
    : VerModel vm ( anom_train_version data2 208 2 cfg2 )
    ( check == . vm offset -0.5 `contamination: auto offset = -0.5` )
    ( anom_vermodel_free vm )
    ( _an_vercfg_free cfg2 )
    ( scaler_free sc )
    ( vec_free [f] data2 )
}

@ main → i {
    ( test_batch_outliers )
    ( test_determinism )
    ( test_contamination )
    : String summary ( string_from `model_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
