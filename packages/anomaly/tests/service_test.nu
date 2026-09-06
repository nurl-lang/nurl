// service_test.nu — M6 tests: every HTTP route golden-tested through
// router_handle, no sockets involved. Store: $ANOMALY_TEST_DIR (default
// ./anomaly_svc_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`
$ `src/service.nu`

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

@ mk_req s method s path s query s body → HttpRequest {
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( string_from `HTTP/1.1` )
        ( vec_new [Header] )
        ( bytes_from_str body )
    }
}

// Fire one request; returns (status, parsed body Json or JNull).
: SvcOut {
    i status
    Json body
}

@ fire Router r s method s path s query s body → SvcOut {
    : HttpRequest req ( mk_req method path query body )
    : HttpResponse resp ( router_handle r req )
    : i status . resp status
    : String txt ( bytes_to_str . resp body )
    : ~ Json parsed ( json_null )
    : !Json JsonError jr ( json_parse ( string_data txt ) )
    ?? jr {
        T j → { ( json_free parsed ) = parsed j }
        F _ → {}
    }
    ( string_free txt )
    ( http_response_free resp )
    ( request_free req )
    ^ @ SvcOut { status parsed }
}

// Fire one request for its status alone; the body is parsed and dropped.
@ status_of Router r s method s path → i {
    : SvcOut o ( fire r method path `` `` )
    ( json_free . o body )
    ^ . o status
}

// String field of a JSON object equals `want`.
@ jstr_eq Json o s key s want → b {
    ?? ( json_obj_get o key ) {
        T e → { ^ == ( nurl_str_eq ( json_str_data e ) want ) 1 }
        F _ → { ^ F }
    }
}

// Does the array under `key` contain the string `want`? The dashboard
// generates its whole metadata editor from `editable_fields`, so an
// endpoint that stops publishing it silently empties that editor.
@ jarr_has Json o s key s want → b {
    ?? ( json_obj_get o key ) {
        T a → {
            : i n ( json_arr_len a )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get a k ) {
                    T e → { ? == ( nurl_str_eq ( json_str_data e ) want ) 1 { ^ T } {} }
                    F _ → {}
                }
                = k + k 1
            }
            ^ F
        }
        F _ → { ^ F }
    }
}

@ jint_of Json o s key → i {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( json_as_int e ) }
        F _ → { ^ -1 }
    }
}

@ jbool_of Json o s key → b {
    ?? ( json_obj_get o key ) {
        T e → { ^ ( json_as_bool e ) }
        F _ → { ^ F }
    }
}

