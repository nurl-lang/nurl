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
@ ingest_temp *Model mo f temp i at → v {
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

@ probe_temp *Model mo f temp → ProbeOut {
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
    : b m1 ( model_set_margin mo `short_term` 0.5 )
    : b m2 ( model_set_margin mo `daily` 0.5 )
    : b m3 ( model_set_margin mo `weekly` 0.5 )
    : b m4 ( model_set_margin mo `seasonal` 0.5 )
    : b m5 ( model_set_margin mo `timevector` 0.5 )

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
    : ProbeOut all5 ( probe_temp mo 23.0 )
    ( check == . all5 hits 5 `agg: all tight margins -> 5 versions flag` )
    ( check <= . all5 score . all5 df_short `agg: aggregate score is the most severe` )

    // Fine-tune from loose margins: the worst observed point must cross.
    : b r1 ( model_set_margin mo `short_term` 0.5 )
    : b r2 ( model_set_margin mo `daily` 0.5 )
    : b r3 ( model_set_margin mo `weekly` 0.5 )
    : b r4 ( model_set_margin mo `seasonal` 0.5 )
    : b r5 ( model_set_margin mo `timevector` 0.5 )

    : FineTuneReport rep ( model_finetune mo )
    ( check == ( vec_len [FtVer] . rep items ) 5 `finetune: 5 versions tuned` )
    : ~ b margins_tightened T
    : ~ b formula_holds T
    : i ni ( vec_len [FtVer] . rep items )
    : ~ i q 0
    ~ < q ni {
        ?? ( vec_get [FtVer] . rep items q ) {
            T ft → {
                ? < . ft new_margin . ft old_margin {} { = margins_tightened F }
                ? < ( float_abs - . ft new_margin * ( float_abs . ft min_score ) 0.95 ) 0.0000001 {} { = formula_holds F }
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check margins_tightened `finetune: margins move toward the data` )
    ( check formula_holds `finetune: margin = 0.95 * |worst score|` )

    // The worst ring point (the 23.0 outlier) now crosses; normals don't.
    : ProbeOut post ( probe_temp mo 23.0 )
    ( check . post anomaly `finetune: worst observed point crosses the margin` )
    : ProbeOut norm ( probe_temp mo 20.0 )
    ( check == . norm anomaly F `finetune: normal point still normal` )

    ( finetune_free rep )
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
