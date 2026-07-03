// anomaly/service.nu — HTTP/JSON service (milestone M6).
//
// Thin: parse JSON → call the library → serialise. The routes and the
// request/response shapes mirror the Python reference service so existing
// dashboards keep working:
//
//   POST   /detect/<model>                    ingest + verdict (202 warming)
//   POST   /detect_only/<model>               score only, no state change
//   GET|POST /force_train/<model>             retrain now
//   POST   /detect_anomalies                  batch-score a CSV file
//   GET    /models/dynamic                    list models + metadata
//   GET    /models/dynamic/<model>/metadata   metadata
//   GET    /models/dynamic/<model>/data       recent points (?limit=N|all)
//   POST   /models/dynamic/<model>/reset      drop data+forests, keep name
//   DELETE|GET /delete_model/<model>          delete entirely
//   PUT    /api/dynamic/<model>/schedule      retraining schedule
//   POST   /api/dynamic/<model>/finetune      recalibrate margins
//
// Model names must match ^[a-zA-Z0-9_]+$ (400 otherwise, same message as
// the reference). Divergence from the reference: /detect_anomalies scores
// the CSV with a self-trained stateless forest (the reference's separate
// "static model" family doesn't exist here); passing model_name is a 400.
//
// The router is exposed separately from the socket (anomaly_service_router
// + router_handle) so every route is testable without networking.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_server.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`

// Store root used by every handler; set once before serving.
: ~ s g_an_root `.`

@ anomaly_service_set_root s root → v {
    = g_an_root root
}

// ── Small helpers ─────────────────────────────────────────────────────

@ __an_name_ok s name → b {
    : i n ( nurl_str_len name )
    ? <= n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get name k )
        : ~ b good F
        ? & >= c 48 <= c 57 { = good T } {}
        ? & >= c 65 <= c 90 { = good T } {}
        ? & >= c 97 <= c 122 { = good T } {}
        ? == c 95 { = good T } {}
        ? good {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __an_json_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `error` ) )
    ( json_obj_set o `message` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( json_free o )
    ^ r
}

@ __an_bad_name → HttpResponse {
    ^ ( __an_json_err 400 `Invalid model name. Use only letters, numbers, and underscores.` )
}

@ __an_404_model s name → HttpResponse {
    : String msg ( string_from `Model ` )
    ( string_push_str msg name )
    ( string_push_str msg ` not found` )
    : HttpResponse r ( __an_json_err 404 ( string_data msg ) )
    ( string_free msg )
    ^ r
}

@ __an_ok_msg s msg → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `message` ( json_str_lit msg ) )
    ^ o
}

// The :model path capture (owned; empty String = missing).
@ __an_param_model Params p → String {
    ?? ( params_get p `model` ) {
        T v → { ^ v }
        F junk → { ^ junk }
    }
}

// Request body as parsed JSON, or None.
@ __an_body_json HttpRequest req → ?Json {
    : String txt ( bytes_to_str . req body )
    : !Json JsonError r ( json_parse ( string_data txt ) )
    ( string_free txt )
    ?? r {
        T j → { ^ @ ?Json { T j } }
        F _ → { ^ @ ?Json { F } }
    }
}

// Integer query parameter (?key=N). `dflt` when missing/garbage; -1 for
// the "everything" spellings (all / max / *).
@ __an_query_int String q s key i dflt → i {
    : String needle ( string_from key )
    ( string_push_char needle 61 )
    : ?i at0 ( string_index_of q ( string_data needle ) )
    : i klen ( string_len needle )
    ( string_free needle )
    ?? at0 {
        T at → {
            : String val ( string_new )
            : i n ( string_len q )
            : ~ i k + at klen
            : ~ b going T
            ~ & going < k n {
                : i c ( string_get q k )
                ? == c 38 { = going F } {
                    ( string_push_char val c )
                    = k + k 1
                }
            }
            : ~ i out dflt
            : s vraw ( string_data val )
            ? || == ( nurl_str_eq vraw `all` ) 1 || == ( nurl_str_eq vraw `max` ) 1 == ( nurl_str_eq vraw `*` ) 1 {
                = out -1
            } {
                ?? ( string_to_int val ) {
                    T x → { ? > x 0 { = out x } {} }
                    F _ → {}
                }
            }
            ( string_free val )
            ^ out
        }
        F _ → { ^ dflt }
    }
}