@ main → i {
    : ~ String root ( string_from `./anomaly_svc_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    ( anomaly_service_set_root ( string_data root ) )
    : Router r ( anomaly_service_router )

    // Invalid model name.
    : SvcOut bad ( fire r `POST` `/detect/bad!name` `` `{"temp": 1}` )
    ( check == . bad status 400 `svc: invalid name -> 400` )
    ( check ( jstr_eq . bad body `status` `error` ) `svc: invalid name error body` )
    ( json_free . bad body )

    // First point: create-on-first-use + warming up (202).
    : SvcOut first ( fire r `POST` `/detect/svc` `` `{"temp": 20.5}` )
    ( check == . first status 202 `svc: first point -> 202 collecting` )
    ( check ( jstr_eq . first body `status` `collecting` ) `svc: collecting status` )
    ( check == ( jint_of . first body `data_points` ) 1 `svc: data_points 1` )
    ( json_free . first body )

    // 49 more points → trained, 200 success.
    : ~ i k 2
    : ~ i last_status 0
    : ~ Json last_body ( json_null )
    ~ <= k 50 {
        : String body ( string_from `{"temp": 2` )
        ( string_push_int body % k 10 )
        ( string_push_str body `.5}` )
        : SvcOut o ( fire r `POST` `/detect/svc` `` ( string_data body ) )
        ( string_free body )
        = last_status . o status
        ( json_free last_body )
        = last_body . o body
        = k + k 1
    }
    ( check == last_status 200 `svc: point 50 -> 200 (trained)` )
    ( check ( jstr_eq last_body `status` `success` ) `svc: success status` )
    // (whether a quantized-grid point trips the tight default margins is
    // small-sample statistics, covered by dynamic_test — here we only pin
    // the response SHAPE)
    : ~ b has_anomaly_field F
    ?? ( json_obj_get last_body `anomaly` ) {
        T e → { = has_anomaly_field ( json_is_bool e ) }
        F _ → {}
    }
    ( check has_anomaly_field `svc: anomaly field present and boolean` )
    : ~ b has_versions F
    ?? ( json_obj_get last_body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) { T _ → { = has_versions T } F _ → {} }
        }
        F _ → {}
    }
    ( check has_versions `svc: per-version breakdown present` )
    ( json_free last_body )

    // detect_only: missing model 404; outlier flagged; garbage 400.
    : SvcOut miss ( fire r `POST` `/detect_only/nosuch` `` `{"temp": 1}` )
    ( check == . miss status 404 `svc: detect_only missing -> 404` )
    ( json_free . miss body )
    : SvcOut outl ( fire r `POST` `/detect_only/svc` `` `{"temp": 99}` )
    ( check == . outl status 200 `svc: detect_only -> 200` )
    ( check ( jbool_of . outl body `anomaly` ) `svc: outlier flagged` )
    // severity = -score / margin: unit-free, > 1 exactly when flagged.
    : ~ f sev 0.0
    ?? ( json_obj_get . outl body `severity` ) { T e → { ?? ( json_num_as_f e ) { T x → { = sev x } F _ → {} } } F _ → {} }
    ( check > sev 1.0 `svc: aggregate severity above 1 for a flagged point` )
    : ~ f sev_st 0.0
    : ~ b ti_ok F
    ?? ( json_obj_get . outl body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) {
                T v → {
                    ?? ( json_obj_get v `severity` ) { T e → { ?? ( json_num_as_f e ) { T x → { = sev_st x } F _ → {} } } F _ → {} }
                    // threshold_info names the band and its units: a
                    // forest's margin is absolute, so it equals the
                    // stored decision_margin.
                    ?? ( json_obj_get v `threshold_info` ) {
                        T ti → {
                            : ~ f m 0.0
                            : ~ f dm -1.0
                            ?? ( json_obj_get ti `margin` ) { T e → { ?? ( json_num_as_f e ) { T x → { = m x } F _ → {} } } F _ → {} }
                            ?? ( json_obj_get ti `decision_margin` ) { T e → { ?? ( json_num_as_f e ) { T x → { = dm x } F _ → {} } } F _ → {} }
                            = ti_ok & == m dm ( jstr_eq ti `units` `absolute` )
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check > sev_st 0.0 `svc: per-version severity present` )
    ( check ti_ok `svc: threshold_info carries decision_margin and units` )
    ( json_free . outl body )
    : SvcOut garb ( fire r `POST` `/detect_only/svc` `` `not json` )
    ( check == . garb status 400 `svc: garbage body -> 400` )
    ( json_free . garb body )

    // Listing + metadata + data.
    : SvcOut lst ( fire r `GET` `/models/dynamic` `` `` )
    ( check == . lst status 200 `svc: models list -> 200` )
    : ~ b has_svc F
    ?? ( json_obj_get . lst body `models` ) {
        T ms → {
            ?? ( json_obj_get ms `svc` ) { T _ → { = has_svc T } F _ → {} }
        }
        F _ → {}
    }
    ( check has_svc `svc: model in listing` )
    ( check == ( jint_of . lst body `min_data_points` ) 50 `svc: listing min_data_points` )
    ( json_free . lst body )

    : SvcOut md ( fire r `GET` `/models/dynamic/svc/metadata` `` `` )
    ( check == . md status 200 `svc: metadata -> 200` )
    ( check ( jstr_eq . md body `model_name` `svc` ) `svc: metadata carries model_name` )
    ( check ( jarr_has . md body `editable_fields` `max_data_points` )
    `svc: metadata publishes the editable key list` )
    ( check ( jarr_has . md body `editable_fields` `versions` )
    `svc: the editable key list names versions` )
    ( json_free . md body )
    : SvcOut md4 ( fire r `GET` `/models/dynamic/nosuch/metadata` `` `` )
    ( check == . md4 status 404 `svc: metadata missing -> 404` )
    ( json_free . md4 body )

    : SvcOut data ( fire r `GET` `/models/dynamic/svc/data` `limit=5` `` )
    ( check == . data status 200 `svc: data -> 200` )
    ( check == ( jint_of . data body `data_points_count` ) 50 `svc: data total count` )
    : ~ i arr_len -1
    ?? ( json_obj_get . data body `data` ) {
        T arr → { = arr_len ( json_arr_len arr ) }
        F _ → {}
    }
    ( check == arr_len 5 `svc: data respects limit` )
    ( json_free . data body )

    // Schedule.
    : SvcOut sch ( fire r `PUT` `/api/dynamic/svc/schedule` `` `{"below_max_retrain_frequency": 25}` )
    ( check == . sch status 200 `svc: schedule update -> 200` )
    : ~ i below -1
    ?? ( json_obj_get . sch body `training_schedule` ) {
        T ts → { = below ( jint_of ts `below_max` ) }
        F _ → {}
    }
    ( check == below 25 `svc: schedule below_max updated` )
    ( json_free . sch body )
    : SvcOut sch2 ( fire r `PUT` `/api/dynamic/svc/schedule` `` `{}` )
    ( check == . sch2 status 400 `svc: empty schedule -> 400` )
    ( json_free . sch2 body )

    // Editable metadata: PUT /models/dynamic/<m>/metadata.
    : SvcOut mu ( fire r `PUT` `/models/dynamic/svc/metadata` ``
    `{"versions":{"weekly":{"enabled":false},"daily":{"decision_margin":0.44}},"schedule":{"below_max":30,"at_max":600}}` )
    ( check == . mu status 200 `svc: metadata PUT -> 200` )
    : ~ b patch_applied F
    : ~ b weekly_off F
    : ~ i below2 -1
    ?? ( json_obj_get . mu body `metadata` ) {
        T md → {
            ?? ( json_obj_get md `versions` ) {
                T vs → {
                    ?? ( json_obj_get vs `daily` ) {
                        T d → {
                            ?? ( json_obj_get d `decision_margin` ) {
                                T dm → {
                                    ?? ( json_num_as_f dm ) {
                                        T x → { = patch_applied < ( float_abs - x 0.44 ) 0.000001 }
                                        F _ → {}
                                    }
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    ?? ( json_obj_get vs `weekly` ) {
                        T w → { = weekly_off == ( jbool_of w `enabled` ) F }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            ?? ( json_obj_get md `schedule` ) {
                T sc → { = below2 ( jint_of sc `below_max` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check patch_applied `svc: metadata PUT sets a version margin` )
    ( check weekly_off `svc: metadata PUT disables a version` )
    ( check == below2 30 `svc: metadata PUT sets the schedule` )
    ( json_free . mu body )

    : SvcOut mu2 ( fire r `PUT` `/models/dynamic/svc/metadata` `` `{"versions":[]}` )
    ( check == . mu2 status 400 `svc: metadata PUT rejects a non-object versions` )
    ( json_free . mu2 body )
    : SvcOut mu3 ( fire r `PUT` `/models/dynamic/svc/metadata` `` `{}` )
    ( check == . mu3 status 400 `svc: an empty metadata patch -> 400` )
    ( json_free . mu3 body )
    : SvcOut mu4 ( fire r `PUT` `/models/dynamic/nope/metadata` `` `{"schedule":{"below_max":5,"at_max":5}}` )
    ( check == . mu4 status 404 `svc: metadata PUT on an unknown model -> 404` )
    ( json_free . mu4 body )

    // The metadata GET carries the autoencoder's own state.
    : SvcOut aem ( fire r `GET` `/models/dynamic/svc/metadata` `` `` )
    : ~ b ae_block F
    ?? ( json_obj_get . aem body `autoencoder` ) {
        T ab → { = ae_block == ( jbool_of ab `trained` ) F }
        F _ → {}
    }
    ( check ae_block `svc: metadata carries an autoencoder block` )
    ( json_free . aem body )

    // Put weekly back so the routes below see the default version set.
    : SvcOut mu5 ( fire r `PUT` `/models/dynamic/svc/metadata` ``
    `{"versions":{"weekly":{"enabled":true},"daily":{"decision_margin":0.12}},"schedule":{"below_max":25,"at_max":1000}}` )
    ( check == . mu5 status 200 `svc: metadata PUT restores the defaults` )
    ( json_free . mu5 body )

    // Calibration: read-only, per version, with the rate ladder.
    : SvcOut cal ( fire r `GET` `/models/dynamic/svc/calibration` `last=all&curve=0` `` )
    ( check == . cal status 200 `svc: calibration -> 200` )
    : ~ i cal_rows -1
    ?? ( json_obj_get . cal body `window` ) { T w → { = cal_rows ( jint_of w `rows` ) } F _ → {} }
    ( check == cal_rows 50 `svc: calibration scored the whole ring` )
    : ~ b cal_st F
    : ~ b cal_ladder F
    : ~ b cal_units F
    ?? ( json_obj_get . cal body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) {
                T v → {
                    = cal_st == ( jint_of v `n` ) 50
                    = cal_units ( jstr_eq v `units` `absolute` )
                    ?? ( json_obj_get v `margin_for_rate` ) {
                        T mfr → {
                            ?? ( json_obj_get mfr `1%` ) {
                                T e → {
                                    // requested_rate is the ladder step;
                                    // achieved_rate = flagged / n.
                                    : ~ f req 0.0
                                    : ~ f ach -1.0
                                    ?? ( json_obj_get e `requested_rate` ) { T x → { ?? ( json_num_as_f x ) { T y → { = req y } F _ → {} } } F _ → {} }
                                    ?? ( json_obj_get e `achieved_rate` ) { T x → { ?? ( json_num_as_f x ) { T y → { = ach y } F _ → {} } } F _ → {} }
                                    : f want / # f ( jint_of e `flagged` ) 50.0
                                    = cal_ladder & == req 0.01 < ( float_abs - ach want ) 0.000000001
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check cal_st `svc: calibration reports short_term over 50 rows` )
    ( check cal_units `svc: calibration names the margin's units` )
    ( check cal_ladder `svc: margin_for_rate carries requested and achieved rates` )
    ( json_free . cal body )
    : SvcOut cal4 ( fire r `GET` `/models/dynamic/nosuch/calibration` `` `` )
    ( check == . cal4 status 404 `svc: calibration missing -> 404` )
    ( json_free . cal4 body )

    // Fine-tune: a dry run changes nothing, a real one writes 10 % of 50
    // = 5 flagged per version (the feed cycles ten values, so the five
    // copies of the worst one tie), and a bad rate is a 400.
    : SvcOut ftd ( fire r `POST` `/api/dynamic/svc/finetune` `` `{"rate":0.1,"last":"all","dry_run":true}` )
    ( check == . ftd status 200 `svc: finetune dry run -> 200` )
    ( check ( jbool_of . ftd body `dry_run` ) `svc: dry run echoed` )
    : ~ b dry_applied T
    : ~ i dry_after -1
    ?? ( json_obj_get . ftd body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) {
                T v → { = dry_applied ( jbool_of v `applied` ) = dry_after ( jint_of v `flagged_after` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check == dry_applied F `svc: dry run applies nothing` )
    ( check == dry_after 5 `svc: dry run predicts 5 flagged of 50` )
    ( json_free . ftd body )

    : SvcOut ft ( fire r `POST` `/api/dynamic/svc/finetune` `` `{"rate":0.1,"last":"all"}` )
    ( check == . ft status 200 `svc: finetune -> 200` )
    : ~ b has_margin F
    : ~ f ft_margin -1.0
    ?? ( json_obj_get . ft body `adjusted_margins` ) {
        T ms → {
            ?? ( json_obj_get ms `short_term` ) { T e → { = has_margin T ?? ( json_num_as_f e ) { T x → { = ft_margin x } F _ → {} } } F _ → {} }
        }
        F _ → {}
    }
    ( check has_margin `svc: finetune returns adjusted margins` )
    : ~ b ft_applied F
    ?? ( json_obj_get . ft body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) { T v → { = ft_applied ( jbool_of v `applied` ) } F _ → {} }
        }
        F _ → {}
    }
    ( check ft_applied `svc: finetune applied the margin` )
    ( json_free . ft body )
    : SvcOut md6 ( fire r `GET` `/models/dynamic/svc/metadata` `` `` )
    : ~ f stored_m -2.0
    ?? ( json_obj_get . md6 body `versions` ) {
        T vers → {
            ?? ( json_obj_get vers `short_term` ) {
                T v → { ?? ( json_obj_get v `decision_margin` ) { T e → { ?? ( json_num_as_f e ) { T x → { = stored_m x } F _ → {} } } F _ → {} } }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check < ( float_abs - stored_m ft_margin ) 0.000000001 `svc: the fine-tuned margin is in the metadata` )
    ( json_free . md6 body )
    : SvcOut ftb ( fire r `POST` `/api/dynamic/svc/finetune` `` `{"rate":7}` )
    ( check == . ftb status 400 `svc: finetune with rate > 1 -> 400` )
    ( json_free . ftb body )

    // Force train.
    : SvcOut tr ( fire r `POST` `/force_train/svc` `` `` )
    ( check == . tr status 200 `svc: force_train -> 200` )
    ( check == ( jint_of . tr body `points_used` ) 50 `svc: force_train points_used` )
    ( json_free . tr body )

    // Batch CSV.
    : String csv ( string_from `a,b\n1,2\n1.1,2.1\n0.9,1.9\n50,50\n1,2\n1,2.2\n` )
    : String csvpath ( string_from ( string_data root ) )
    ( string_push_str csvpath `/batch.csv` )
    : !v IoErr wr ( write_file ( string_data csvpath ) ( string_data csv ) )
    ?? wr { T _ → {} F _ → {} }
    ( string_free csv )
    : String breq ( string_from `{"file_path": "` )
    ( string_push_str breq ( string_data csvpath ) )
    ( string_push_str breq `", "has_header": true}` )
    : SvcOut bat ( fire r `POST` `/detect_anomalies` `` ( string_data breq ) )
    ( string_free breq )
    ( check == . bat status 200 `svc: detect_anomalies -> 200` )
    : ~ i bcount -1
    : ~ b bhas F
    : ~ i bidx -1
    ?? ( json_obj_get . bat body `result` ) {
        T res → {
            = bcount ( jint_of res `anomaly_count` )
            = bhas ( jbool_of res `has_anomalies` )
            ?? ( json_obj_get res `anomaly_indices` ) {
                T idxs → {
                    ?? ( json_arr_get idxs 0 ) { T e → { = bidx ( json_as_int e ) } F _ → {} }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check == bcount 1 `svc: batch flags exactly the outlier row` )
    ( check bhas `svc: batch has_anomalies` )
    ( check == bidx 3 `svc: batch anomaly index 3` )
    ( json_free . bat body )
    : SvcOut batm ( fire r `POST` `/detect_anomalies` `` `{"file_path": "x.csv", "model_name": "svc"}` )
    ( check == . batm status 400 `svc: batch model_name rejected` )
    ( json_free . batm body )
    ( string_free csvpath )

    // ── GET /models/dynamic/<m>/anomalies ─────────────────────────────
    //
    // The scan route: one model load for the whole ring, epoch-stamped
    // cache underneath, and the filters the dashboard drives.
    : SvcOut an404 ( fire r `GET` `/models/dynamic/nosuch/anomalies` `` `` )
    ( check == . an404 status 404 `svc: anomalies missing model -> 404` )
    ( json_free . an404 body )
    : SvcOut anbad ( fire r `GET` `/models/dynamic/bad-name/anomalies` `` `` )
    ( check == . anbad status 400 `svc: anomalies bad name -> 400` )
    ( json_free . anbad body )

    : SvcOut an1 ( fire r `GET` `/models/dynamic/svc/anomalies` `limit=all` `` )
    ( check == . an1 status 200 `svc: anomalies -> 200` )
    : i an1_total ( jint_of . an1 body `data_points_count` )
    : i an1_ret ( jint_of . an1 body `returned` )
    ( check == an1_ret an1_total `svc: anomalies returns every stored point` )
    : ~ i an1_hits -1
    : ~ i an1_miss -1
    : ~ i an1_epoch -1
    ?? ( json_obj_get . an1 body `cache` ) {
        T c → {
            = an1_hits ( jint_of c `hits` )
            = an1_miss ( jint_of c `misses` )
            = an1_epoch ( jint_of c `epoch` )
        }
        F _ → {}
    }
    ( check == an1_hits 0 `svc: the first scan is a cold one` )
    ( check == an1_miss an1_total `svc: the cold scan computes every verdict` )
    ( check > an1_epoch 0 `svc: the scan reports its epoch` )
    // model_versions drives the dashboard's filter chips, so it must be
    // there even before anything has been flagged.
    : ~ b an1_vers F
    ?? ( json_obj_get . an1 body `model_versions` ) {
        T vs → { = an1_vers > ( json_arr_len vs ) 0 }
        F _ → {}
    }
    ( check an1_vers `svc: anomalies lists the scoring versions` )
    // Every returned point carries the fields the charts read.
    : ~ b an1_shape F
    ?? ( json_obj_get . an1 body `points` ) {
        T ps → {
            ?? ( json_arr_get ps 0 ) {
                T p0 → {
                    = an1_shape & & ( json_obj_has p0 `index` ) ( json_obj_has p0 `timestamp` )
                    & ( json_obj_has p0 `score` ) ( json_obj_has p0 `anomaly` )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check an1_shape `svc: a scanned point carries index/timestamp/score/anomaly` )
    ( json_free . an1 body )

    // Second call: same answer, nothing recomputed.
    : SvcOut an2 ( fire r `GET` `/models/dynamic/svc/anomalies` `limit=all` `` )
    : ~ i an2_hits -1
    : ~ i an2_miss -1
    ?? ( json_obj_get . an2 body `cache` ) {
        T c → { = an2_hits ( jint_of c `hits` ) = an2_miss ( jint_of c `misses` ) }
        F _ → {}
    }
    ( check == an2_hits an1_total `svc: the second scan is served from cache` )
    ( check == an2_miss 0 `svc: the cached scan recomputes nothing` )
    ( json_free . an2 body )

    // limit takes the newest rows; fields adds the values the chart needs.
    : SvcOut an3 ( fire r `GET` `/models/dynamic/svc/anomalies` `limit=3&fields=temp` `` )
    ( check == ( jint_of . an3 body `returned` ) 3 `svc: anomalies honours limit` )
    ( check == ( jint_of . an3 body `considered` ) an1_total `svc: considered spans the window` )
    : ~ b an3_vals F
    ?? ( json_obj_get . an3 body `points` ) {
        T ps → {
            ?? ( json_arr_get ps 0 ) {
                T p0 → {
                    ?? ( json_obj_get p0 `values` ) {
                        T vv → { = an3_vals ( json_obj_has vv `temp` ) }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check an3_vals `svc: fields= attaches the requested feature values` )
    ( json_free . an3 body )

    // A time window nothing falls into is empty, not an error.
    : SvcOut an4 ( fire r `GET` `/models/dynamic/svc/anomalies` `from=4000000000` `` )
    ( check == . an4 status 200 `svc: an empty time window -> 200` )
    ( check == ( jint_of . an4 body `returned` ) 0 `svc: an empty time window returns nothing` )
    ( json_free . an4 body )

    // A margin edit changes verdicts, so it must invalidate the cache.
    : SvcOut anpatch ( fire r `PUT` `/models/dynamic/svc/metadata` ``
    `{"versions": {"weekly": {"decision_margin": 0.011}}}` )
    ( check == . anpatch status 200 `svc: margin patch -> 200` )
    ( json_free . anpatch body )
    : SvcOut an5 ( fire r `GET` `/models/dynamic/svc/anomalies` `limit=all` `` )
    : ~ i an5_miss -1
    : ~ i an5_epoch -1
    ?? ( json_obj_get . an5 body `cache` ) {
        T c → { = an5_miss ( jint_of c `misses` ) = an5_epoch ( jint_of c `epoch` ) }
        F _ → {}
    }
    ( check == an5_miss an1_total `svc: a margin edit invalidates every cached verdict` )
    ( check > an5_epoch an1_epoch `svc: the epoch advanced` )
    ( json_free . an5 body )

    // Import with a clock to find. An FMI-shaped file: the time is spread
    // over year/month/day/clock columns under Finnish names, and `-` is a
    // missing value. inspect=1 describes the file and proposes the parts
    // without creating the model; the import then stamps every row from
    // that proposal and drops the consumed columns.
    : s FMI `Havaintoasema,Vuosi,Kuukausi,Päivä,Aika [Paikallinen aika],Ilman lämpötila [°C],Suhteellinen kosteus [%]
Kouvola Anjala,2026,8,29,00:00,12.1,88
Kouvola Anjala,2026,8,29,00:10,12.0,89
Kouvola Anjala,2026,8,29,00:20,11.8,-
Kouvola Anjala,2026,8,29,00:30,11.7,90
Kouvola Anjala,2026,8,29,00:40,11.5,91
Kouvola Anjala,2026,8,29,00:50,11.4,92
`
    : SvcOut insp ( fire r `POST` `/models/dynamic/svc_imp/import` `inspect=1&format=csv&tz=utc` FMI )
    ( check == . insp status 200 `svc: import inspect -> 200` )
    : ~ b insp_parts F
    : ~ i insp_unix 0
    ?? ( json_obj_get . insp body `time` ) {
        T tj → {
            = insp_parts ( jstr_eq tj `mode` `parts` )
            = insp_unix ( jint_of tj `sample_unix` )
        }
        F _ → {}
    }
    ( check insp_parts `svc: inspect proposes the year/month/day/clock parts` )
    ( check == insp_unix 1787961600 `svc: inspect reads the first row as 2026-08-29T00:00:00Z` )
    : ~ b insp_exists T
    ?? ( json_obj_get . insp body `model` ) { T mj → { = insp_exists ( jbool_of mj `exists` ) } F _ → {} }
    ( check ! insp_exists `svc: inspect does not bring the model into being` )
    ( json_free . insp body )
    : SvcOut md_none ( fire r `GET` `/models/dynamic/svc_imp/metadata` `` `` )
    ( check == . md_none status 404 `svc: inspected model still 404` )
    ( json_free . md_none body )

    : SvcOut imp ( fire r `POST` `/models/dynamic/svc_imp/import` `format=csv&tz=utc` FMI )
    ( check == . imp status 200 `svc: import with the proposed clock -> 200` )
    ( check ( jstr_eq . imp body `clock` `time` ) `svc: stamped rows run on the time clock` )
    : ~ i imp_stamped 0
    ?? ( json_obj_get . imp body `time` ) { T tj → { = imp_stamped ( jint_of tj `stamped` ) } F _ → {} }
    ( check == imp_stamped 6 `svc: every row was stamped` )
    ( json_free . imp body )
    : SvcOut md_imp ( fire r `GET` `/models/dynamic/svc_imp/metadata` `` `` )
    ( check ( jstr_eq . md_imp body `clock` `time` ) `svc: metadata clock is time` )
    : ~ b has_year F
    : ~ b has_temp F
    ?? ( json_obj_get . md_imp body `column_types` ) {
        T ct → {
            ?? ( json_obj_get ct `Vuosi` ) { T _ → { = has_year T } F _ → {} }
            ?? ( json_obj_get ct `Ilman lämpötila [°C]` ) { T _ → { = has_temp T } F _ → {} }
        }
        F _ → {}
    }
    ( check ! has_year `svc: the consumed year column is not a feature` )
    ( check has_temp `svc: the measurement columns are features` )
    ( json_free . md_imp body )
    : SvcOut dat ( fire r `GET` `/models/dynamic/svc_imp/data` `limit=all` `` )
    : ~ i first_ts 0
    ?? ( json_obj_get . dat body `data` ) {
        T a → { ?? ( json_arr_get a 0 ) { T row → { = first_ts ( jint_of row `timestamp` ) } F _ → {} } }
        F _ → {}
    }
    ( check == first_ts 1787961600 `svc: the stored point carries the parsed stamp` )
    ( json_free . dat body )
    // ?at=<index>: exactly that row; past the end, none.
    : SvcOut at1 ( fire r `GET` `/models/dynamic/svc_imp/data` `at=1` `` )
    : ~ i at1_n 0
    : ~ i at1_ts 0
    ?? ( json_obj_get . at1 body `data` ) {
        T a → {
            = at1_n ( json_arr_len a )
            ?? ( json_arr_get a 0 ) { T row → { = at1_ts ( jint_of row `timestamp` ) } F _ → {} }
        }
        F _ → {}
    }
    ( check == at1_n 1 `svc: data?at= returns one row` )
    ( check == at1_ts + 1787961600 600 `svc: data?at=1 is the second stored row` )
    ( json_free . at1 body )
    : SvcOut at9 ( fire r `GET` `/models/dynamic/svc_imp/data` `at=99` `` )
    : ~ i at9_n -1
    ?? ( json_obj_get . at9 body `data` ) { T a → { = at9_n ( json_arr_len a ) } F _ → {} }
    ( check == at9_n 0 `svc: data?at= past the end is empty` )
    ( json_free . at9 body )
    // A feature named with spaces and a degree sign arrives percent-encoded
    // from a browser; fields= must still find it.
    : SvcOut anf ( fire r `GET` `/models/dynamic/svc_imp/anomalies`
    `limit=all&fields=Ilman%20l%C3%A4mp%C3%B6tila%20%5B%C2%B0C%5D,Suhteellinen%20kosteus%20%5B%25%5D` `` )
    ( check == . anf status 200 `svc: anomalies with encoded fields -> 200` )
    : ~ b anf_temp F
    : ~ b anf_rh F
    ?? ( json_obj_get . anf body `points` ) {
        T ps → {
            ?? ( json_arr_get ps 0 ) {
                T p0 → {
                    ?? ( json_obj_get p0 `values` ) {
                        T vv → {
                            = anf_temp ( json_obj_has vv `Ilman lämpötila [°C]` )
                            = anf_rh ( json_obj_has vv `Suhteellinen kosteus [%]` )
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( check anf_temp `svc: fields= is percent-decoded (space, UTF-8)` )
    ( check anf_rh `svc: fields= is percent-decoded (%25)` )
    ( json_free . anf body )
    ( check == ( status_of r `DELETE` `/delete_model/svc_imp` ) 200 `svc: delete imported model` )

    // The same rows without any time column: the model is born on the
    // count clock. Points are ticks of 60 apart, `last=N` is N points, and
    // the clock cannot be changed once points are stored.
    : s NOTIME `a,b
12.1,88
12.0,89
11.8,90
11.7,90
11.5,91
`
    : SvcOut impc ( fire r `POST` `/models/dynamic/svc_cnt/import` `format=csv` NOTIME )
    ( check == . impc status 200 `svc: import without a clock -> 200` )
    ( check ( jstr_eq . impc body `clock` `count` ) `svc: unstamped rows run on the count clock` )
    ( json_free . impc body )
    : SvcOut datc ( fire r `GET` `/models/dynamic/svc_cnt/data` `limit=all` `` )
    : ~ i tick0 0
    : ~ i tick4 0
    ?? ( json_obj_get . datc body `data` ) {
        T a → {
            ?? ( json_arr_get a 0 ) { T row → { = tick0 ( jint_of row `timestamp` ) } F _ → {} }
            ?? ( json_arr_get a 4 ) { T row → { = tick4 ( jint_of row `timestamp` ) } F _ → {} }
        }
        F _ → {}
    }
    ( check == tick0 60 `svc: count clock starts at tick 60` )
    ( check == tick4 300 `svc: ticks are 60 apart` )
    ( json_free . datc body )
    : SvcOut detc ( fire r `POST` `/detect/svc_cnt` `` `{"a": 11.3, "b": 92}` )
    ( check | == . detc status 200 == . detc status 202 `svc: detect on a count-clock model is accepted` )
    ( json_free . detc body )
    : SvcOut calc ( fire r `GET` `/models/dynamic/svc_cnt/calibration` `last=2` `` )
    : ~ i cal_rows -1
    ?? ( json_obj_get . calc body `window` ) { T w → { = cal_rows ( jint_of w `rows` ) } F _ → {} }
    // 400 (not trained) is fine too: what matters is that last= counts points.
    ? == . calc status 200 { ( check == cal_rows 2 `svc: last=2 on a count clock is 2 points` ) } {}
    ( json_free . calc body )
    : SvcOut clk ( fire r `PUT` `/models/dynamic/svc_cnt/metadata` `` `{"clock": "time"}` )
    ( check == . clk status 400 `svc: the clock cannot change once points are stored` )
    ( json_free . clk body )
    // Stamped rows into a count-clock model are taken as ticks — the clock
    // is settled — and the response says so.
    : SvcOut mismatch ( fire r `POST` `/models/dynamic/svc_cnt/import` `format=csv&tz=utc` FMI )
    ( check == . mismatch status 200 `svc: stamped rows into a count-clock model -> 200` )
    ( check ( jstr_eq . mismatch body `clock` `count` ) `svc: the count clock is kept` )
    : ~ b noted F
    ?? ( json_obj_get . mismatch body `notes` ) {
        T a → { ? > ( json_arr_len a ) 0 { = noted T } {} }
        F _ → {}
    }
    ( check noted `svc: ignored stamps are noted` )
    ( json_free . mismatch body )
    : SvcOut datc2 ( fire r `GET` `/models/dynamic/svc_cnt/data` `limit=all` `` )
    : ~ i tick11 0
    ?? ( json_obj_get . datc2 body `data` ) {
        T a → { ?? ( json_arr_get a 11 ) { T row → { = tick11 ( jint_of row `timestamp` ) } F _ → {} } }
        F _ → {}
    }
    ( check == tick11 720 `svc: the stamped rows took ticks, not their stamps` )
    ( json_free . datc2 body )
    ( check == ( status_of r `DELETE` `/delete_model/svc_cnt` ) 200 `svc: delete count model` )

    // Reset → not trained → detect_only 400.
    : SvcOut rs ( fire r `POST` `/models/dynamic/svc/reset` `` `{}` )
    ( check == . rs status 200 `svc: reset -> 200` )
    ( json_free . rs body )
    : SvcOut nt ( fire r `POST` `/detect_only/svc` `` `{"temp": 1}` )
    ( check == . nt status 400 `svc: detect_only after reset -> 400 (not trained)` )
    ( json_free . nt body )

    // Delete (both verbs), then gone.
    : SvcOut del ( fire r `DELETE` `/delete_model/svc` `` `` )
    ( check == . del status 200 `svc: delete -> 200` )
    ( json_free . del body )
    : SvcOut md5 ( fire r `GET` `/models/dynamic/svc/metadata` `` `` )
    ( check == . md5 status 404 `svc: deleted model metadata -> 404` )
    ( json_free . md5 body )

    // ── Organisation folder, signed links ─────────────────────────────
    ( check ( orgfiles_name_ok `report-2026.05.json` ) `orgfiles: plain name ok` )
    ( check ! ( orgfiles_name_ok `.hidden` ) `orgfiles: leading dot rejected` )
    ( check ! ( orgfiles_name_ok `../etc/passwd` ) `orgfiles: path escape rejected` )
    ( check ! ( orgfiles_name_ok `a b` ) `orgfiles: space rejected` )
    : String safe ( orgfiles_safe_name `demo run/x` )
    ( check == ( nurl_str_eq ( string_data safe ) `demo_run_x` ) 1 `orgfiles: safe_name maps the rest to _` )
    ( string_free safe )
    : ( Vec u ) payload ( bytes_from_str `{"hello": 1}` )
    ( check ( orgfiles_write `public` `hello.json` payload ) `orgfiles: write` )
    ( vec_free [u] payload )
    : SvcOut fl ( fire r `GET` `/api/org/files` `` `` )
    ( check == . fl status 200 `org files: list -> 200` )
    : ~ i nfiles 0
    ?? ( json_obj_get . fl body `files` ) { T a → { = nfiles ( json_arr_len a ) } F _ → {} }
    ( check == nfiles 1 `org files: one file listed` )
    ( json_free . fl body )
    : SvcOut fg ( fire r `GET` `/api/org/files/hello.json` `` `` )
    ( check == . fg status 200 `org files: member get -> 200` )
    ( check == ( jint_of . fg body `hello` ) 1 `org files: get returns the content` )
    ( json_free . fg body )
    ( check == ( status_of r `GET` `/api/org/files/nope.json` ) 404 `org files: missing -> 404` )
    ( check == ( status_of r `GET` `/api/org/files/.env` ) 400 `org files: bad name -> 400` )
    : SvcOut lk ( fire r `POST` `/api/org/files/hello.json/link` `ttl=60` `` )
    ( check == . lk status 200 `org files: link -> 200` )
    : ~ String durl ( string_new )
    ?? ( json_obj_get . lk body `download_url` ) { T u → { ( string_push_str durl ( json_str_data u ) ) } F _ → {} }
    ( check > ( string_len durl ) 0 `org files: link carries download_url` )
    ( json_free . lk body )
    // The link is path?query: split it and fire the query as an
    // anonymous request — the signature alone must open the file.
    : ~ i qat -1
    ?? ( string_index_of durl `?` ) { T q → { = qat q } F _ → {} }
    ( check > qat 0 `org files: link has a query` )
    : String lpath ( string_substr durl 0 qat )
    : String lquery ( string_substr durl + qat 1 - ( string_len durl ) + qat 1 )
    : SvcOut sg ( fire r `GET` ( string_data lpath ) ( string_data lquery ) `` )
    ( check == . sg status 200 `org files: signed link -> 200` )
    ( json_free . sg body )
    : ~ String bad ( string_from ( string_data lquery ) )
    ( string_push_str bad `0` )
    : SvcOut sb ( fire r `GET` ( string_data lpath ) ( string_data bad ) `` )
    ( check == . sb status 403 `org files: tampered signature -> 403` )
    ( json_free . sb body )
    ( string_free bad )
    : i tnow ( now_seconds )
    : String sig ( orgfiles_sign `public` `hello.json` + tnow 60 )
    ( check ( orgfiles_verify `public` `hello.json` + tnow 60 ( string_data sig ) tnow ) `orgfiles: verify own signature` )
    ( check ! ( orgfiles_verify `public` `hello.json` + tnow 60 ( string_data sig ) + tnow 61 ) `orgfiles: expired link fails` )
    ( check ! ( orgfiles_verify `other` `hello.json` + tnow 60 ( string_data sig ) tnow ) `orgfiles: signature is bound to the org` )
    ( string_free sig )
    ( string_free lpath )
    ( string_free lquery )
    ( string_free durl )
    ( check == ( status_of r `DELETE` `/api/org/files/hello.json` ) 200 `org files: delete -> 200` )
    ( check == ( status_of r `GET` `/api/org/files/hello.json` ) 404 `org files: deleted -> 404` )

    // ── Analyze: tasks, the job, the response ─────────────────────────
    ( check == ( status_of r `GET` `/api/org/tasks/not-a-task-id` ) 400 `tasks: bad id -> 400` )
    ( check == ( status_of r `GET` `/api/org/tasks/000000000000000000000000` ) 404 `tasks: unknown -> 404` )
    ( check == ( status_of r `POST` `/api/analyze` ) 400 `analyze: empty body -> 400` )
    // The test binary must not re-spawn itself as the job: the job runs
    // in this process instead, after the request has queued it.
    ( analyze_set_exe `/bin/true` )
    : ~ String csv ( string_from `timestamp,a,b` )
    : ~ i ri 0
    ~ < ri 400 {
        ( string_push_char csv 10 )
        ( string_push_int csv + 1780000000 * ri 60 )
        ( string_push_str csv `,` )
        ( string_push_int csv + 10 % ri 7 )
        ( string_push_str csv `,` )
        ( string_push_int csv ? == ri 200 900 + 20 % ri 5 )
        = ri + ri 1
    }
    : SvcOut aq ( fire r `POST` `/api/analyze` `wait=0&name=unit%20run` ( string_data csv ) )
    ( check == . aq status 202 `analyze: wait=0 -> 202 pending` )
    ( check ( jstr_eq . aq body `state` `queued` ) `analyze: state queued` )
    : ~ String tid ( string_new )
    ?? ( json_obj_get . aq body `task_id` ) { T t → { ( string_push_str tid ( json_str_data t ) ) } F _ → {} }
    ( check == ( string_len tid ) 24 `analyze: task_id is 24 hex chars` )
    ( json_free . aq body )
    : String tdir ( analyze_task_dir `public` ( string_data tid ) )
    ( check == ( analyze_run ( string_data tdir ) ) 0 `analyze: the job runs to completion` )
    : ~ String turl ( string_from `/api/org/tasks/` )
    ( string_push_str turl ( string_data tid ) )
    : SvcOut tr ( fire r `GET` ( string_data turl ) `` `` )
    ( check == . tr status 200 `tasks: finished task -> 200` )
    ( check ( jstr_eq . tr body `state` `done` ) `tasks: state done` )
    ( check == ( jint_of . tr body `rows` ) 400 `tasks: every row counted` )
    ( check ( jbool_of . tr body `inline` ) `tasks: small result is inline` )
    : ~ i npts -1
    : ~ b spike F
    ?? ( json_obj_get . tr body `points` ) {
        T a → {
            = npts ( json_arr_len a )
            : ~ i pk 0
            ~ < pk npts {
                ?? ( json_arr_get a pk ) {
                    T pt → { ? == ( jint_of pt `index` ) 200 { = spike T } {} }
                    F _ → {}
                }
                = pk + pk 1
            }
        }
        F _ → {}
    }
    ( check > npts 0 `tasks: anomalies returned` )
    ( check < npts 40 `tasks: the union stays near the target (< 10% of 400)` )
    ( check spike `tasks: the injected spike is among the anomalies` )
    ( check ( jarr_has . tr body `model_versions` `autoencoder` ) `tasks: the autoencoder was trained` )
    : ~ String rfile ( string_new )
    ?? ( json_obj_get . tr body `file` ) {
        T fo → {
            ?? ( json_obj_get fo `name` ) { T n → { ( string_push_str rfile ( json_str_data n ) ) } F _ → {} }
            ( check > ( jint_of fo `size` ) 0 `tasks: result file has a size` )
        }
        F _ → {}
    }
    ( json_free . tr body )
    : ~ String rurl ( string_from `/api/org/files/` )
    ( string_push_str rurl ( string_data rfile ) )
    : SvcOut rf ( fire r `GET` ( string_data rurl ) `` `` )
    ( check == . rf status 200 `tasks: result file is in the org folder` )
    ( check == ( jint_of . rf body `rows` ) 400 `tasks: result file carries the report` )
    ( json_free . rf body )
    ( string_free rurl )
    ( string_free rfile )
    : SvcOut tl ( fire r `GET` `/api/org/tasks` `` `` )
    ( check == . tl status 200 `tasks: list -> 200` )
    : ~ i ntasks 0
    ?? ( json_obj_get . tl body `tasks` ) { T a → { = ntasks ( json_arr_len a ) } F _ → {} }
    ( check == ntasks 1 `tasks: one task listed` )
    ( json_free . tl body )
    // A garbage file fails with a message, in the task and in the answer.
    : SvcOut ag ( fire r `POST` `/api/analyze` `wait=0` `this is not data` )
    ( check == . ag status 202 `analyze: garbage queues too` )
    : ~ String gid ( string_new )
    ?? ( json_obj_get . ag body `task_id` ) { T t → { ( string_push_str gid ( json_str_data t ) ) } F _ → {} }
    ( json_free . ag body )
    : String gdir ( analyze_task_dir `public` ( string_data gid ) )
    ( check != ( analyze_run ( string_data gdir ) ) 0 `analyze: garbage job fails` )
    : ~ String gurl ( string_from `/api/org/tasks/` )
    ( string_push_str gurl ( string_data gid ) )
    : SvcOut gr ( fire r `GET` ( string_data gurl ) `` `` )
    ( check == . gr status 200 `tasks: failed task is readable` )
    ( check ( jstr_eq . gr body `state` `failed` ) `tasks: state failed` )
    ( check ( jstr_eq . gr body `status` `error` ) `tasks: failed task says error` )
    ( json_free . gr body )
    ( check == ( status_of r `DELETE` ( string_data gurl ) ) 200 `tasks: delete -> 200` )
    ( check == ( status_of r `GET` ( string_data gurl ) ) 404 `tasks: deleted -> 404` )
    ( string_free gurl )
    ( string_free gdir )
    ( string_free gid )
    ( string_free turl )
    ( string_free tdir )
    ( string_free tid )
    ( string_free csv )

    ( router_free r )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `service_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
