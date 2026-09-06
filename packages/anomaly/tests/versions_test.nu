// versions_test.nu — M5 tests: multi-version behaviour.
//   routing   — versions train on their own time windows: after a step
//               change, short_term (window 180 min) knows only the new
//               regime while daily/seasonal remember the old one, so the
//               same probe scores very differently per version.
//   aggregate — the any-version-OR truth table, driven through margins.
//   finetune  — margins recalibrate to 95% of the worst observed score;
//               the worst ring point then crosses the threshold, normal
//               points still don't.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_ver_test).

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
$ `src/store.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000
: ~ i g_lcg 1

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

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

@ gauss3 → f {
    ^ - + + ( lcg_u01 ) ( lcg_u01 ) ( lcg_u01 ) 1.5
}

// Ingest a single-feature {"temp": t} point at absolute time `at`.
@ ingest_temp * Model mo f temp i at → v {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    ?? r {
        T vd → { ( verdict_free vd ) }
        F e → { ( string_free e ) }
    }
}

// detect_only a {"temp": t} probe; caller owns the returned Verdict.
// (`ok` false means the call errored.)
: ProbeOut {
    b ok
    b anomaly
    f score
    i hits
    f df_short
    f df_daily
    f df_seasonal
}

@ probe_temp * Model mo f temp → ProbeOut {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    : !Verdict String r ( model_detect_only mo j )
    ( json_free j )
    ?? r {
        T vd → {
            : ~ i hits 0
            : ~ f dsh 999.0
            : ~ f dda 999.0
            : ~ f dse 999.0
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        ? . vv anomaly { = hits + hits 1 } {}
                        : s vn ( string_data . vv vvname )
                        ? == ( nurl_str_eq vn `short_term` ) 1 { = dsh . vv score } {}
                        ? == ( nurl_str_eq vn `daily` ) 1 { = dda . vv score } {}
                        ? == ( nurl_str_eq vn `seasonal` ) 1 { = dse . vv score } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            : ProbeOut out @ ProbeOut { T . vd anomaly . vd score hits dsh dda dse }
            ( verdict_free vd )
            ^ out
        }
        F e → {
            ( string_free e )
            ^ @ ProbeOut { F F 0.0 0 999.0 999.0 999.0 }
        }
    }
}

// ── Scenario 1: per-window routing ────────────────────────────────────
//
// 20 points of an OLD regime (temp ≈ 20) six+ hours ago, then 10 points of
// a NEW regime (temp ≈ 40) within the last few minutes. At the final train,
// short_term's 180-minute window sees only the new regime; daily/seasonal
// see both. A probe from the old regime is alien to short_term but familiar
// to the long windows.

@ test_routing Store st → v {
    = g_lcg 1
    : i NOW + T0 * 400 60
    : *Model mo ( model_open_at st `routing` T0 )
    ( model_set_limits mo 10 150000 )
    ( model_set_schedule mo 10 1000 )

    : ~ i k 1
    ~ <= k 20 {
        ( ingest_temp mo + 20.0 ( gauss3 ) + T0 * k 60 )
        = k + k 1
    }
    : ~ i j 1
    ~ <= j 10 {
        ( ingest_temp mo + 40.0 ( gauss3 ) - NOW * - 10 j 60 )
        = j + j 1
    }
    ( check ( model_is_trained mo ) `routing: trained` )
    : *Meta mm ( model_metadata mo )
    ( check == . mm last_trained 30 `routing: final train at 30` )

    // Old-regime probe: alien to short_term, familiar to the long windows.
    : ProbeOut p20 ( probe_temp mo 20.0 )
    ( check . p20 ok `routing: probe scored` )
    ( check < . p20 df_short - . p20 df_daily 0.05 `routing: short_term finds old regime alien (daily does not)` )
    ( check < . p20 df_short - . p20 df_seasonal 0.05 `routing: short_term finds old regime alien (seasonal does not)` )
    // New-regime probe: fine everywhere (short_term trained on it).
    : ProbeOut p40 ( probe_temp mo 40.0 )
    ( check > . p40 df_short -0.12 `routing: new regime familiar to short_term` )

    ( model_free mo )
}

// ── Scenario 2: aggregation truth table + fine-tune ───────────────────

@ test_aggregate_finetune Store st → v {
    = g_lcg 7
    : *Model mo ( model_open_at st `agg` T0 )
    ( model_set_limits mo 10 150000 )
    ( model_set_schedule mo 10 1000 )
    // The sliding-window timevector needs the window to fit in this tiny
    // ring — 6 points keeps all five versions in play.
    : b mw ( model_set_version_window mo `timevector` 6 1 )
    : b m1 ( model_set_margin mo `short_term` 0.5 )
    : b m2 ( model_set_margin mo `daily` 0.5 )
    : b m3 ( model_set_margin mo `weekly` 0.5 )
    : b m4 ( model_set_margin mo `seasonal` 0.5 )
    : b m5 ( model_set_margin mo `timevector` 0.5 )
    // The range guard counts in sigmas, and 23.0 on a ±0.5 stream is six
    // of them: "loose" for it is a hundred.
    : b m6 ( model_set_margin mo ANOM_GUARD_NAME 100.0 )

    // 19 normal points (temp ≈ 20 ± .5) and one mild outlier (23.0).
    : ~ i k 1
    ~ <= k 20 {
        : ~ f temp + 20.0 * ( gauss3 ) 0.5
        ? == k 15 { = temp 23.0 } {}
        ( ingest_temp mo temp + T0 * k 60 )
        = k + k 1
    }
    ( check ( model_is_trained mo ) `agg: trained` )

    // Truth table: margins decide, aggregate is OR over versions.
    : ProbeOut loose ( probe_temp mo 23.0 )
    ( check == . loose anomaly F `agg: all margins loose -> normal` )
    ( check == . loose hits 0 `agg: 0 versions flag` )

    : b t1 ( model_set_margin mo `short_term` 0.01 )
    : ProbeOut one ( probe_temp mo 23.0 )
    ( check . one anomaly `agg: one tight margin -> anomaly` )
    ( check == . one hits 1 `agg: exactly 1 version flags` )

    : b t2 ( model_set_margin mo `daily` 0.01 )
    : b t3 ( model_set_margin mo `weekly` 0.01 )
    : b t4 ( model_set_margin mo `seasonal` 0.01 )
    : b t5 ( model_set_margin mo `timevector` 0.01 )
    : b t6 ( model_set_margin mo ANOM_GUARD_NAME 0.01 )
    : ProbeOut all5 ( probe_temp mo 23.0 )
    ( check == . all5 hits 6 `agg: all tight margins -> 6 versions flag` )
    ( check <= . all5 score . all5 df_short `agg: aggregate score is the most severe` )

    // Fine-tune from loose margins: a 5 % target on a 20-point ring is
    // one point per version — the worst one, sitting exactly on the line.
    : b r1 ( model_set_margin mo `short_term` 0.5 )
    : b r2 ( model_set_margin mo `daily` 0.5 )
    : b r3 ( model_set_margin mo `weekly` 0.5 )
    : b r4 ( model_set_margin mo `seasonal` 0.5 )
    : b r5 ( model_set_margin mo `timevector` 0.5 )
    : b r6 ( model_set_margin mo ANOM_GUARD_NAME 100.0 )
    : ( Vec String ) none ( vec_new [String] )

    // Dry run first: the report is complete, nothing is written.
    : FineTuneReport dry ( model_finetune_at mo 0.05 0 0 F none )
    ( check == ( vec_len [FtVer] . dry items ) 6 `finetune dry: 6 versions reported` )
    ( check == . dry applied F `finetune dry: report says not applied` )
    : ~ b dry_untouched T
    : ~ i q 0
    ~ < q ( vec_len [FtVer] . dry items ) {
        ?? ( vec_get [FtVer] . dry items q ) {
            T ft → {
                ? . ft applied { = dry_untouched F } {}
                ? == ( meta_version_margin ( model_metadata mo ) ( string_data . ft ftname ) -1.0 ) . ft old_margin {} { = dry_untouched F }
                ? | == . ft old_margin 0.5 == . ft old_margin 100.0 {} { = dry_untouched F }
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check dry_untouched `finetune dry: margins untouched` )
    ( finetune_free dry )

    : FineTuneReport rep ( model_finetune_at mo 0.05 0 0 T none )
    ( vec_free [String] none )
    ( check == ( vec_len [FtVer] . rep items ) 6 `finetune: 6 versions tuned` )
    ( check == . rep n_rows 20 `finetune: whole ring in the window` )
    : ~ b margins_tightened T
    : ~ b one_each T
    : ~ b short_numbers T
    : ~ b all_applied T
    : i ni ( vec_len [FtVer] . rep items )
    = q 0
    ~ < q ni {
        ?? ( vec_get [FtVer] . rep items q ) {
            T ft → {
                ? < . ft new_margin . ft old_margin {} { = margins_tightened F }
                ? == . ft after 1 {} { = one_each F }
                ? == ( round_sig . ft new_margin 6 ) . ft new_margin {} { = short_numbers F }
                ? . ft applied {} { = all_applied F }
                ? == ( meta_version_margin ( model_metadata mo ) ( string_data . ft ftname ) -1.0 ) . ft new_margin {} { = all_applied F }
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check margins_tightened `finetune: margins move toward the data` )
    ( check one_each `finetune: 5 % of 20 points = exactly one flagged per version` )
    ( check short_numbers `finetune: margins carry at most 6 significant digits` )
    ( check all_applied `finetune: every margin written to the metadata` )

    // The worst ring point (the 23.0 outlier) now crosses; normals don't.
    : ProbeOut post ( probe_temp mo 23.0 )
    ( check . post anomaly `finetune: worst observed point crosses the margin` )
    : ProbeOut norm ( probe_temp mo 20.0 )
    ( check == . norm anomaly F `finetune: normal point still normal` )

    // Rate 0: the margin sits just above the worst point, nothing flags.
    : ( Vec String ) none2 ( vec_new [String] )
    : FineTuneReport zero ( model_finetune_at mo 0.0 0 0 T none2 )
    ( vec_free [String] none2 )
    : ~ b none_flag T
    = q 0
    ~ < q ( vec_len [FtVer] . zero items ) {
        ?? ( vec_get [FtVer] . zero items q ) {
            T ft → { ? == . ft after 0 {} { = none_flag F } }
            F _ → {}
        }
        = q + q 1
    }
    ( check none_flag `finetune: rate 0 flags nothing` )
    : ProbeOut post0 ( probe_temp mo 23.0 )
    ( check == . post0 anomaly F `finetune: rate 0 clears the worst point` )
    ( finetune_free zero )

    // Labels: the worst stored row called a false positive drops out of
    // calibration, so rate 0 — "flag nothing you have seen" — no longer
    // makes room for it: the margin lands on the worst of the rest and
    // 23.0 crosses again.
    : ScanOut lsc ( model_scan_at mo 0 0 0 F )
    : ~ i worst_idx -1
    : ~ f worst_sev -1.0
    : ~ i lk 0
    ~ < lk ( vec_len [ScoredPt] . lsc pts ) {
        ?? ( vec_get [ScoredPt] . lsc pts lk ) {
            T r → { ? > . r sp_severity worst_sev { = worst_sev . r sp_severity = worst_idx . r sp_idx } {} }
            F _ → {}
        }
        = lk + lk 1
    }
    ( scan_free lsc )
    ( check >= worst_idx 0 `labels: the scan names a worst row` )
    ( check == ( model_label_point mo worst_idx `nonsense` `t` `` 1 ) -2 `labels: an unknown label is refused` )
    ( check == ( model_label_point mo 999 ANOM_LABEL_FP `t` `` 1 ) -1 `labels: an index outside the ring is refused` )
    : i lseq ( model_label_point mo worst_idx ANOM_LABEL_FP `tester` `sensor was being cleaned` 1700000000 )
    ( check == lseq + ( model_seq_base mo ) worst_idx `labels: the label is keyed by lifetime sequence` )
    : ( Vec Label ) ls ( model_labels mo )
    ( check == ( vec_len [Label] ls ) 1 `labels: one label in force` )
    : ( Vec i ) lmap ( model_label_map mo ls )
    ( check == ( _mlp_iget lmap worst_idx ) 0 `labels: the map points the row at its label` )
    ( check ( _an_label_is ls ( _mlp_iget lmap worst_idx ) ANOM_LABEL_FP ) `labels: and it reads false_positive` )
    ( vec_free [i] lmap )
    ( labels_free ls )
    : CalReport lcal ( model_calibrate mo 0 0 )
    ( check == . lcal excluded 1 `labels: calibration leaves the false positive out` )
    ( check == . lcal n_rows 19 `labels: and scores the other nineteen` )
    ( cal_free lcal )
    : ( Vec String ) none3 ( vec_new [String] )
    : FineTuneReport zero2 ( model_finetune_at mo 0.0 0 0 T none3 )
    ( check == . zero2 excluded 1 `labels: the fine-tune report counts the exclusion` )
    ( finetune_free zero2 )
    ( vec_free [String] none3 )
    : ProbeOut post1 ( probe_temp mo 23.0 )
    ( check . post1 anomaly `labels: a false positive no longer pays for the margin` )
    : i lseq2 ( model_label_point mo worst_idx ANOM_LABEL_NONE `tester` `` 1700000001 )
    ( check == lseq2 lseq `labels: none is written under the same sequence` )
    : ( Vec Label ) ls2 ( model_labels mo )
    ( check == ( vec_len [Label] ls2 ) 0 `labels: none withdraws the label` )
    ( labels_free ls2 )
    : i lseq3 ( model_label_point mo worst_idx ANOM_LABEL_OK `tester` `` 1700000002 )
    ( model_reset mo )
    : ( Vec Label ) ls3 ( model_labels mo )
    ( check == ( vec_len [Label] ls3 ) 0 `labels: a reset drops the labels with the ring` )
    ( labels_free ls3 )

    ( finetune_free rep )
    ( model_free mo )
}

// ── Scenario 3: the flatline guard ────────────────────────────────────
//
// 300 minutes of a temperature at 0.1 ° resolution riding a slow wave,
// a pressure with fine noise, and a rain gauge that reads 0.0 nine
// minutes in ten. Then the temperature sticks for 70 minutes: the run of
// identical readings passes nine tenths of the reference (the window, 60,
// as the training runs were short) and the flatline guard names `temp`.
// Later the pressure sensor hangs with a hair of dither: no two readings
// identical, but the window's spread collapses below a tenth of the
// stream's quietest windows, and the guard names `press`. The rain gauge
// sat flat through training and is never blamed for it.

: FlatProbe {
    b seen  // the flatline gave a verdict
    b anomaly
    f score
    String feat
}

@ flat_ingest * Model mo f temp f press f rain i at → FlatProbe {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    ( json_obj_set j `press` ( json_float press ) )
    ( json_obj_set j `rain` ( json_float rain ) )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    : ~ FlatProbe out @ FlatProbe { F F 0.0 ( string_new ) }
    ?? r {
        T vd → {
            : *Meta mm ( model_metadata mo )
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        ? ( _an_is_flat_name ( string_data . vv vvname ) ) {
                            = . out seen T
                            = . out anomaly . vv anomaly
                            = . out score . vv score
                            ? >= . vv vv_feat 0 {
                                ?? ( vec_get [String] . mm feats . vv vv_feat ) {
                                    T fn → { ( string_push_str . out feat ( string_data fn ) ) }
                                    F _ → {}
                                }
                            } {}
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( verdict_free vd )
        }
        F e → { ( string_free e ) }
    }
    ^ out
}

@ tenths f x → f { ^ / ( float_round * x 10.0 ) 10.0 }

// The gauge's habit: dry nine minutes in ten.
@ rain_now → f { ^ ? < ( lcg_u01 ) 0.9 0.0 ( tenths * 3.0 ( lcg_u01 ) ) }

@ test_flatline Store st → v {
    = g_lcg 11
    : *Model mo ( model_open_at st `flat` T0 )
    ( model_set_limits mo 10 150000 )
    ( model_set_schedule mo 100000 100000 )
    : ~ i k 0
    : ~ f last_temp 0.0
    ~ < k 300 {
        : f wave * 5.0 ( sin / # f k 20.0 )
        = last_temp ( tenths + + 20.0 wave * 0.3 ( gauss3 ) )
        : FlatProbe fp ( flat_ingest mo last_temp + 1000.0 ( gauss3 ) ( rain_now ) + T0 * k 60 )
        ( string_free . fp feat )
        = k + k 1
    }
    : i tr ( model_force_train_at mo + T0 * 300 60 )
    ( check > tr 0 `flatline: trained` )
    : *Meta mm ( model_metadata mo )
    ( check == ( vec_len [f] . mm flat_sd ) ( vec_len [String] . mm feats ) `flatline: one reference per feature` )
    ( check ( meta_version_enabled mm ANOM_FLAT_NAME F ) `flatline: the version exists and is on` )
    ( check == ( meta_version_margin mm ANOM_FLAT_NAME 0.0 ) ANOM_FLAT_MARGIN `flatline: default margin` )

    // The references round-trip through the metadata JSON.
    : String js ( meta_to_json_str mm )
    ?? ( meta_from_json_str ( string_data js ) ) {
        T m2 → {
            ( check == ( vec_len [f] . m2 flat_run ) ( vec_len [f] . mm flat_run ) `flatline: references survive the JSON round trip` )
            ( meta_free m2 )
        }
        F _ → { ( check F `flatline: metadata parses back` ) }
    }
    ( string_free js )

    // A normal minute: the guard judges and stays quiet.
    : FlatProbe p0 ( flat_ingest mo ( tenths + 20.0 * 0.3 ( gauss3 ) ) + 1000.0 ( gauss3 ) ( rain_now ) + T0 * 300 60 )
    ( check . p0 seen `flatline: a verdict on a normal minute` )
    ( check ! . p0 anomaly `flatline: quiet on a normal minute` )
    ( string_free . p0 feat )

    // The temperature sticks.
    : ~ FlatProbe pa @ FlatProbe { F F 0.0 ( string_new ) }
    = k 0
    ~ < k 70 {
        ( string_free . pa feat )
        = pa ( flat_ingest mo 20.0 + 1000.0 ( gauss3 ) ( rain_now ) + T0 * + 301 k 60 )
        = k + k 1
    }
    ( check . pa anomaly `flatline: 70 identical readings are flagged` )
    ( check == ( nurl_str_eq ( string_data . pa feat ) `temp` ) 1 `flatline: and the guard names temp` )
    ( check <= . pa score -0.9 `flatline: the fraction is past the line` )
    ( string_free . pa feat )

    // Back to life for a window's worth, then the pressure hangs with dither.
    = k 0
    ~ < k 70 {
        : f wave * 5.0 ( sin / # f k 20.0 )
        : FlatProbe fp ( flat_ingest mo ( tenths + + 20.0 wave * 0.3 ( gauss3 ) ) + 1000.0 ( gauss3 ) ( rain_now ) + T0 * + 371 k 60 )
        ? == k 69 { ( check ! . fp anomaly `flatline: quiet again once the window has moved` ) } {}
        ( string_free . fp feat )
        = k + k 1
    }
    : ~ FlatProbe pb @ FlatProbe { F F 0.0 ( string_new ) }
    = k 0
    ~ < k 70 {
        ( string_free . pb feat )
        : f wave * 5.0 ( sin / # f + 70 k 20.0 )
        = pb ( flat_ingest mo ( tenths + + 20.0 wave * 0.3 ( gauss3 ) ) + 1000.0 * 0.001 ( gauss3 ) ( rain_now ) + T0 * + 441 k 60 )
        = k + k 1
    }
    ( check . pb anomaly `flatline: a dithering stuck sensor is flagged` )
    ( check == ( nurl_str_eq ( string_data . pb feat ) `press` ) 1 `flatline: and the guard names press` )
    ( string_free . pb feat )

    // Fine-tune leaves the flatline's margin alone.
    : ( Vec String ) none ( vec_new [String] )
    : FineTuneReport ft ( model_finetune_at mo 0.05 0 0 T none )
    ( vec_free [String] none )
    : ~ b listed F
    = k 0
    ~ < k ( vec_len [FtVer] . ft items ) {
        ?? ( vec_get [FtVer] . ft items k ) {
            T it → { ? ( _an_is_flat_name ( string_data . it ftname ) ) { = listed T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( finetune_free ft )
    ( check ! listed `flatline: finetune does not list it` )
    ( check == ( meta_version_margin mm ANOM_FLAT_NAME 0.0 ) ANOM_FLAT_MARGIN `flatline: and its margin stands` )

    ( model_free mo )
}

@ main → i {
    : ~ String root ( string_from `./anomaly_ver_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    ( test_routing st )
    ( test_aggregate_finetune st )
    ( test_flatline st )

    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `versions_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
