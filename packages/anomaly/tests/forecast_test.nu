// forecast_test.nu — the forecast version (src/forecast.nu).
//
//   A temperature that rides a 24-row rhythm with noise, and a pressure
//   that wanders. After a train with the version on, every numeric
//   feature has a model; a point whose temperature is an ordinary value
//   at the wrong moment — inside the training range, on the wrong side
//   of the cycle — is flagged by the forecast and named, while the
//   forests, which see values and not order, let it through (the
//   contextual anomaly is what this version exists for). A reading the
//   point leaves out is a gap: no verdict for it, the model moves on.
//   detect_only leaves the states alone; a scan over the stored rows
//   agrees with the live verdicts; a model reopened from the store
//   carries on from its saved states; JSON round-trips; reset drops it.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_fc_test).

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
$ `src/forecast.nu`
$ `src/store.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000
: ~ i g_lcg 7

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        = g_pass + g_pass 1
        ( nurl_print `ok ` )
    } {
        = g_fail + g_fail 1
        ( nurl_print `FAIL ` )
    }
    ( pline label )
}

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

@ gauss3 → f {
    ^ * 1.7320508 - + + ( lcg_u01 ) ( lcg_u01 ) ( lcg_u01 ) 1.5
}

// The stream: temperature = 20 + 5 sin(2πk/24) + 0.3 noise, pressure a
// slow walk with noise, a rain gauge mostly dry.
@ temp_at i k → f { ^ + 20.0 * 5.0 ( sin / * 6.283185307179586 # f k 24.0 ) }

: Probe {
    b seen
    b anomaly
    f score
    String feat
    b forest_hit  // any forest version flagged it
}

@ probe_of * Model mo ! Verdict String r → Probe {
    : ~ Probe out @ Probe { F F 0.0 ( string_new ) F }
    ?? r {
        T vd → {
            : *Meta mm ( model_metadata mo )
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        : s nm ( string_data . vv vvname )
                        ? ( _an_is_fc_name nm ) {
                            = . out seen T
                            = . out anomaly . vv anomaly
                            = . out score . vv score
                            ? >= . vv vv_feat 0 {
                                ?? ( vec_get [String] . mm feats . vv vv_feat ) {
                                    T fn → { ( string_push_str . out feat ( string_data fn ) ) }
                                    F _ → {}
                                }
                            } {}
                        } {
                            ? & ! ( _an_forestless_name nm ) . vv anomaly { = . out forest_hit T } {}
                        }
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

@ point_json f temp f press b with_temp → Json {
    : Json j ( json_obj_new )
    ? with_temp { ( json_obj_set j `temp` ( json_float temp ) ) } {}
    ( json_obj_set j `press` ( json_float press ) )
    ^ j
}

@ ingest * Model mo f temp f press i at → Probe {
    : Json j ( point_json temp press T )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    ^ ( probe_of mo r )
}

@ main → i {
    : ~ String root ( string_from `./anomaly_fc_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    : *Model mo ( model_open_at st `fc` T0 )
    ( model_set_limits mo 10 150000 )
    ( model_set_schedule mo 100000 100000 )
    : ~ f press 1000.0
    : ~ i k 0
    ~ < k 480 {
        = press + press * 0.05 ( gauss3 )
        : Probe p ( ingest mo + ( temp_at k ) * 0.3 ( gauss3 ) press + T0 * k 60 )
        ( string_free . p feat )
        = k + k 1
    }
    // the version is off by default: a train leaves it untrained
    : i tr0 ( model_force_train_at mo + T0 * 480 60 )
    ( check > tr0 0 `forecast: the model trains` )
    : *Meta mm ( model_metadata mo )
    ( check >= ( meta_find_version mm ANOM_FC_NAME ) 0 `forecast: the version exists` )
    ( check ! ( meta_version_enabled mm ANOM_FC_NAME T ) `forecast: and is off by default` )
    ( check ! . . mo fc trained `forecast: off means untrained` )
    ( check == ( meta_version_margin mm ANOM_FC_NAME 0.0 ) ANOM_FC_SIGMA `forecast: default margin is the sigma count` )

    // train it with the daily season
    : b _w ( model_set_version_window mo ANOM_FC_NAME 24 0 )
    : String err ( model_train_forecast_at mo + T0 * 480 60 )
    ( check == ( string_len err ) 0 `forecast: explicit training succeeds` )
    ( string_free err )
    ( check ( meta_version_enabled mm ANOM_FC_NAME F ) `forecast: training switches the version on` )
    : *FcModel fc ( model_forecast mo )
    ( check . fc trained `forecast: trained` )
    ( check == . fc nw 2 `forecast: one model per numeric feature (temp, press)` )
    ( check == . fc season 24 `forecast: with the season given` )
    ( check == . fc pos 480 `forecast: the states stand at the ring's end` )
    : ~ b named T
    ?? ( vec_get [String] . fc feats 0 ) { T f0 → { ? == ( nurl_str_eq ( string_data f0 ) `temp` ) 1 {} { = named F } } F _ → { = named F } }
    ( check named `forecast: the first watched feature is temp` )
    : *ArimaModel am0 ( model_forecast_model mo 0 )
    : ArimaSpec sp0 ( arima_spec_of am0 )
    ( check | | > . sp0 P 0 > . sp0 Q 0 > . am0 xk 0 `forecast: the temperature's model is seasonal (a polynomial or Fourier terms)` )
    : ~ b selected F
    ?? ( vec_get [String] . fc sel 0 ) { T sn → { = selected > ( string_len sn ) 0 } F _ → {} }
    ( check selected `forecast: the holdout chose a form and named it` )
    ( check < ( _fc_getf . fc sel_mae 0 ) ( _fc_getf . fc sel_naive 0 ) `forecast: the chosen form beats the naive forecast on the holdout` )

    // normal points: quiet
    : ~ b quiet T
    : ~ b seen T
    = k 480
    ~ < k 510 {
        = press + press * 0.05 ( gauss3 )
        : Probe p ( ingest mo + ( temp_at k ) * 0.3 ( gauss3 ) press + T0 * k 60 )
        ? . p seen {} { = seen F }
        ? . p anomaly { = quiet F } {}
        ( string_free . p feat )
        = k + k 1
    }
    ( check seen `forecast: a verdict on every normal point` )
    ( check quiet `forecast: and quiet on them` )
    ( check == . fc pos 510 `forecast: every ingested point absorbed` )

    // the contextual anomaly: k=510 is the cycle's top (510/24 = 21.25, sin = 1, temp 25);
    // a reading of 15.5 is an ordinary trough value — inside the training range — at the wrong moment
    = press + press * 0.05 ( gauss3 )
    : Probe pa ( ingest mo 15.5 press + T0 * 510 60 )
    ( check . pa seen `forecast: the contextual point gets a verdict` )
    ( check . pa anomaly `forecast: an ordinary value at the wrong moment is flagged` )
    ( check == ( nurl_str_eq ( string_data . pa feat ) `temp` ) 1 `forecast: and the version names temp` )
    ( check <= . pa score -4.0 `forecast: the reading sits past the sigma line` )
    ( check ! . pa forest_hit `forecast: the forests, which see values and not order, let it through` )
    ( string_free . pa feat )

    // a gap: the point without a temperature — no verdict for temp, the pressure still judged
    : Json jg ( point_json 0.0 press F )
    : !Verdict String rg ( model_ingest_at mo jg + T0 * 511 60 )
    ( json_free jg )
    : Probe pg ( probe_of mo rg )
    ( check . pg seen `forecast: a point missing a feature still gets a verdict from the others` )
    ( check ! == ( nurl_str_eq ( string_data . pg feat ) `temp` ) 1 `forecast: the missing reading is a gap, not a zero` )
    ( string_free . pg feat )
    ( check == . fc pos 512 `forecast: the gap counts as a step` )

    // detect_only: no state change
    : i pos_before . fc pos
    : Json jd ( point_json ( temp_at 512 ) press T )
    : !Verdict String rd ( model_detect_only mo jd )
    ( json_free jd )
    : Probe pd ( probe_of mo rd )
    ( check . pd seen `forecast: detect_only judges` )
    ( check ! . pd anomaly `forecast: detect_only quiet on a normal reading` )
    ( check == . fc pos pos_before `forecast: detect_only leaves the states alone` )
    ( string_free . pd feat )

    // the JSON round trip is exact
    : String j1 ( fc_to_json_str fc )
    ?? ( fc_from_json_str ( string_data j1 ) ) {
        T fc2 → {
            : String j2 ( fc_to_json_str fc2 )
            ( check ( string_eq j1 j2 ) `forecast: JSON round trip is exact` )
            ( string_free j2 )
            ( fc_free fc2 )
        }
        F _ → { ( check F `forecast: JSON parses back` ) }
    }
    ( string_free j1 )

    // the scan over the stored rows agrees with the live verdicts
    : ScanOut so ( model_scan_at mo + T0 * 480 60 + T0 * 513 60 0 T )
    : ~ i bit -1
    : ~ i q 0
    ~ < q ( vec_len [String] . so vnames ) { ?? ( vec_get [String] . so vnames q ) { T nm → { ? ( _an_is_fc_name ( string_data nm ) ) { = bit q } {} } F _ → {} } = q + q 1 }
    ( check >= bit 0 `forecast: the scan lists the version` )
    : ~ b scan_flag F
    : ~ i scan_hits 0
    : ~ i scan_seen 0
    : i nsp ( vec_len [ScoredPt] . so pts )
    = q 0
    ~ < q nsp {
        ?? ( vec_get [ScoredPt] . so pts q ) {
            T r → {
                ? & >= bit 0 != & . r sp_present << 1 bit 0 { = scan_seen + scan_seen 1 } {}
                ? & >= bit 0 != & . r sp_flagged << 1 bit 0 {
                    = scan_hits + scan_hits 1
                    ? == . r sp_idx 510 { = scan_flag T } {}
                } {}
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check == scan_seen nsp `forecast: the scan has a forecast verdict on every row` )
    ( check scan_flag `forecast: the scan flags the contextual point` )
    ( check == scan_hits 1 `forecast: and nothing else in the window` )
    ( scan_free so )

    // reopen: the states carry on from the file (saved at the train,
    // caught up from the ring on the next judgement)
    ( model_free mo )
    : *Model mo2 ( model_open_at st `fc` + T0 * 512 60 )
    : *FcModel fcb ( model_forecast mo2 )
    ( check . fcb trained `forecast: reopened trained` )
    ( check == . fcb pos 512 `forecast: the file stands at the last save (the train, then every 32 rows absorbed)` )
    = press + press * 0.05 ( gauss3 )
    : Probe pr ( ingest mo2 + ( temp_at 512 ) * 0.3 ( gauss3 ) press + T0 * 512 60 )
    ( check . pr seen `forecast: judges after a reopen` )
    ( check ! . pr anomaly `forecast: quiet after a reopen` )
    ( check == . fcb pos 513 `forecast: caught up with the ring before judging` )
    ( string_free . pr feat )

    // the forecast itself: the next row is 513 (23.5 on the cycle)
    ( model_forecast_sync mo2 )
    : FcForecast ff ( fc_forecast fcb 3 )
    ( check == ( vec_len [String] . ff feats ) 2 `forecast: a forecast per watched feature` )
    : ~ f m0 0.0
    ?? ( vec_get [( Vec f )] . ff mean 0 ) { T mv → { = m0 ( _fc_getf mv 0 ) } F _ → {} }
    ( check < ( float_abs - m0 ( temp_at 513 ) ) 1.5 `forecast: the next temperature is forecast near the cycle` )
    ( fc_forecast_free ff )
    : Json info ( fc_info_json fcb )
    ( check == ( _an_jint info `training_data_points` 0 ) 480 `forecast: the info block carries the fit size` )
    ( json_free info )

    : Probe pr2 ( ingest mo2 15.5 press + T0 * 513 60 )
    ( check . pr2 anomaly `forecast: still catches the contextual point after a reopen` )
    ( string_free . pr2 feat )

    // the forecast as the API answers it: times from the ring's step, intervals
    ( check == ( model_step mo2 ) 60 `forecast: the ring's step is a minute` )
    : Json fj ( model_forecast_json mo2 3 )
    ( check == ( _an_jint fj `step_seconds` 0 ) 60 `forecast: the answer carries the step` )
    : ~ i t1 0
    ?? ( json_obj_get fj `times` ) { T ta → { ?? ( json_arr_get ta 0 ) { T e → { = t1 ( json_as_int e ) } F _ → {} } } F _ → {} }
    ( check == t1 + ( model_last_ts mo2 ) 60 `forecast: the first step's time is the newest point's plus the step` )
    : ~ b bands F
    ?? ( json_obj_get fj `forecasts` ) {
        T fa → {
            ?? ( json_arr_get fa 0 ) {
                T f0 → {
                    : ~ f lo 0.0 : ~ f m 0.0 : ~ f hi 0.0
                    ?? ( json_obj_get f0 `lo95` ) { T a → { ?? ( json_arr_get a 0 ) { T e → { ?? ( json_num_as_f e ) { T x → { = lo x } F _ → {} } } F _ → {} } } F _ → {} }
                    ?? ( json_obj_get f0 `mean` ) { T a → { ?? ( json_arr_get a 0 ) { T e → { ?? ( json_num_as_f e ) { T x → { = m x } F _ → {} } } F _ → {} } } F _ → {} }
                    ?? ( json_obj_get f0 `hi95` ) { T a → { ?? ( json_arr_get a 0 ) { T e → { ?? ( json_num_as_f e ) { T x → { = hi x } F _ → {} } } F _ → {} } } F _ → {} }
                    = bands & < lo m < m hi
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check bands `forecast: the 95 % interval brackets the mean` )
    ( json_free fj )

    // measured: over the last 60 origins the model beats carrying the last value forward
    : Json bt ( model_forecast_backtest mo2 6 60 )
    ( check == ( _an_jint bt `origins` 0 ) 60 `backtest: sixty origins` )
    : ~ f skill -1.0
    : ~ f cov 0.0
    ?? ( json_obj_get bt `features` ) {
        T fa → {
            ?? ( json_arr_get fa 0 ) {
                T f0 → {
                    ?? ( json_obj_get f0 `skill_vs_naive` ) { T e → { ?? ( json_num_as_f e ) { T x → { = skill x } F _ → {} } } F _ → {} }
                    ?? ( json_obj_get f0 `coverage95` ) { T a → { ?? ( json_arr_get a 0 ) { T e → { ?? ( json_num_as_f e ) { T x → { = cov x } F _ → {} } } F _ → {} } } F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check > skill 0.3 `backtest: the seasonal model beats the naive forecast on the rhythm` )
    ( check > cov 0.7 `backtest: the 95 % interval holds most one-step readings` )
    ( json_free bt )
    : Json bt0 ( model_forecast_backtest mo2 6 100000 )
    ( check > ( _an_jint bt0 `origins` 0 ) 0 `backtest: more origins than rows is clamped, not refused` )
    ( json_free bt0 )

    // muted while disabled: no verdict, the models kept
    : b _off ( model_set_version_enabled mo2 ANOM_FC_NAME F )
    : Probe pm ( ingest mo2 + ( temp_at 514 ) * 0.3 ( gauss3 ) press + T0 * 514 60 )
    ( check ! . pm seen `forecast: no verdict while the version is off` )
    ( check . fcb trained `forecast: the models are kept while off` )
    ( check == . fcb pos 514 `forecast: nothing absorbed while off` )
    ( string_free . pm feat )
    : b _on ( model_set_version_enabled mo2 ANOM_FC_NAME T )
    : Probe pn ( ingest mo2 + ( temp_at 515 ) * 0.3 ( gauss3 ) press + T0 * 515 60 )
    ( check . pn seen `forecast: judging again once on` )
    ( check == . fcb pos 516 `forecast: the rows ingested while off were caught up` )
    ( string_free . pn feat )

    // a model whose forecast version is untrained: the ensure fits it, the season from the step
    : *Model mo3 ( model_open_at st `ensure` T0 )
    ( model_set_limits mo3 10 150000 )
    ( model_set_schedule mo3 100000 100000 )
    : String e0 ( model_forecast_ensure_at mo3 T0 )
    ( check > ( string_len e0 ) 0 `ensure: an untrained model has no forecast, and says so` )
    ( string_free e0 )
    = k 0
    ~ < k 200 {
        : Probe p ( ingest mo3 + ( temp_at k ) * 0.3 ( gauss3 ) 1000.0 + T0 * k 3600 )
        ( string_free . p feat )
        = k + k 1
    }
    : i tr3 ( model_force_train_at mo3 + T0 * 200 3600 )
    ( check > tr3 0 `ensure: the model trains` )
    : String e1 ( model_forecast_ensure_at mo3 + T0 * 200 3600 )
    ( check == ( string_len e1 ) 0 `ensure: fits the forecast version` )
    ( string_free e1 )
    ( check == . . mo3 fc season 24 `ensure: hourly points get the daily season` )
    ( check ( meta_version_enabled ( model_metadata mo3 ) ANOM_FC_NAME F ) `ensure: and switches it on` )
    ( model_free mo3 )

    // a minute's step: the day is 1 440 rows, which no polynomial state
    // can carry — the season goes to Fourier terms, the fit stays quick,
    // and the forecast still follows the rhythm
    : *Model mo4 ( model_open_at st `minute` T0 )
    ( model_set_limits mo4 10 150000 )
    ( model_set_schedule mo4 100000 100000 )
    : ( Vec Json ) recs ( vec_new [Json] )
    = k 0
    ~ < k 4500 {
        : Json j ( json_obj_new )
        ( json_obj_set j `temp` ( json_float + + 20.0 * 5.0 ( sin / * 6.283185307179586 # f k 1440.0 ) * 0.3 ( gauss3 ) ) )
        ( json_obj_set j `timestamp` ( json_int + T0 * k 60 ) )
        ( vec_push [Json] recs j )
        = k + k 1
    }
    : ImportReport ir ( model_import_at mo4 recs + T0 * 4500 60 )
    ( check == . ir accepted 4500 `minute: 4 500 points imported` )
    ( import_report_free ir )
    ( vec_free_with [Json] recs \ Json j → v { ( json_free j ) } )
    : i tm0 ( now_ms )
    : String e4 ( model_forecast_ensure_at mo4 + T0 * 4500 60 )
    : i tm1 - ( now_ms ) tm0
    ( check == ( string_len e4 ) 0 `minute: the forecast version fits` )
    ( string_free e4 )
    : String tl ( string_from `minute: fitted a 1 440-row season on 2 000 rows in ` )
    ( string_push_int tl tm1 ) ( string_push_str tl ` ms` )
    ( check < tm1 20000 ( string_data tl ) )
    ( string_free tl )
    ( check == . . mo4 fc season 1440 `minute: the season is the day` )
    : *ArimaModel am4 ( model_forecast_model mo4 0 )
    ( check > . am4 xk 0 `minute: modelled as Fourier terms` )
    ( check == . . am4 spec s 0 `minute: over a plain ARMA` )
    : Json bt4 ( model_forecast_backtest mo4 60 100 )
    : ~ f sk4 -1.0
    ?? ( json_obj_get bt4 `features` ) { T fa → { ?? ( json_arr_get fa 0 ) { T f0 → { ?? ( json_obj_get f0 `skill_vs_naive` ) { T e → { ?? ( json_num_as_f e ) { T x → { = sk4 x } F _ → {} } } F _ → {} } } F _ → {} } } F _ → {} }
    ( check > sk4 0.3 `minute: an hour ahead the Fourier model beats the naive forecast` )
    ( json_free bt4 )
    // a reopen keeps the regressors' phase
    ( model_free mo4 )
    : *Model mo5 ( model_open_at st `minute` + T0 * 4500 60 )
    : Json fj5 ( model_forecast_json mo5 1 )
    : ~ f m5 0.0
    ?? ( json_obj_get fj5 `forecasts` ) { T fa → { ?? ( json_arr_get fa 0 ) { T f0 → { ?? ( json_obj_get f0 `mean` ) { T a → { ?? ( json_arr_get a 0 ) { T e → { ?? ( json_num_as_f e ) { T x → { = m5 x } F _ → {} } } F _ → {} } } F _ → {} } } F _ → {} } } F _ → {} }
    ( check < ( float_abs - m5 + 20.0 * 5.0 ( sin / * 6.283185307179586 4500.0 1440.0 ) ) 1.0 `minute: after a reopen the next value is forecast on the rhythm` )
    ( json_free fj5 )
    ( model_free mo5 )

    // reset drops it
    ( model_reset mo2 )
    ( check ! . fcb trained `forecast: reset drops the models` )
    ?? ( store_load_fc st `fc` ) { T fx → { ( check F `forecast: reset removes the file` ) ( fc_free fx ) } F → { ( check T `forecast: reset removes the file` ) } }
    ( model_free mo2 )
    ( store_free st )
    ( string_free root )

    : String sum ( string_from `forecast_test: ` )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( pline ( string_data sum ) )
    ( string_free sum )
    ^ ? > g_fail 0 1 0
}
