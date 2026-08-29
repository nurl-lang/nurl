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

// String field of a JSON object equals `want`.
@ jstr_eq Json o s key s want → b {
    ?? ( json_obj_get o key ) {
        T e → { ^ == ( nurl_str_eq ( json_str_data e ) want ) 1 }
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

    // Fine-tune.
    : SvcOut ft ( fire r `POST` `/api/dynamic/svc/finetune` `` `{}` )
    ( check == . ft status 200 `svc: finetune -> 200` )
    : ~ b has_margin F
    ?? ( json_obj_get . ft body `adjusted_margins` ) {
        T ms → {
            ?? ( json_obj_get ms `short_term` ) { T _ → { = has_margin T } F _ → {} }
        }
        F _ → {}
    }
    ( check has_margin `svc: finetune returns adjusted margins` )
    ( json_free . ft body )

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
