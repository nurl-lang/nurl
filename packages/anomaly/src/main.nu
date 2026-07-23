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
//
// The command line is assembled with the `cli` package: one Cli, a flag set,
// and a handler per subcommand — routing, typed flags with the $ANOMALY_HOME
// / $ANOMALY_WEBROOT fallbacks, --help / --version and exit codes are the
// framework's job.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `deps/cli/src/cli.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`
$ `src/service.nu`

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

// Store directory: --store → $ANOMALY_HOME (via the flag's env fallback) →
// ~/.anomaly. The flag binds $ANOMALY_HOME, so an empty resolved value means
// neither was set and we fall back to the home directory.
@ __an_store_root CliCtx x → String {
    : String s ( ctx_str x `store` )
    ? > ( string_len s ) 0 { ^ s } {}
    ( string_free s )
    : String home ( env_var_or `HOME` `.` )
    : String r ( path_join ( string_data home ) `.anomaly` )
    ( string_free home )
    ^ r
}

// Dashboard web root for `serve`. --webroot / $ANOMALY_WEBROOT (via the
// flag) first, then <exe-dir>/static, <exe-dir>/../share/anomaly/static,
// then ./static. Empty String disables the dashboard (API-only).
@ __an_webroot CliCtx x → String {
    : String v ( ctx_str x `webroot` )
    ? > ( string_len v ) 0 {
        ? ( file_exists ( string_data v ) ) { ^ v } { ( string_free v ) }
    } {
        ( string_free v )
    }
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
    ? ( file_exists `static` ) { ^ ( string_from `static` ) } {}
    ^ ( string_new )
}

// The key=val positionals after the model → a JSON record. Numeric-looking
// values become JSON numbers, everything else a JSON string (the library's
// auto-typing takes it from there). None on a malformed argument.
@ __an_record CliCtx x → ?Json {
    : Json o ( json_obj_new )
    : i n ( ctx_nargs x )
    : ~ i k 1
    ~ < k n {
        : String kv ( ctx_arg x k )
        : ?i eq ( string_index_of kv `=` )
        ?? eq {
            T at → {
                ? <= at 0 {
                    ( string_free kv )
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
                    T fv → { ( json_obj_set o ( string_data key ) ( json_float fv ) ) }
                    F _ → { ( json_obj_set o ( string_data key ) ( json_str_lit ( string_data val ) ) ) }
                }
                ( string_free key )
                ( string_free val )
            }
            F _ → {
                ( string_free kv )
                ( json_free o )
                ^ @ ?Json { F }
            }
        }
        ( string_free kv )
        = k + k 1
    }
    ^ @ ?Json { T o }
}

