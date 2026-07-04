// anomaly — streaming anomaly detection from the command line.
//
//   anomaly detect <model> key=val ...     ingest one point → verdict JSON
//   anomaly score  <model> key=val ...     score only (no state change)
//   anomaly batch  [-f FILE] [-H]          score a CSV (index<TAB>score)
//   anomaly train  <model>                 force a retrain now
//   anomaly reset  <model>                 drop data+forests, keep the name
//   anomaly rm     <model>                 delete the model entirely
//   anomaly ls                             list models in the store
//   anomaly info   <model>                 dump model metadata (pretty JSON)
//   anomaly serve  [--addr HOST:PORT]      run the HTTP/JSON service + dashboard
//                  [--webroot DIR]         (dashboard HTML dir; auto-located)
//
// Values in key=val are auto-typed: numbers are numeric features, ISO-8601
// strings are timestamps, anything else is categorical (one-hot). Verdicts
// print as one JSON object per invocation. The store lives under --store
// DIR (default $ANOMALY_HOME, else ~/.anomaly).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`
$ `src/service.nu`

@ __cli_store_root ArgParser p → String {
    : ?String ov ( args_value p `store` )
    ?? ov { T v → { ^ v } F junk → { ( string_free junk ) } }
    : ?String ev ( env_get `ANOMALY_HOME` )
    ?? ev { T v → { ^ v } F junk → { ( string_free junk ) } }
    : String home ( env_var_or `HOME` `.` )
    : String r ( path_join ( string_data home ) `.anomaly` )
    ( string_free home )
    ^ r
}

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

// Resolve the directory that holds the dashboard HTML for `serve`. Order:
//   --webroot DIR  →  $ANOMALY_WEBROOT  →  <exe-dir>/static  →
//   <exe-dir>/../share/anomaly/static  →  ./static.
// Returns the first candidate that exists; empty String disables the
// dashboard (API-only serving still works).
@ __cli_webroot ArgParser p → String {
    : ?String ov ( args_value p `webroot` )
    ?? ov { T v → { ^ v } F junk → { ( string_free junk ) } }
    : ?String ev ( env_get `ANOMALY_WEBROOT` )
    ?? ev {
        T v → {
            ? ( file_exists ( string_data v ) ) { ^ v } { ( string_free v ) }
        }
        F junk → { ( string_free junk ) }
    }
    // Candidates derived from the executable location.
    : !String IoErr exe ( fs_readlink `/proc/self/exe` )
    ?? exe {
        T ep → {
            : String bindir ( path_dirname ( string_data ep ) )
            ( string_free ep )
            : String c1 ( path_join ( string_data bindir ) `static` )
            ? ( file_exists ( string_data c1 ) ) {
                ( string_free bindir )
                ^ c1
            } { ( string_free c1 ) }
            : String share ( path_join ( string_data bindir ) `../share/anomaly/static` )
            ( string_free bindir )
            ? ( file_exists ( string_data share ) ) { ^ share } { ( string_free share ) }
        }
        F _ → {}
    }
    // Last resort: ./static relative to the current directory.
    ? ( file_exists `static` ) { ^ ( string_from `static` ) } {}
    ^ ( string_new )
}

