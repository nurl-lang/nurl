// scan_test.nu — the cached ring scan, the relative autoencoder margin,
// per-feature attribution, and fine-tuning the autoencoder.
//
//   margin   — the autoencoder's decision_margin is RELATIVE to its
//              reconstruction threshold, so the same number means the same
//              thing on any data scale, and the reference's absolute-margin
//              muting cannot come back.
//   contrib  — the per-feature reconstruction error names the feature that
//              broke the relationship, not the one with the largest value.
//   scan     — model_scan_at agrees point-for-point with model_detect_only,
//              answers a second call entirely from the cache, respects time
//              windows and limits, and re-scores after anything that could
//              change a verdict (retrain, margin edit, version toggle).
//   evict    — cached verdicts stay aligned to their points across ring
//              eviction, because rows are keyed on the lifetime counter.
//   ft       — model_finetune now reaches the autoencoder as well.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_scan_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/autoenc.nu`
$ `src/store.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000
: ~ i g_lcg 1

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

// One point on the manifold flow ≈ 2·pres, plus an independent `temp`.
@ mkpoint f pres f flow f temp → Json {
    : Json j ( json_obj_new )
    ( json_obj_set j `pres` ( json_float pres ) )
    ( json_obj_set j `flow` ( json_float flow ) )
    ( json_obj_set j `temp` ( json_float temp ) )
    ^ j
}

@ ingest * Model mo f pres f flow f temp i at → v {
    : Json j ( mkpoint pres flow temp )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    ?? r { T vd → { ( verdict_free vd ) } F e → { ( string_free e ) } }
}

// The autoencoder's slice of a detect_only verdict.
: AeSlice { b present b hit f df f margin }

@ ae_probe * Model mo Json j → AeSlice {
    : !Verdict String r ( model_detect_only mo j )
    ?? r {
        T vd → {
            : ~ AeSlice out @ AeSlice { F F 0.0 0.0 }
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        ? == ( nurl_str_eq ( string_data . vv vvname ) `autoencoder` ) 1 {
                            = out @ AeSlice { T . vv anomaly . vv score . vv margin }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( verdict_free vd )
            ^ out
        }
        F e → { ( string_free e ) ^ @ AeSlice { F F 0.0 0.0 } }
    }
}

// The aggregate verdict of one stored ring row, the slow way.
@ detect_row * Model mo i at → b {
    : ~ b anom F
    ?? ( model_point_json mo at ) {
        T j → {
            : !Verdict String r ( model_detect_only mo j )
            ?? r {
                T vd → { = anom . vd anomaly ( verdict_free vd ) }
                F e → { ( string_free e ) }
            }
            ( json_free j )
        }
        F → {}
    }
    ^ anom
}

// How many ring points the autoencoder version flags, via a scan.
@ ae_flag_count * Model mo → i {
    : ScanOut so ( model_scan_at mo 0 0 0 F )
    : ~ i bit -1
    : ~ i k 0
    ~ < k ( vec_len [String] . so vnames ) {
        ?? ( vec_get [String] . so vnames k ) {
            T nm → { ? == ( nurl_str_eq ( string_data nm ) `autoencoder` ) 1 { = bit k } {} }
            F _ → {}
        }
        = k + k 1
    }
    : ~ i n 0
    ? >= bit 0 {
        = k 0
        ~ < k ( vec_len [ScoredPt] . so pts ) {
            ?? ( vec_get [ScoredPt] . so pts k ) {
                T r → { ? != & . r sp_flagged << 1 bit 0 { = n + n 1 } {} }
                F _ → {}
            }
            = k + k 1
        }
    } {}
    ( scan_free so )
    ^ n
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_scan_test` )
    : Store st ( store_open ( string_data root ) )

    // ── a model on a 1-D manifold: flow = 2·pres (+ noise), temp free ──
    : *Model mo ( model_open_at st `scan` T0 )
    ( model_set_limits mo 30 150000 )
    ( model_set_schedule mo 1000000 1000000 )
    = g_lcg 11
    : ~ i k 0
    ~ < k 400 {
        : f pres + 1.0 ( lcg_u01 )
        : f flow + * 2.0 pres * 0.02 - ( lcg_u01 ) 0.5
        : f temp + 20.0 ( lcg_u01 )
        ( ingest mo pres flow temp + T0 * k 60 )
        = k + k 1
    }
    : i used ( model_force_train_at mo + T0 * 400 60 )
    ( check > used 0 `trained on the ring` )
    : ( Vec i ) hidden ( vec_new [i] )
    : String aerr ( model_train_autoencoder mo hidden -1.0 )
    ( check == ( string_len aerr ) 0 `autoencoder trained` )
    ( string_free aerr )
    ( vec_free [i] hidden )
    : AeModel ae0 . mo ae
    ( check . ae0 trained `autoencoder is live` )
    ( check > . ae0 threshold 0.0 `reconstruction threshold is positive` )

    // ── the margin is RELATIVE ────────────────────────────────────────
    //
    // An off-manifold probe: pres 1.5 with flow 5.0 instead of ~3.0.
    // Both values are inside the training range of their own column, so
    // only a joint model can object.
    : Json bad ( mkpoint 1.5 5.0 20.5 )
    : b _m0 ( model_set_margin mo `autoencoder` 0.0 )
    : AeSlice s0 ( ae_probe mo bad )
    ( check . s0 present `the autoencoder has a verdict` )
    ( check . s0 hit `at margin 0 the off-manifold point is an anomaly` )
    ( check == . s0 margin 0.0 `margin 0 is an effective band of 0` )

    // The reference's absolute 0.05 would demand an error ~100x the
    // threshold and mute the version; as a FRACTION it is 5% over it.
    : b _m1 ( model_set_margin mo `autoencoder` ANOM_AE_MARGIN )
    : AeSlice s1 ( ae_probe mo bad )
    ( check . s1 hit `at the default margin it is still an anomaly` )
    : f want * . ae0 threshold ANOM_AE_MARGIN
    ( check < ( float_abs - . s1 margin want ) 0.000000001
    `effective margin is threshold x decision_margin` )
    ( check < . s1 margin 0.05 `the effective band is far below the raw 0.05` )

    // A margin big enough to swallow the probe mutes the version, which is
    // what the knob is FOR — it just now scales with the model.
    : b _m2 ( model_set_margin mo `autoencoder` 1000.0 )
    : AeSlice s2 ( ae_probe mo bad )
    ( check ! . s2 hit `a huge relative margin mutes the version` )
    : b _m3 ( model_set_margin mo `autoencoder` ANOM_AE_MARGIN )

    // An on-manifold point at the same scale must stay clean.
    : Json good ( mkpoint 1.5 3.0 20.5 )
    : AeSlice s3 ( ae_probe mo good )
    ( check ! . s3 hit `an on-manifold point is not an anomaly` )

    // ── per-feature attribution ───────────────────────────────────────
    //
    // `flow` is what broke the relationship, so it must carry more of the
    // reconstruction error than the untouched `temp`.
    : ( Vec AeContrib ) cs ( model_ae_contrib mo bad 3 )
    ( check == ( vec_len [AeContrib] cs ) 3 `contributions come back top-3` )
    : ~ f share_flow -1.0
    : ~ f share_temp -1.0
    : ~ b sorted T
    : ~ f prev 1000000.0
    = k 0
    ~ < k ( vec_len [AeContrib] cs ) {
        ?? ( vec_get [AeContrib] cs k ) {
            T c → {
                ? > . c ac_err prev { = sorted F } {}
                = prev . c ac_err
                ? == ( nurl_str_eq ( string_data . c ac_name ) `flow` ) 1 { = share_flow . c ac_share } {}
                ? == ( nurl_str_eq ( string_data . c ac_name ) `temp` ) 1 { = share_temp . c ac_share } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check sorted `contributions are ordered worst-first` )
    ( check > share_flow share_temp `the feature that broke the relation carries more error` )
    ( ae_contrib_free cs )
    : ( Vec AeContrib ) cs2 ( model_ae_contrib mo good 3 )
    ( check == ( vec_len [AeContrib] cs2 ) 3 `a clean point still reports shares` )
    ( ae_contrib_free cs2 )
    ( json_free bad )
    ( json_free good )

    // ── the scan agrees with detect_only ──────────────────────────────
    : ScanOut sc1 ( model_scan_at mo 0 0 0 F )
    ( check == . sc1 total 400 `scan sees the whole ring` )
    ( check == ( vec_len [ScoredPt] . sc1 pts ) 400 `scan returns every row` )
    ( check == . sc1 misses 400 `a cold scan computes every verdict` )
    ( check == . sc1 hits 0 `a cold scan hits nothing` )
    : ~ b agree T
    = k 0
    ~ < k 400 {
        ?? ( vec_get [ScoredPt] . sc1 pts k ) {
            T r → {
                ? != . r sp_anomaly ( detect_row mo . r sp_idx ) { = agree F } {}
            }
            F _ → {}
        }
        = k + k 20
    }
    ( check agree `every sampled scan verdict matches detect_only` )
    : i anoms1 . sc1 anomalies
    ( scan_free sc1 )

    // ── the cache ─────────────────────────────────────────────────────
    : ScanOut sc2 ( model_scan_at mo 0 0 0 F )
    ( check == . sc2 hits 400 `a second scan is served entirely from cache` )
    ( check == . sc2 misses 0 `a warm scan computes nothing` )
    ( check == . sc2 anomalies anoms1 `the cached verdicts are the same verdicts` )
    ( scan_free sc2 )

    // force ignores the cache but must not change the answer
    : ScanOut sc3 ( model_scan_at mo 0 0 0 T )
    ( check == . sc3 misses 400 `refresh recomputes everything` )
    ( check == . sc3 anomalies anoms1 `recomputing reproduces the verdicts` )
    ( scan_free sc3 )

    // ── time window and limit ─────────────────────────────────────────
    : i mid + T0 * 200 60
    : ScanOut sc4 ( model_scan_at mo mid 0 0 F )
    ( check == . sc4 considered 200 `from= keeps the later half` )
    ( check == . sc4 hits 200 `a window reuses the full scan's cache` )
    ( scan_free sc4 )
    : ScanOut sc5 ( model_scan_at mo 0 mid 0 F )
    ( check == . sc5 considered 201 `to= keeps the earlier half` )
    ( scan_free sc5 )
    : ScanOut sc6 ( model_scan_at mo 0 0 50 F )
    ( check == ( vec_len [ScoredPt] . sc6 pts ) 50 `limit caps the rows returned` )
    ( check == . sc6 considered 400 `considered still reports the whole window` )
    : ~ i last_idx -1
    ?? ( vec_get [ScoredPt] . sc6 pts 49 ) { T r → { = last_idx . r sp_idx } F _ → {} }
    ( check == last_idx 399 `limit takes the NEWEST rows` )
    ( scan_free sc6 )

    // ── invalidation ──────────────────────────────────────────────────
    : b _m4 ( model_set_margin mo `weekly` 0.02 )
    : ScanOut sc7 ( model_scan_at mo 0 0 0 F )
    ( check == . sc7 misses 400 `a margin edit invalidates the cache` )
    ( scan_free sc7 )
    : b _m5 ( model_set_margin mo `weekly` 0.06 )

    : b _e1 ( model_set_version_enabled mo `daily` F )
    : ScanOut sc8 ( model_scan_at mo 0 0 0 F )
    ( check == . sc8 misses 400 `toggling a version invalidates the cache` )
    : ~ b has_daily F
    = k 0
    ~ < k ( vec_len [String] . sc8 vnames ) {
        ?? ( vec_get [String] . sc8 vnames k ) {
            T nm → { ? == ( nurl_str_eq ( string_data nm ) `daily` ) 1 { = has_daily T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( check ! has_daily `a disabled version leaves the scan's version list` )
    ( scan_free sc8 )
    : b _e2 ( model_set_version_enabled mo `daily` T )

    : ScanOut sc9 ( model_scan_at mo 0 0 0 F )
    ( scan_free sc9 )
    : i _u2 ( model_force_train_at mo + T0 * 400 60 )
    : ScanOut sc10 ( model_scan_at mo 0 0 0 F )
    ( check == . sc10 misses 400 `a retrain invalidates the cache` )
    ( scan_free sc10 )

    // ── eviction keeps the cache aligned ──────────────────────────────
    //
    // Rows are keyed on the lifetime counter, so evicting the oldest point
    // must not shift every cached verdict onto its neighbour.
    : *Model ev ( model_open_at st `evict` T0 )
    ( model_set_limits ev 30 120 )
    ( model_set_schedule ev 1000000 1000000 )
    = g_lcg 23
    = k 0
    ~ < k 120 {
        : f pres + 1.0 ( lcg_u01 )
        ( ingest ev pres * 2.0 pres + 20.0 ( lcg_u01 ) + T0 * k 60 )
        = k + k 1
    }
    : i _u3 ( model_force_train_at ev + T0 * 120 60 )
    : ScanOut e1 ( model_scan_at ev 0 0 0 F )
    ( check == . e1 total 120 `the eviction model is at capacity` )
    ( scan_free e1 )
    // One more point: the ring drops row 0 and gains a new tail.
    ( ingest ev 1.5 3.0 20.5 + T0 * 121 60 )
    : ScanOut e2 ( model_scan_at ev 0 0 0 F )
    ( check == . e2 total 120 `still at capacity after eviction` )
    ( check == . e2 hits 119 `every surviving point keeps its cached verdict` )
    ( check == . e2 misses 1 `only the newly arrived point is scored` )
    : ~ b ev_agree T
    = k 0
    ~ < k ( vec_len [ScoredPt] . e2 pts ) {
        ?? ( vec_get [ScoredPt] . e2 pts k ) {
            T r → {
                ? != . r sp_anomaly ( detect_row ev . r sp_idx ) { = ev_agree F } {}
            }
            F _ → {}
        }
        = k + k 7
    }
    ( check ev_agree `post-eviction cached verdicts still match their points` )
    ( scan_free e2 )
    ( model_free ev )

    // ── fine-tuning reaches the autoencoder ───────────────────────────
    : b _m6 ( model_set_margin mo `autoencoder` 0.0 )
    : i ae_before ( ae_flag_count mo )
    ( check > ae_before 1 `at margin 0 the ring flags several points` )
    // The default fine-tune: 1 % of the window (400 points, all inside
    // the 24 h default) → four flagged, in the AE's own relative units.
    : FineTuneReport rep ( model_finetune mo )
    : ~ b saw_ae F
    : ~ f ae_new -1.0
    : ~ i ae_rep_after -1
    = k 0
    ~ < k ( vec_len [FtVer] . rep items ) {
        ?? ( vec_get [FtVer] . rep items k ) {
            T ft → {
                ? == ( nurl_str_eq ( string_data . ft ftname ) `autoencoder` ) 1 {
                    = saw_ae T
                    = ae_new . ft new_margin
                    = ae_rep_after . ft after
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( finetune_free rep )
    ( check saw_ae `finetune reports the autoencoder version` )
    ( check > ae_new 0.0 `the autoencoder gets a positive relative margin` )
    : f stored ( meta_version_margin ( model_metadata mo ) `autoencoder` -1.0 )
    ( check < ( float_abs - stored ae_new ) 0.000000001 `the new margin is persisted` )
    ( check == ae_rep_after 4 `1 % of 400 points: the report says four flagged` )
    // The scan, which applies the relative margin through the live verdict
    // path, agrees with the report — that is what makes the margin a
    // setting with a visible effect.
    : i ae_after ( ae_flag_count mo )
    ( check == ae_after 4 `the scan flags exactly those four` )
    ( check < ae_after ae_before `fine-tune narrows the autoencoder's alarm` )

    // Calibration reads the same numbers back without writing anything.
    : CalReport cal ( model_calibrate mo 0 0 )
    ( check == . cal n_rows 400 `calibrate: every ring row scored` )
    : ~ b cal_ae F
    = k 0
    ~ < k ( vec_len [CalVer] . cal items ) {
        ?? ( vec_get [CalVer] . cal items k ) {
            T cv → {
                ? == ( nurl_str_eq ( string_data . cv cvname ) `autoencoder` ) 1 {
                    = cal_ae T
                    ( check == . cv n 400 `calibrate: autoencoder saw every row` )
                    ( check == . cv flagged 4 `calibrate: flagged at the stored margin = 4` )
                    ( check < ( float_abs - . cv cur_margin ae_new ) 0.000000001 `calibrate: reports the stored margin` )
                    // Rounding to few digits may trade a tenth of the
                    // count for a readable margin: 20 ± 2.
                    : i at5 ( cal_flagged_at cv ( cal_margin_for_rate cv 0.05 ) )
                    ( check & >= at5 18 <= at5 22 `calibrate: margin for 5 % flags 20 (±2)` )
                    ( check == ( cal_flagged_at cv ( cal_margin_for_rate cv 0.0 ) ) 0 `calibrate: margin for 0 % flags none` )
                    ( check >= ( cal_margin_for_rate cv 0.05 ) 0.0 `calibrate: margins never go negative` )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check cal_ae `calibrate: the autoencoder is in the report` )
    ( cal_free cal )

    ( model_free mo )
    ( store_free st )
    ( string_free root )
    ( nurl_print `scan_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