// Print a verdict as one compact JSON object.
@ __an_print_verdict * Model mo Verdict vd → v {
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
@ __an_report * Model mo ! Verdict String vr → i {
    ?? vr {
        T vd → {
            ( __an_print_verdict mo vd )
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

// ── Command handlers ──────────────────────────────────────────────────

// detect / score share a path: ingest = true stores + retrains, false only
// scores. Model = first positional; features = the remaining key=val args.
@ __an_cmd_detect CliCtx x b ingest → i {
    ? < ( ctx_nargs x ) 1 {
        ( nurl_eprintln `anomaly: model name required` )
        ^ 2
    } {}
    : String mname ( ctx_arg x 0 )
    : ?Json ro ( __an_record x )
    : ~ i rc 0
    ?? ro {
        T rec → {
            : String root ( __an_store_root x )
            : Store st ( store_open ( string_data root ) )
            ( string_free root )
            ? & == ingest F == ( store_exists st ( string_data mname ) ) F {
                ( nurl_eprint `anomaly: model not found: ` )
                ( nurl_eprintln ( string_data mname ) )
                = rc 1
            } {
                : *Model mo ( model_open st ( string_data mname ) )
                ? ingest {
                    : !Verdict String vr ( model_ingest mo rec )
                    = rc ( __an_report mo vr )
                } {
                    : !Verdict String vr ( model_detect_only mo rec )
                    = rc ( __an_report mo vr )
                }
                ( model_free mo )
            }
            ( store_free st )
            ( json_free rec )
        }
        F _ → {
            ( nurl_eprintln `anomaly: arguments must be key=value pairs` )
            = rc 2
        }
    }
    ( string_free mname )
    ^ rc
}

// batch: stateless CSV scoring, one `index<TAB>score` line per row.
@ __an_cmd_batch CliCtx x → i {
    : ~ String input ( string_new )
    : ~ b have_input T
    : String fv ( ctx_str x `file` )
    ? > ( string_len fv ) 0 {
        : !String IoErr r ( read_file ( string_data fv ) )
        ?? r {
            T txt → { ( string_free input ) = input txt }
            F _ → {
                ( nurl_eprint `anomaly: cannot read file: ` )
                ( nurl_eprintln ( string_data fv ) )
                = have_input F
            }
        }
    } {
        ( string_free input )
        = input ( read_all_stdin )
    }
    ( string_free fv )
    ? have_input {} {
        ( string_free input )
        ^ 1
    }
    : b header ( ctx_bool x `header` )
    : AnomCsv ds ( anom_parse_csv ( string_data input ) `,` header )
    ( string_free input )
    ? || <= . ds rows 0 <= . ds cols 0 {
        ( nurl_eprintln `anomaly: no numeric rows found in input` )
        ( anom_csv_free ds )
        ^ 1
    } {}
    : f margin ( ctx_float x `margin` )
    : VerCfg cfg @ VerCfg { ( string_from `batch` ) 0 0 0 0 100 256 -1.0 margin T }
    : BatchReport rep ( anomaly_batch . ds data . ds rows . ds cols cfg )
    ( _an_vercfg_free cfg )

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

@ __an_cmd_serve CliCtx x → i {
    : String addr ( ctx_str x `addr` )
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
            ?? ( string_to_int ps ) { T v → { = port v } F _ → {} }
            ( string_free ps )
        }
        F _ → {
            ( string_free host )
            = host ( string_from ( string_data addr ) )
        }
    }
    : String root ( __an_store_root x )
    ( anomaly_service_set_root ( string_data root ) )
    : String webroot ( __an_webroot x )
    ( anomaly_service_set_webroot ( string_data webroot ) )
    ? > ( string_len webroot ) 0 {
        ( nurl_eprint `anomaly: dashboard web root: ` )
        ( nurl_eprintln ( string_data webroot ) )
    } {
        ( nurl_eprintln `anomaly: no dashboard web root found (API-only)` )
    }
    : i rc ( anomaly_serve ( string_data host ) port )
    ( string_free webroot )
    ( string_free root )
    ( string_free host )
    ( string_free addr )
    ^ rc
}

@ __an_cmd_ls CliCtx x → i {
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
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
    ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
    ( store_free st )
    ^ 0
}

@ __an_cmd_info CliCtx x → i {
    : String mname ( ctx_arg x 0 )
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
    : ~ i rc 0
    ?? ( store_load_meta st ( string_data mname ) ) {
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
            ( nurl_eprintln ( string_data mname ) )
            = rc 1
        }
    }
    ( store_free st )
    ( string_free mname )
    ^ rc
}

@ __an_cmd_train_ae CliCtx x → i {
    : String mname ( ctx_arg x 0 )
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
    : ~ i rc 0
    ? ( store_exists st ( string_data mname ) ) {
        : *Model mo ( model_open st ( string_data mname ) )
        : ( Vec i ) hidden ( vec_new [i] )
        : String err ( model_train_autoencoder mo hidden -1.0 )
        ( vec_free [i] hidden )
        ? == ( string_len err ) 0 {
            : AeModel tae . mo ae
            : String msg ( string_from `autoencoder trained on ` )
            ( string_push_int msg . tae trained_on )
            ( string_push_str msg ` normal points (` )
            ( string_push_int msg . tae filtered )
            ( string_push_str msg ` anomalies filtered)` )
            ( pline ( string_data msg ) )
            ( string_free msg )
        } {
            ( nurl_eprint `anomaly: ` )
            ( nurl_eprintln ( string_data err ) )
            = rc 1
        }
        ( string_free err )
        ( model_free mo )
    } {
        ( nurl_eprint `anomaly: model not found: ` )
        ( nurl_eprintln ( string_data mname ) )
        = rc 1
    }
    ( store_free st )
    ( string_free mname )
    ^ rc
}

@ __an_cmd_train CliCtx x → i {
    : String mname ( ctx_arg x 0 )
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
    : ~ i rc 0
    ? ( store_exists st ( string_data mname ) ) {
        : *Model mo ( model_open st ( string_data mname ) )
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
        ( nurl_eprintln ( string_data mname ) )
        = rc 1
    }
    ( store_free st )
    ( string_free mname )
    ^ rc
}

@ __an_cmd_reset CliCtx x → i {
    : String mname ( ctx_arg x 0 )
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
    : ~ i rc 0
    ? ( store_exists st ( string_data mname ) ) {
        : *Model mo ( model_open st ( string_data mname ) )
        ( model_reset mo )
        ( model_free mo )
        ( pline `reset` )
    } {
        ( nurl_eprint `anomaly: model not found: ` )
        ( nurl_eprintln ( string_data mname ) )
        = rc 1
    }
    ( store_free st )
    ( string_free mname )
    ^ rc
}

@ __an_cmd_rm CliCtx x → i {
    : String mname ( ctx_arg x 0 )
    : String root ( __an_store_root x )
    : Store st ( store_open ( string_data root ) )
    ( string_free root )
    : ~ i rc 0
    ? ( store_exists st ( string_data mname ) ) {
        : b okd ( model_delete st ( string_data mname ) )
        ? okd { ( pline `deleted` ) } {
            ( nurl_eprintln `anomaly: delete failed` )
            = rc 1
        }
    } {
        ( nurl_eprint `anomaly: model not found: ` )
        ( nurl_eprintln ( string_data mname ) )
        = rc 1
    }
    ( store_free st )
    ( string_free mname )
    ^ rc
}

@ main → i {
    : *Cli c ( cli_new `anomaly` `Streaming anomaly detection: dynamic self-training models over Isolation Forests.` `0.5.2` )
    ( cli_flag_str c `store` 115 `DIR` `model store (default: $ANOMALY_HOME, else ~/.anomaly)` `` `ANOMALY_HOME` )
    ( cli_flag_str c `file` 102 `FILE` `for batch: read CSV from FILE instead of stdin` `` `` )
    ( cli_flag_str c `margin` 109 `M` `for batch: decision margin (default 0 = predict==-1)` `0` `` )
    ( cli_flag_str c `addr` 97 `HOST:PORT` `for serve: bind address` `127.0.0.1:8811` `` )
    ( cli_flag_str c `webroot` 119 `DIR` `for serve: dashboard HTML dir (default: <exe>/static, $ANOMALY_WEBROOT)` `` `ANOMALY_WEBROOT` )
    ( cli_flag_bool c `header` 72 `for batch: skip the first CSV line (header)` )

    ( cli_cmd c `detect` `ingest one point, print the verdict` \ CliCtx x → i { ^ ( __an_cmd_detect x T ) } )
    ( cli_cmd c `score` `score only (never ingests or retrains)` \ CliCtx x → i { ^ ( __an_cmd_detect x F ) } )
    ( cli_cmd c `batch` `score a CSV, one index<TAB>score per row` \ CliCtx x → i { ^ ( __an_cmd_batch x ) } )
    ( cli_cmd c `train` `force a retrain now` \ CliCtx x → i { ^ ( __an_cmd_train x ) } )
    ( cli_cmd c `train-ae` `train the autoencoder version (iforest-filtered)` \ CliCtx x → i { ^ ( __an_cmd_train_ae x ) } )
    ( cli_cmd c `reset` `drop data + forests, keep the name` \ CliCtx x → i { ^ ( __an_cmd_reset x ) } )
    ( cli_cmd c `rm` `delete the model entirely` \ CliCtx x → i { ^ ( __an_cmd_rm x ) } )
    ( cli_cmd c `ls` `list models` \ CliCtx x → i { ^ ( __an_cmd_ls x ) } )
    ( cli_cmd c `info` `print model metadata` \ CliCtx x → i { ^ ( __an_cmd_info x ) } )
    ( cli_cmd c `serve` `run the HTTP/JSON service + web dashboard` \ CliCtx x → i { ^ ( __an_cmd_serve x ) } )

    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