// ── Verdict → JSON ────────────────────────────────────────────────────

@ __an_verdict_resp *Model mo s mname Json body Verdict vd → HttpResponse {
    ? . vd ready {} {
        : *Meta mm ( model_metadata mo )
        : i n ( model_n_points mo )
        : String msg ( string_from `Collecting data (` )
        ( string_push_int msg n )
        ( string_push_char msg 47 )
        ( string_push_int msg . mo min_points )
        ( string_push_str msg ` points).` )
        : Json o ( json_obj_new )
        ( json_obj_set o `status` ( json_str_lit `collecting` ) )
        ( json_obj_set o `message` ( json_str_lit ( string_data msg ) ) )
        ( json_obj_set o `data_points` ( json_int n ) )
        ( json_obj_set o `min_data_points` ( json_int . mo min_points ) )
        ( json_obj_set o `model_name` ( json_str_lit mname ) )
        ( string_free msg )
        : HttpResponse r ( response_json 202 o )
        ( json_free o )
        ^ r
    }

    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model` ( json_str_lit mname ) )
    ( json_obj_set o `anomaly` ( json_bool . vd anomaly ) )
    ( json_obj_set o `score` ( json_float . vd score ) )
    ( json_obj_set o `data_points` ( json_int ( model_n_points mo ) ) )

    : Json vers ( json_obj_new )
    : i nv ( vec_len [VerVerdict] . vd versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerVerdict] . vd versions k ) {
            T vv → {
                : Json vo ( json_obj_new )
                ( json_obj_set vo `anomaly` ( json_bool . vv anomaly ) )
                ( json_obj_set vo `score` ( json_float . vv score ) )
                : Json ti ( json_obj_new )
                ( json_obj_set ti `margin` ( json_float . vv margin ) )
                ( json_obj_set vo `threshold_info` ti )
                ( json_obj_set vers ( string_data . vv vvname ) vo )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `versions` vers )
    ( json_obj_set o `data_point` ( json_clone body ) )

    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// ── Route handlers ────────────────────────────────────────────────────

@ __an_h_detect HttpRequest req Params p b ingest → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            ? ( json_is_obj body ) {} {
                ( json_free body )
                ( string_free mname )
                ^ ( __an_json_err 400 `No parameters provided. Need at least one numeric parameter.` )
            }
            : Store st ( store_open g_an_root )
            ? ingest {} {
                ? ( store_exists st ( string_data mname ) ) {} {
                    : HttpResponse r404 ( __an_404_model ( string_data mname ) )
                    ( store_free st )
                    ( json_free body )
                    ( string_free mname )
                    ^ r404
                }
            }
            : *Model mo ( model_open st ( string_data mname ) )
            ? ingest {} {
                ? ( model_is_trained mo ) {} {
                    : String msg ( string_from `Model ` )
                    ( string_push_str msg ( string_data mname ) )
                    ( string_push_str msg ` exists but is not trained yet.` )
                    : HttpResponse rr ( __an_json_err 400 ( string_data msg ) )
                    ( string_free msg )
                    ( model_free mo )
                    ( store_free st )
                    ( json_free body )
                    ( string_free mname )
                    ^ rr
                }
            }
            : ~ HttpResponse resp ( response_status_only 500 )
            ? ingest {
                : !Verdict String vr ( model_ingest mo body )
                ?? vr {
                    T vd → {
                        ( http_response_free resp )
                        = resp ( __an_verdict_resp mo ( string_data mname ) body vd )
                        ( verdict_free vd )
                    }
                    F e → {
                        ( http_response_free resp )
                        = resp ( __an_json_err 400 ( string_data e ) )
                        ( string_free e )
                    }
                }
            } {
                : !Verdict String vr ( model_detect_only mo body )
                ?? vr {
                    T vd → {
                        ( http_response_free resp )
                        = resp ( __an_verdict_resp mo ( string_data mname ) body vd )
                        ( verdict_free vd )
                    }
                    F e → {
                        ( http_response_free resp )
                        = resp ( __an_json_err 400 ( string_data e ) )
                        ( string_free e )
                    }
                }
            }
            ( model_free mo )
            ( store_free st )
            ( json_free body )
            ( string_free mname )
            ^ resp
        }
        F _ → {
            ( string_free mname )
            ^ ( __an_json_err 400 `No parameters provided. Need at least one numeric parameter.` )
        }
    }
}

@ __an_h_force_train HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    : i used ( model_force_train mo )
    : ~ HttpResponse resp ( response_status_only 500 )
    ? > used 0 {
        : String msg ( string_from `Model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` trained` )
        : Json o ( __an_ok_msg ( string_data msg ) )
        ( json_obj_set o `points_used` ( json_int used ) )
        ( http_response_free resp )
        = resp ( response_json 200 o )
        ( json_free o )
        ( string_free msg )
    } {
        ( http_response_free resp )
        = resp ( __an_json_err 400 `Not enough data to train` )
    }
    ( model_free mo )
    ( store_free st )
    ( string_free mname )
    ^ resp
}