// key=val positionals (from index `from`) → a JSON record. Numeric-looking
// values become JSON numbers, everything else a JSON string (the library's
// auto-typing takes it from there). None on a malformed argument.
@ __cli_record ( Vec String ) pos i from → ?Json {
    : Json o ( json_obj_new )
    : i n ( vec_len [String] pos )
    : ~ i k from
    ~ < k n {
        ?? ( vec_get [String] pos k ) {
            T kv → {
                : ?i eq ( string_index_of kv `=` )
                ?? eq {
                    T at → {
                        ? <= at 0 {
                            ( json_free o )
                            ^ @ ?Json { F }
                        } {}
                        : String key ( string_new )
                        : String val ( string_new )
                        : i len ( string_len kv )
                        : ~ i c 0
                        ~ < c at {
                            ( string_push_char key ( string_get kv c ) )
                            = c + c 1
                        }
                        = c + at 1
                        ~ < c len {
                            ( string_push_char val ( string_get kv c ) )
                            = c + c 1
                        }
                        : ?f fx ( string_to_float val )
                        ?? fx {
                            T x → { ( json_obj_set o ( string_data key ) ( json_float x ) ) }
                            F _ → { ( json_obj_set o ( string_data key ) ( json_str_lit ( string_data val ) ) ) }
                        }
                        ( string_free key )
                        ( string_free val )
                    }
                    F _ → {
                        ( json_free o )
                        ^ @ ?Json { F }
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?Json { T o }
}

// Print a verdict as one compact JSON object.
@ __cli_print_verdict *Model mo Verdict vd → v {
    : Json o ( json_obj_new )
    ? . vd ready {
        ( json_obj_set o `status` ( json_str_lit `success` ) )
        ( json_obj_set o `anomaly` ( json_bool . vd anomaly ) )
        ( json_obj_set o `score` ( json_float . vd score ) )
        : Json vers ( json_obj_new )
        : i nv ( vec_len [VerVerdict] . vd versions )
        : ~ i k 0
        ~ < k nv {
            ?? ( vec_get [VerVerdict] . vd versions k ) {
                T vv → {
                    : Json vo ( json_obj_new )
                    ( json_obj_set vo `anomaly` ( json_bool . vv anomaly ) )
                    ( json_obj_set vo `score` ( json_float . vv score ) )
                    ( json_obj_set vo `margin` ( json_float . vv margin ) )
                    ( json_obj_set vers ( string_data . vv vvname ) vo )
                }
                F _ → {}
            }
            = k + k 1
        }
        ( json_obj_set o `versions` vers )
    } {
        ( json_obj_set o `status` ( json_str_lit `collecting` ) )
        ( json_obj_set o `min_data_points` ( json_int . mo min_points ) )
    }
    ( json_obj_set o `data_points` ( json_int ( model_n_points mo ) ) )
    : String out ( json_stringify o )
    ( pline ( string_data out ) )
    ( string_free out )
    ( json_free o )
}

// Print (or report the error of) one detect/score result. Exit code.
@ __cli_report *Model mo !Verdict String vr → i {
    ?? vr {
        T vd → {
            ( __cli_print_verdict mo vd )
            ( verdict_free vd )
            ^ 0
        }
        F e → {
            ( nurl_eprint `anomaly: ` )
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
}

// detect / score shared path. Returns the exit code.
@ __cli_detect ArgParser p ( Vec String ) pos b ingest → i {
    ? < ( vec_len [String] pos ) 2 {
        ( nurl_eprintln `anomaly: model name required` )
        ^ 2
    } {}
    : ~ s mname ``
    ?? ( vec_get [String] pos 1 ) { T m → { = mname ( string_data m ) } F _ → {} }
    : ?Json ro ( __cli_record pos 2 )
    ?? ro {
        T rec → {
            ? > ( json_arr_len rec ) 0 { } {}
            : String root ( __cli_store_root p )
            : Store st ( store_open ( string_data root ) )
            ( string_free root )
            : ~ i rc 0
            ? & == ingest F == ( store_exists st mname ) F {
                ( nurl_eprint `anomaly: model not found: ` )
                ( nurl_eprintln mname )
                = rc 1
            } {
                : *Model mo ( model_open st mname )
                ? ingest {
                    : !Verdict String vr ( model_ingest mo rec )
                    = rc ( __cli_report mo vr )
                } {
                    : !Verdict String vr ( model_detect_only mo rec )
                    = rc ( __cli_report mo vr )
                }
                ( model_free mo )
            }
            ( store_free st )
            ( json_free rec )
            ^ rc
        }
        F _ → {
            ( nurl_eprintln `anomaly: arguments must be key=value pairs` )
            ^ 2
        }
    }
}

// batch: stateless CSV scoring, one `index<TAB>score` line per row.
@ __cli_batch ArgParser p → i {
    : ~ String input ( string_new )
    : ~ b have_input T
    : ?String fo ( args_value p `file` )
    ?? fo {
        T fv → {
            : !String IoErr r ( read_file ( string_data fv ) )
            ?? r {
                T txt → { ( string_free input ) = input txt }
                F _ → {
                    ( nurl_eprint `anomaly: cannot read file: ` )
                    ( nurl_eprintln ( string_data fv ) )
                    = have_input F
                }
            }
            ( string_free fv )
        }
        F junk → {
            ( string_free junk )
            ( string_free input )
            = input ( read_all_stdin )
        }
    }
    ? have_input {} {
        ( string_free input )
        ^ 1
    }
    : b header ( args_present p `header` )
    : AnomCsv ds ( anom_parse_csv ( string_data input ) `,` header )
    ( string_free input )
    ? || <= . ds rows 0 <= . ds cols 0 {
        ( nurl_eprintln `anomaly: no numeric rows found in input` )
        ( anom_csv_free ds )
        ^ 1
    } {}
    : ~ f margin 0.0
    : ?String mg ( args_value p `margin` )
    ?? mg {
        T mv → {
            ?? ( string_to_float mv ) { T x → { = margin x } F _ → {} }
            ( string_free mv )
        }
        F junk → { ( string_free junk ) }
    }
    : VerCfg cfg @ VerCfg { ( string_from `batch` ) 0 0 100 256 -1.0 margin T }
    : BatchReport rep ( anomaly_batch . ds data . ds rows . ds cols cfg )
    ( __an_vercfg_free cfg )

    : String out ( string_with_cap * . ds rows 16 )
    : ~ i r 0
    ~ < r . ds rows {
        ( string_push_int out r )
        ( string_push_char out 9 )
        ?? ( vec_get [f] . rep scores r ) {
            T sc → { ( string_push_float out sc ) }
            F _ → {}
        }
        ( string_push_char out 10 )
        = r + r 1
    }
    ( nurl_print ( string_data out ) )
    ( string_free out )
    : String sm ( string_from `anomalies: ` )
    ( string_push_int sm . rep anomaly_count )
    ( string_push_str sm ` of ` )
    ( string_push_int sm . rep total_rows )
    ( nurl_eprintln ( string_data sm ) )
    ( string_free sm )
    ( anomaly_report_free rep )
    ( anom_csv_free ds )
    ^ 0
}

@ main → i {
    : ArgParser p ( args_new `anomaly` `Streaming anomaly detection: dynamic self-training models over Isolation Forests.` )
    ( args_opt p `store` 115 `DIR` `model store (default: $ANOMALY_HOME, else ~/.anomaly)` )
    ( args_opt p `file` 102 `FILE` `for batch: read CSV from FILE instead of stdin` )
    ( args_opt p `margin` 109 `M` `for batch: decision margin (default 0 = predict==-1)` )
    ( args_opt p `addr` 97 `HOST:PORT` `for serve: bind address (default 127.0.0.1:8811)` )
    ( args_opt p `webroot` 119 `DIR` `for serve: dashboard HTML dir (default: <exe>/static, $ANOMALY_WEBROOT)` )
    ( args_flag p `header` 72 `for batch: skip the first CSV line (header)` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )

    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  detect <model> key=val ...   ingest one point, print the verdict\n  score  <model> key=val ...   score only (never ingests or retrains)\n  batch  [-f FILE] [-H]        score a CSV, one "index<TAB>score" per row\n  train  <model>               force a retrain now\n  reset  <model>               drop data + forests, keep the name\n  rm     <model>               delete the model entirely\n  ls                           list models\n  info   <model>               print model metadata\n  serve  [--addr H:P] [--webroot DIR]  HTTP/JSON service + web dashboard\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( pline `anomaly 0.2.0` )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: anomaly <detect|score|batch|train|reset|rm|ls|info|serve> ... (anomaly --help)` )
        ( args_free p )
        ^ 2
    } {}

    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F _ → {} }
    : ~ s arg1 ``
    ? >= ( args_positional_count p ) 2 {
        ?? ( vec_get [String] pos 1 ) { T a → { = arg1 ( string_data a ) } F _ → {} }
    } {}

    : ~ i rc 0
    : ~ b handled T
    ? ( nurl_str_eq cmd `detect` ) {
        = rc ( __cli_detect p pos T )
    } {
    ? ( nurl_str_eq cmd `score` ) {
        = rc ( __cli_detect p pos F )
    } {
    ? ( nurl_str_eq cmd `batch` ) {
        = rc ( __cli_batch p )
    } {
    ? ( nurl_str_eq cmd `serve` ) {
        : ~ String addr ( string_from `127.0.0.1:8811` )
        : ?String av ( args_value p `addr` )
        ?? av {
            T v → { ( string_free addr ) = addr v }
            F junk → { ( string_free junk ) }
        }
        : ~ String host ( string_new )
        : ~ i port 8811
        : ?i colon ( string_index_of addr `:` )
        ?? colon {
            T at → {
                : i n ( string_len addr )
                : ~ i c 0
                ~ < c at {
                    ( string_push_char host ( string_get addr c ) )
                    = c + c 1
                }
                : String ps ( string_new )
                = c + at 1
                ~ < c n {
                    ( string_push_char ps ( string_get addr c ) )
                    = c + c 1
                }
                ?? ( string_to_int ps ) { T x → { = port x } F _ → {} }
                ( string_free ps )
            }
            F _ → {
                ( string_free host )
                = host ( string_from ( string_data addr ) )
            }
        }
        : String root ( __cli_store_root p )
        ( anomaly_service_set_root ( string_data root ) )
        : String webroot ( __cli_webroot p )
        ( anomaly_service_set_webroot ( string_data webroot ) )
        ? > ( string_len webroot ) 0 {
            ( nurl_eprint `anomaly: dashboard web root: ` )
            ( nurl_eprintln ( string_data webroot ) )
        } {
            ( nurl_eprintln `anomaly: no dashboard web root found (API-only)` )
        }
        = rc ( anomaly_serve ( string_data host ) port )
        ( string_free webroot )
        ( string_free root )
        ( string_free host )
        ( string_free addr )
    } {
        // Store-backed single-model commands.
        : String root ( __cli_store_root p )
        : Store st ( store_open ( string_data root ) )
        ( string_free root )
        ? ( nurl_str_eq cmd `ls` ) {
            : ( Vec String ) names ( store_list st )
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → { ( pline ( string_data nm ) ) }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        } {
        ? ( nurl_str_eq cmd `info` ) {
            : ?*Meta mload ( store_load_meta st arg1 )
            ?? mload {
                T mm → {
                    : Json o ( meta_to_json mm )
                    : String out ( json_pretty o )
                    ( pline ( string_data out ) )
                    ( string_free out )
                    ( json_free o )
                    ( meta_free mm )
                }
                F _ → {
                    ( nurl_eprint `anomaly: model not found: ` )
                    ( nurl_eprintln arg1 )
                    = rc 1
                }
            }
        } {
        ? ( nurl_str_eq cmd `train` ) {
            ? ( store_exists st arg1 ) {
                : *Model mo ( model_open st arg1 )
                : i used ( model_force_train mo )
                ? > used 0 {
                    : String msg ( string_from `trained on ` )
                    ( string_push_int msg used )
                    ( string_push_str msg ` points` )
                    ( pline ( string_data msg ) )
                    ( string_free msg )
                } {
                    ( nurl_eprintln `anomaly: not enough data to train` )
                    = rc 1
                }
                ( model_free mo )
            } {
                ( nurl_eprint `anomaly: model not found: ` )
                ( nurl_eprintln arg1 )
                = rc 1
            }
        } {
        ? ( nurl_str_eq cmd `reset` ) {
            ? ( store_exists st arg1 ) {
                : *Model mo ( model_open st arg1 )
                ( model_reset mo )
                ( model_free mo )
                ( pline `reset` )
            } {
                ( nurl_eprint `anomaly: model not found: ` )
                ( nurl_eprintln arg1 )
                = rc 1
            }
        } {
        ? ( nurl_str_eq cmd `rm` ) {
            ? ( store_exists st arg1 ) {
                : b okd ( model_delete st arg1 )
                ? okd { ( pline `deleted` ) } {
                    ( nurl_eprintln `anomaly: delete failed` )
                    = rc 1
                }
            } {
                ( nurl_eprint `anomaly: model not found: ` )
                ( nurl_eprintln arg1 )
                = rc 1
            }
        } {
            ( nurl_eprint `anomaly: unknown command: ` )
            ( nurl_eprintln cmd )
            ( nurl_eprintln `try 'anomaly --help'` )
            = rc 2
        } } } } }
        ( store_free st )
    } } } }

    ( args_free p )
    ^ rc
}