@ __an_h_models HttpRequest req Params p → HttpResponse {
    : Store st ( store_open g_an_root )
    : Json models ( json_obj_new )
    : ( Vec String ) names ( store_list st )
    : i n ( vec_len [String] names )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] names k ) {
            T nm → {
                : ?*Meta mload ( store_load_meta st ( string_data nm ) )
                ?? mload {
                    T mm → {
                        ( json_obj_set models ( string_data nm ) ( meta_to_json mm ) )
                        ( meta_free mm )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `models` models )
    ( json_obj_set o `min_data_points` ( json_int ANOM_MIN_POINTS ) )
    ( json_obj_set o `max_data_points` ( json_int ANOM_MAX_POINTS ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( store_free st )
    ^ r
}

@ __an_h_metadata HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    : ?*Meta mload ( store_load_meta st ( string_data mname ) )
    : ~ HttpResponse resp ( response_status_only 500 )
    ?? mload {
        T mm → {
            : Json o ( meta_to_json mm )
            ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
            ( http_response_free resp )
            = resp ( response_json 200 o )
            ( json_free o )
            ( meta_free mm )
        }
        F _ → {
            ( http_response_free resp )
            = resp ( __an_404_model ( string_data mname ) )
        }
    }
    ( store_free st )
    ( string_free mname )
    ^ resp
}

@ __an_h_data HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : i limit ( __an_query_int . req query `limit` 100 )
    : ( Vec String ) pts ( store_load_points st ( string_data mname ) )
    : i total ( vec_len [String] pts )
    : ~ i from 0
    ? > limit 0 {
        ? > total limit { = from - total limit } {}
    } {}
    : Json arr ( json_arr_new )
    : ~ i k from
    ~ < k total {
        ?? ( vec_get [String] pts k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → { ( json_arr_push arr j ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] pts \ String x → v { ( string_free x ) } )
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
    ( json_obj_set o `data_points_count` ( json_int total ) )
    ( json_obj_set o `data` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_reset HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    ( model_reset mo )
    ( model_free mo )
    : String msg ( string_from `Model ` )
    ( string_push_str msg ( string_data mname ) )
    ( string_push_str msg ` reset` )
    : Json o ( __an_ok_msg ( string_data msg ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_delete HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : b okd ( store_delete st ( string_data mname ) )
    : String msg ( string_from `Model ` )
    ( string_push_str msg ( string_data mname ) )
    ( string_push_str msg ` deleted successfully` )
    : Json o ( __an_ok_msg ( string_data msg ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_schedule HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            : i below ( __an_jint body `below_max_retrain_frequency` 0 )
            : i atmax ( __an_jint body `at_max_retrain_frequency` 0 )
            ( json_free body )
            ? || > below 0 > atmax 0 {} {
                ( store_free st )
                ( string_free mname )
                ^ ( __an_json_err 400 `No training schedule parameters provided` )
            }
            : *Model mo ( model_open st ( string_data mname ) )
            ( model_set_schedule mo below atmax )
            : *Meta mm ( model_metadata mo )
            : String msg ( string_from `Training schedule updated for model ` )
            ( string_push_str msg ( string_data mname ) )
            : Json o ( __an_ok_msg ( string_data msg ) )
            : Json sched ( json_obj_new )
            ( json_obj_set sched `below_max` ( json_int . mm sched_below ) )
            ( json_obj_set sched `at_max` ( json_int . mm sched_at_max ) )
            ( json_obj_set o `training_schedule` sched )
            : HttpResponse r ( response_json 200 o )
            ( json_free o )
            ( string_free msg )
            ( model_free mo )
            ( store_free st )
            ( string_free mname )
            ^ r
        }
        F _ → {
            ( store_free st )
            ( string_free mname )
            ^ ( __an_json_err 400 `No data provided` )
        }
    }
}

@ __an_h_finetune HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    ? ( model_is_trained mo ) {} {
        : String msg ( string_from `Model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` exists but is not trained yet.` )
        : HttpResponse rr ( __an_json_err 400 ( string_data msg ) )
        ( string_free msg )
        ( model_free mo )
        ( store_free st )
        ( string_free mname )
        ^ rr
    }
    : FineTuneReport rep ( model_finetune mo )
    : Json margins ( json_obj_new )
    : Json scores ( json_obj_new )
    : i ni ( vec_len [FtVer] . rep items )
    : ~ i k 0
    ~ < k ni {
        ?? ( vec_get [FtVer] . rep items k ) {
            T ft → {
                ( json_obj_set margins ( string_data . ft ftname ) ( json_float . ft new_margin ) )
                ( json_obj_set scores ( string_data . ft ftname ) ( json_float . ft min_score ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( finetune_free rep )
    : String msg ( string_from `Successfully fine-tuned model ` )
    ( string_push_str msg ( string_data mname ) )
    : Json o ( __an_ok_msg ( string_data msg ) )
    ( json_obj_set o `adjusted_margins` margins )
    ( json_obj_set o `max_anomaly_scores` scores )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( model_free mo )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_batch HttpRequest req Params p → HttpResponse {
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            ? ( json_obj_has body `model_name` ) {
                ( json_free body )
                ^ ( __an_json_err 400 `model_name is not supported: batch scoring trains a stateless forest on the file itself` )
            } {}
            : ~ String fpath ( string_new )
            : ~ b have_path F
            ?? ( json_obj_get body `file_path` ) {
                T fp → {
                    ? ( json_is_str fp ) {
                        ( string_free fpath )
                        = fpath ( string_from ( json_str_data fp ) )
                        = have_path T
                    } {}
                }
                F _ → {}
            }
            : ~ b header T
            ?? ( json_obj_get body `has_header` ) {
                T hh → { = header ( json_as_bool hh ) }
                F _ → {}
            }
            ( json_free body )
            ? have_path {} {
                ( string_free fpath )
                ^ ( __an_json_err 400 `file_path is required` )
            }
            : !String IoErr fr ( read_file ( string_data fpath ) )
            ?? fr {
                T text → {
                    : AnomCsv ds ( anom_parse_csv ( string_data text ) `,` header )
                    ( string_free text )
                    ? || <= . ds rows 0 <= . ds cols 0 {
                        ( anom_csv_free ds )
                        ( string_free fpath )
                        ^ ( __an_json_err 400 `No numeric rows found in file` )
                    } {}
                    : VerCfg cfg @ VerCfg { ( string_from `batch` ) 0 0 100 256 -1.0 0.0 T }
                    : BatchReport rep ( anomaly_batch . ds data . ds rows . ds cols cfg )
                    ( __an_vercfg_free cfg )

                    : Json res ( json_obj_new )
                    ( json_obj_set res `file_path` ( json_str_lit ( string_data fpath ) ) )
                    ( json_obj_set res `model_used` ( json_str_lit `batch:iforest` ) )
                    ( json_obj_set res `total_rows` ( json_int . rep total_rows ) )
                    ( json_obj_set res `anomaly_count` ( json_int . rep anomaly_count ) )
                    ( json_obj_set res `anomaly_percentage` ( json_float . rep anomaly_percentage ) )
                    ( json_obj_set res `has_anomalies` ( json_bool . rep has_anomalies ) )
                    : Json idxs ( json_arr_new )
                    : i nh ( vec_len [i] . rep anomaly_indices )
                    : ~ i k 0
                    ~ < k nh {
                        ?? ( vec_get [i] . rep anomaly_indices k ) {
                            T idx → { ( json_arr_push idxs ( json_int idx ) ) }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ( json_obj_set res `anomaly_indices` idxs )
                    // First 100 anomalies with their scores (and named
                    // column values when the CSV had a header row).
                    : Json details ( json_arr_new )
                    : ~ i d 0
                    ~ & < d nh < d 100 {
                        ?? ( vec_get [i] . rep anomaly_indices d ) {
                            T idx → {
                                : Json det ( json_obj_new )
                                ( json_obj_set det `index` ( json_int idx ) )
                                ?? ( vec_get [f] . rep scores idx ) {
                                    T sc → { ( json_obj_set det `anomaly_score` ( json_float sc ) ) }
                                    F _ → {}
                                }
                                : i nhead ( vec_len [String] . ds headers )
                                : ~ i c 0
                                ~ & < c nhead < c . ds cols {
                                    ?? ( vec_get [String] . ds headers c ) {
                                        T hname → {
                                            ?? ( vec_get [f] . ds data + * idx . ds cols c ) {
                                                T val → { ( json_obj_set det ( string_data hname ) ( json_float val ) ) }
                                                F _ → {}
                                            }
                                        }
                                        F _ → {}
                                    }
                                    = c + c 1
                                }
                                ( json_arr_push details det )
                            }
                            F _ → {}
                        }
                        = d + d 1
                    }
                    ( json_obj_set res `anomaly_details` details )
                    ( anomaly_report_free rep )
                    ( anom_csv_free ds )
                    ( string_free fpath )

                    : Json o ( __an_ok_msg `Anomaly detection completed` )
                    ( json_obj_set o `result` res )
                    : HttpResponse r ( response_json 200 o )
                    ( json_free o )
                    ^ r
                }
                F _ → {
                    : String msg ( string_from `File not found: ` )
                    ( string_push_str msg ( string_data fpath ) )
                    : HttpResponse rr ( __an_json_err 404 ( string_data msg ) )
                    ( string_free msg )
                    ( string_free fpath )
                    ^ rr
                }
            }
        }
        F _ → { ^ ( __an_json_err 400 `file_path is required` ) }
    }
}

// ── Router assembly / server ──────────────────────────────────────────

@ anomaly_service_router → Router {
    : Router r ( router_new )
    ( router_post r `/detect/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_detect req p T ) } )
    ( router_post r `/detect_only/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_detect req p F ) } )
    ( router_post r `/force_train/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_force_train req p ) } )
    ( router_get r `/force_train/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_force_train req p ) } )
    ( router_post r `/detect_anomalies` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_batch req p ) } )
    ( router_get r `/models/dynamic` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_models req p ) } )
    ( router_get r `/models/dynamic/:model/metadata` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_metadata req p ) } )
    ( router_get r `/models/dynamic/:model/data` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_data req p ) } )
    ( router_post r `/models/dynamic/:model/reset` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_reset req p ) } )
    ( router_delete r `/delete_model/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_delete req p ) } )
    ( router_get r `/delete_model/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_delete req p ) } )
    ( router_put r `/api/dynamic/:model/schedule` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_schedule req p ) } )
    ( router_post r `/api/dynamic/:model/finetune` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_finetune req p ) } )
    ^ r
}

// Serve until the listener errors. Returns a process exit code.
@ anomaly_serve s host i port → i {
    : Router r ( anomaly_service_router )
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }
            : HttpServer srv ( server_new listener h )
            ( nurl_eprint `anomaly: serving on ` )
            ( nurl_eprint host )
            ( nurl_eprint `:` )
            : String ps ( string_new )
            ( string_push_int ps port )
            ( nurl_eprintln ( string_data ps ) )
            ( string_free ps )
            : !v NetErr rr ( server_run srv )
            ( server_stop srv )
            ( router_free r )
            ?? rr {
                T _ → { ^ 0 }
                F e → {
                    ( nurl_eprint `anomaly: server error: ` )
                    ( nurl_eprintln ( net_err_name e ) )
                    ^ 1
                }
            }
        }
        F e → {
            ( router_free r )
            ( nurl_eprint `anomaly: cannot bind ` )
            ( nurl_eprintln host )
            ^ 1
        }
    }
}
