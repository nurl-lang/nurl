// src/analyze.nu — one-shot analysis of a file
//
// `POST /api/analyze` takes a file and answers with its anomalies: the
// file becomes a throwaway model, trained as carefully as the data allows
// — every forest version, the 64-16-64 autoencoder over the forest-
// filtered points, every margin set to a 1 % alert rate — scanned once,
// and thrown away. What remains is the result file in the organisation's
// folder (src/orgfiles.nu) and a status record.
//
// The work runs in a CHILD PROCESS, `anomaly analyze-job <task dir>`,
// not in the service: training holds the GPU singleton and the random
// state, both of which the live detectors use, and a file that takes
// the trainer down must not take the service with it. The service and
// the job meet only in the task directory:
//
//   <root>/orgs/<org>/tasks/<id>/params.json   what to do (service → job)
//                              /input         the file as posted
//                              /status.json   queued | running | done | failed
//                              /store/        the temporary model, gone when done
//
// The service watches status.json; the job writes it (atomically) at
// each transition, and the thread that ran the child marks it failed
// when the process died without saying so.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/importer.nu`
$ `src/orgfiles.nu`

: f ANA_TARGET_RATE 0.01
: i ANA_MIN_ROWS 10
: i ANA_INLINE_MAX 10000  // anomalies returned in the response body; beyond it, a link

// ── The task directory ────────────────────────────────────────────────

@ analyze_task_dir s org s id → String {
    : String d ( orgfiles_tasks_dir org )
    ( string_push_char d 47 )
    ( string_push_str d id )
    ^ d
}

@ __ana_file s dir s name → String {
    : String p ( string_from dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ __ana_write_json s dir s name Json j → b {
    : String p ( __ana_file dir name )
    : String tmp ( string_clone p )
    ( string_push_str tmp `.tmp` )
    : String txt ( json_stringify j )
    : ~ b ok F
    ?? ( write_file ( string_data tmp ) ( string_data txt ) ) {
        T _ → { ?? ( fs_rename ( string_data tmp ) ( string_data p ) ) { T _ → { = ok T } F _ → {} } }
        F _ → {}
    }
    ( string_free txt )
    ( string_free tmp )
    ( string_free p )
    ^ ok
}

@ __ana_read_json s dir s name → ?Json {
    : String p ( __ana_file dir name )
    : ~ ? Json out @ ?Json { F @ Json { JNull } }
    ?? ( read_file ( string_data p ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T j → { ? ( json_is_obj j ) { = out @ ?Json { T j } } { ( json_free j ) } }
                F _ → {}
            }
            ( string_free txt )
        }
        F _ → {}
    }
    ( string_free p )
    ^ out
}

@ analyze_status_read s dir → ?Json { ^ ( __ana_read_json dir `status.json` ) }

@ analyze_status_write s dir Json st → b { ^ ( __ana_write_json dir `status.json` st ) }

@ _ana_jstr Json o s key → String {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {} }
        F _ → {}
    }
    ^ ( string_new )
}

@ _ana_jint Json o s key i dflt → i {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } {} }
        F _ → {}
    }
    ^ dflt
}

@ _ana_jbool Json o s key → b {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_bool v ) { ^ ( json_bool_val v ) } {} }
        F _ → {}
    }
    ^ F
}

@ analyze_state s dir → String {
    ?? ( analyze_status_read dir ) {
        T st → {
            : String s ( _ana_jstr st `state` )
            ( json_free st )
            ^ s
        }
        F _ → {}
    }
    ^ ( string_from `missing` )
}

@ analyze_state_final s state → b {
    ^ | == ( nurl_str_eq state `done` ) 1 == ( nurl_str_eq state `failed` ) 1
}

// Create the task: a fresh id, its directory, the input and the
// parameters written, status `queued`. Returns the id ("" = could not
// create).
@ analyze_task_create s org Json params ( Vec u ) input → String {
    : String id ( rand_hex_str 12 )
    : String dir ( analyze_task_dir org ( string_data id ) )
    : ~ b ok T
    ?? ( dir_create_all ( string_data dir ) ) { T _ → {} F _ → { = ok F } }
    ? ok {
        : String ip ( __ana_file ( string_data dir ) `input` )
        ?? ( write_file_bytes ( string_data ip ) input ) { T _ → {} F _ → { = ok F } }
        ( string_free ip )
    } {}
    ? ok {
        ( json_obj_set params `id` ( json_str_lit ( string_data id ) ) )
        ( json_obj_set params `org` ( json_str_lit org ) )
        = ok ( __ana_write_json ( string_data dir ) `params.json` params )
    } {}
    ? ok {
        : Json st ( json_obj_new )
        ( json_obj_set st `state` ( json_str_lit `queued` ) )
        ( json_obj_set st `created` ( json_int ( _ana_jint params `created` 0 ) ) )
        ( json_obj_set st `name` ( json_str_lit ( json_as_str ?? ( json_obj_get params `name` ) { T v → v F _ → @ Json { JNull } } ) ) )
        = ok ( analyze_status_write ( string_data dir ) st )
        ( json_free st )
    } {}
    ( string_free dir )
    ? ok { ^ id } {}
    ( string_free id )
    ^ ( string_new )
}

// Every task of the organisation, newest first: the status records, each
// with its `id`.
@ analyze_task_list s org → Json {
    : String d ( orgfiles_tasks_dir org )
    : Json out ( json_arr_new )
    : ( Vec Json ) items ( vec_new [Json] )
    ?? ( dir_list ( string_data d ) ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String td ( analyze_task_dir org ( string_data nm ) )
                        ?? ( analyze_status_read ( string_data td ) ) {
                            T st → {
                                ( json_obj_set st `id` ( json_str_lit ( string_data nm ) ) )
                                ( vec_push [Json] items st )
                            }
                            F _ → {}
                        }
                        ( string_free td )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ( string_free d )
    // Newest first, by `created`; a handful of tasks, so an insertion sort.
    : i n ( vec_len [Json] items )
    : ~ i i 1
    ~ < i n {
        : ~ i j i
        ~ > j 0 {
            : Json a ?? ( vec_get [Json] items - j 1 ) { T x → x F _ → @ Json { JNull } }
            : Json b ?? ( vec_get [Json] items j ) { T x → x F _ → @ Json { JNull } }
            ? < ( _ana_jint a `created` 0 ) ( _ana_jint b `created` 0 ) {
                ( vec_set [Json] items - j 1 b )
                ( vec_set [Json] items j a )
                = j - j 1
            } { = j 0 }
        }
        = i + i 1
    }
    = i 0
    ~ < i n {
        ?? ( vec_get [Json] items i ) { T x → { ( json_arr_push out x ) } F _ → {} }
        = i + i 1
    }
    ( vec_free [Json] items )
    ^ out
}

@ analyze_task_delete s org s id → b {
    : String d ( analyze_task_dir org id )
    : ~ b ok F
    ? ( file_exists ( string_data d ) ) {
        ?? ( dir_remove_all ( string_data d ) ) { T _ → { = ok T } F _ → {} }
    } {}
    ( string_free d )
    ^ ok
}

// ── Running the job ───────────────────────────────────────────────────

// The service's own binary: the job is the same program in another
// process.
// The binary that runs jobs: this one, normally. A test binary is not
// `anomaly` — re-spawning it would run the whole suite again, in the
// same store — so tests point this at something harmless.
: ~ s g_ana_exe ``

@ analyze_set_exe s exe → v { = g_ana_exe exe }

@ analyze_exe → String {
    ? > ( nurl_str_len g_ana_exe ) 0 { ^ ( string_from g_ana_exe ) } {}
    ?? ( fs_readlink `/proc/self/exe` ) {
        T p → { ^ p }
        F _ → {}
    }
    ^ ( string_from `anomaly` )
}

// The child died without writing a final status: say so. A status the
// job wrote itself stands.
@ _ana_mark_crashed s dir i code s detail → v {
    : String state ( analyze_state dir )
    : b final ( analyze_state_final ( string_data state ) )
    ( string_free state )
    ? final { ^ } {}
    : Json st ?? ( analyze_status_read dir ) { T j → j F _ → ( json_obj_new ) }
    ( json_obj_set st `state` ( json_str_lit `failed` ) )
    : String msg ( string_from `the analysis process exited with code ` )
    ( string_push_int msg code )
    ? > ( nurl_str_len detail ) 0 {
        ( string_push_str msg `: ` )
        // The tail of what it said: the last 400 bytes hold the message.
        : i n ( nurl_str_len detail )
        : String whole ( string_from detail )
        : String tail ? > n 400 ( string_substr whole - n 400 400 ) ( string_clone whole )
        ( string_free whole )
        : String trimmed ( string_trim tail )
        ( string_push_str msg ( string_data trimmed ) )
        ( string_free trimmed )
        ( string_free tail )
    } {}
    ( json_obj_set st `error` ( json_str_lit ( string_data msg ) ) )
    ( json_obj_set st `finished` ( json_int ( now_seconds ) ) )
    ( analyze_status_write dir st )
    ( json_free st )
    ( string_free msg )
}

// Start the job for a task: a thread runs the child process to its end
// and records a crash. The thread shares nothing with the service but the
// task directory. Returns F when no thread could be started.
@ analyze_spawn s org s id → b {
    : String exe ( analyze_exe )
    : String dir ( analyze_task_dir org id )
    : ( @ v ) body \ → v {
        : ( Vec s ) args ( vec_new [s] )
        ( vec_push [s] args `analyze-job` )
        ( vec_push [s] args ( string_data dir ) )
        : !Output ProcessErr r ( process_run ( string_data exe ) args `` )
        ?? r {
            T out → {
                ? ( output_success out ) {} {
                    ( _ana_mark_crashed ( string_data dir ) ( output_exit_code out ) ( output_stderr out ) )
                }
                ( output_free out )
            }
            F e → { ( _ana_mark_crashed ( string_data dir ) -1 ( process_err_name e ) ) }
        }
        ( vec_free [s] args )
        ( string_free dir )
        ( string_free exe )
    }
    // Detached and forgotten: the thread frees the closure's env when the
    // body returns, and the body frees what it captured.
    ?? ( thread_spawn_owned body ) {
        T t → { ( thread_detach t ) ^ T }
        F _ → {}
    }
    ( nurl_free # s # *u body 1 )
    ( string_free dir )
    ( string_free exe )
    ^ F
}

// ── The job itself: `anomaly analyze-job <dir>` ───────────────────────

@ __ana_fail s dir s msg → i {
    : Json st ?? ( analyze_status_read dir ) { T j → j F _ → ( json_obj_new ) }
    ( json_obj_set st `state` ( json_str_lit `failed` ) )
    ( json_obj_set st `error` ( json_str_lit msg ) )
    ( json_obj_set st `finished` ( json_int ( now_seconds ) ) )
    ( analyze_status_write dir st )
    ( json_free st )
    ( nurl_eprint `anomaly analyze-job: ` )
    ( nurl_eprintln msg )
    ^ 1
}

// The temporary store and the input are dropped once the result exists:
// the folder keeps the result, the status keeps the numbers.
@ __ana_cleanup s dir → v {
    : String sp ( __ana_file dir `store` )
    ?? ( dir_remove_all ( string_data sp ) ) { T _ → {} F _ → {} }
    ( string_free sp )
    : String ip ( __ana_file dir `input` )
    ?? ( file_delete ( string_data ip ) ) { T _ → {} F _ → {} }
    ( string_free ip )
}

@ analyze_run s dir → i {
    : Json params ?? ( __ana_read_json dir `params.json` ) { T j → j F _ → ( json_obj_new ) }
    : String org ( _ana_jstr params `org` )
    : String id ( _ana_jstr params `id` )
    ? & > ( string_len org ) 0 > ( string_len id ) 0 {} {
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ ( __ana_fail dir `params.json is missing or names no task` )
    }
    // The store root the service named: the result goes into the
    // organisation's folder beside it.
    : String root ( _ana_jstr params `root` )
    ? > ( string_len root ) 0 { ( orgfiles_set_root ( string_data root ) ) } {}
    ( string_free root )
    : Json st ?? ( analyze_status_read dir ) { T j → j F _ → ( json_obj_new ) }
    ( json_obj_set st `state` ( json_str_lit `running` ) )
    ( json_obj_set st `started` ( json_int ( now_seconds ) ) )
    ( analyze_status_write dir st )

    // The file.
    : String ip ( __ana_file dir `input` )
    : ~ String body ( string_new )
    : ~ b have F
    ?? ( read_file ( string_data ip ) ) { T t → { ( string_free body ) = body t = have T } F _ → {} }
    ( string_free ip )
    ? have {} {
        ( string_free body )
        ( json_free st )
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ ( __ana_fail dir `the input file could not be read` )
    }
    : String fmt ( _ana_jstr params `format` )
    : ImportParse ip2 ( import_parse ( string_data body ) ( string_data fmt ) )
    ( string_free fmt )
    ( string_free body )
    ? > ( string_len . ip2 err ) 0 {
        : i rc ( __ana_fail dir ( string_data . ip2 err ) )
        ( import_parse_free ip2 )
        ( json_free st )
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ rc
    } {}
    : i nrows ( vec_len [Json] . ip2 rows )
    ? < nrows ANA_MIN_ROWS {
        : String m ( string_from `too few rows to analyse: ` )
        ( string_push_int m nrows )
        ( string_push_str m ` (at least ` )
        ( string_push_int m ANA_MIN_ROWS )
        ( string_push_str m ` are needed)` )
        : i rc ( __ana_fail dir ( string_data m ) )
        ( string_free m )
        ( import_parse_free ip2 )
        ( json_free st )
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ rc
    } {}

    // The time plan, as an import would make it.
    : Json spec ?? ( json_obj_get params `time` ) { T t → ( json_clone t ) F _ → ( json_obj_new ) }
    : i tz ( imp_tz_of spec )
    : b calendar ( _ana_jbool params `calendar` )
    : Json insp ( import_inspect . ip2 rows spec tz )
    ( json_free spec )
    : Json plan ?? ( json_obj_get insp `time` ) { T tp → ( json_clone tp ) F _ → ( json_obj_new ) }
    ( json_free insp )
    ? ( json_obj_has plan `error` ) {
        : s perr ?? ( json_obj_get plan `error` ) { T e → ( json_str_data e ) F _ → `bad time plan` }
        : i rc ( __ana_fail dir perr )
        ( json_free plan )
        ( import_parse_free ip2 )
        ( json_free st )
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ rc
    } {}
    : ImpTimeResult tr ( import_time_apply . ip2 rows plan calendar tz )

    // The throwaway model.
    : String sp ( __ana_file dir `store` )
    ?? ( dir_create_all ( string_data sp ) ) { T _ → {} F _ → {} }
    : Store store ( store_open ( string_data sp ) )
    ( string_free sp )
    : *Model mo ( model_open store `analysis` )
    : *Meta mm . mo meta
    : String clockq ( _ana_jstr params `clock` )
    : ~ b count == . tr stamped 0
    ? == ( nurl_str_eq ( string_data clockq ) `count` ) 1 { = count T } {}
    ? == ( nurl_str_eq ( string_data clockq ) `time` ) 1 { = count F } {}
    ( string_free clockq )
    = . mm count_clock count
    // The whole file fits: the ring grows to the file, and the warm-up
    // shrinks to it, so a short file still gets a verdict.
    : i minp ? < nrows ANOM_MIN_POINTS nrows ANOM_MIN_POINTS
    : i maxp ? > nrows ANOM_MAX_POINTS nrows ANOM_MAX_POINTS
    ( model_set_limits mo minp maxp )

    : ImportReport rep ( model_import mo . ip2 rows )
    ? > ( string_len . rep err ) 0 {
        : i rc ( __ana_fail dir ( string_data . rep err ) )
        ( import_report_free rep )
        ( imp_time_result_free tr )
        ( json_free plan )
        ( model_free mo )
        ( store_free store )
        ( import_parse_free ip2 )
        ( json_free st )
        ( string_free org )
        ( string_free id )
        ( json_free params )
        ^ rc
    } {}

    // Train: every forest over the whole file, the autoencoder over the
    // forest-filtered points, every margin at the target rate — the batch
    // recipe (model_train_whole), shared with a model forked from another
    // model's history.
    : ( Vec i ) dflt_layout ( vec_new [i] )
    : WholeTrain wt ( model_train_whole mo ANA_TARGET_RATE dflt_layout )
    ( vec_free [i] dflt_layout )
    : Json notes . wt notes
    : Json margins . wt margins

    // Scan everything, keep the anomalies.
    : ScanOut so ( model_scan mo 0 0 0 F )
    : Json vers ( json_arr_new )
    : i nvn ( vec_len [String] . so vnames )
    : ~ i k 0
    ~ < k nvn {
        ?? ( vec_get [String] . so vnames k ) {
            T nm → { ( json_arr_push vers ( json_str_lit ( string_data nm ) ) ) }
            F _ → {}
        }
        = k + k 1
    }
    // Every version is calibrated to the target rate on its own, and a
    // point is an anomaly when ANY of them says so — six detectors that
    // look for different things (a lone outlier, a broken sequence, a
    // broken relation) agree less than fully, so the union runs above
    // the target. `votes` asks for agreement: keep a point only when at
    // least that many versions flagged it.
    : ~ i minvotes ( _ana_jint params `votes` 1 )
    ? < minvotes 1 { = minvotes 1 } {}
    : Json pts ( json_arr_new )
    : ~ i nanom 0
    : i np ( vec_len [ScoredPt] . so pts )
    = k 0
    ~ < k np {
        ?? ( vec_get [ScoredPt] . so pts k ) {
            T r → {
                : Json flagged ( json_arr_new )
                : ~ i votes 0
                : ~ i b 0
                ~ < b nvn {
                    ? != & >> . r sp_flagged b 1 0 {
                        ?? ( vec_get [String] . so vnames b ) {
                            T nm → {
                                ( json_arr_push flagged ( json_str_lit ( string_data nm ) ) )
                                = votes + votes 1
                            }
                            F _ → {}
                        }
                    } {}
                    = b + b 1
                }
                ? & . r sp_anomaly >= votes minvotes {
                    = nanom + nanom 1
                    : Json o ( json_obj_new )
                    ( json_obj_set o `index` ( json_int . r sp_idx ) )
                    ( json_obj_set o `timestamp` ( json_int . r sp_ts ) )
                    ( json_obj_set o `score` ( json_float . r sp_score ) )
                    ( json_obj_set o `votes` ( json_int votes ) )
                    ( json_obj_set o `versions` flagged )
                    ?? ( model_point_json mo . r sp_idx ) {
                        T rec → {
                            : ( Vec AeContrib ) cs ( model_ae_contrib mo rec 3 )
                            : i nc ( vec_len [AeContrib] cs )
                            ? > nc 0 {
                                : Json ca ( json_arr_new )
                                : ~ i ci 0
                                ~ < ci nc {
                                    ?? ( vec_get [AeContrib] cs ci ) {
                                        T c → {
                                            : Json co ( json_obj_new )
                                            ( json_obj_set co `feature` ( json_str_lit ( string_data . c ac_name ) ) )
                                            ( json_obj_set co `share` ( json_float . c ac_share ) )
                                            ( json_obj_set co `value` ( json_float . c ac_value ) )
                                            ( json_obj_set co `expected` ( json_float . c ac_expected ) )
                                            ( json_arr_push ca co )
                                        }
                                        F _ → {}
                                    }
                                    = ci + ci 1
                                }
                                ( json_obj_set o `contributions` ca )
                            } {}
                            ( ae_contrib_free cs )
                            ( json_obj_set o `values` rec )
                        }
                        F _ → {}
                    }
                    ( json_arr_push pts o )
                } { ( json_free flagged ) }
            }
            F _ → {}
        }
        = k + k 1
    }

    // The result file, into the organisation's folder.
    : String label ( _ana_jstr params `name` )
    : ~ String base ( orgfiles_safe_name ( string_data label ) )
    ( string_free label )
    ? == ( string_len base ) 0 { ( string_free base ) = base ( string_from `analysis` ) } {}
    : String fname ( string_clone base )
    ( string_push_char fname 45 )
    ( string_push_str fname ( string_data id ) )
    ( string_push_str fname `.json` )
    ( string_free base )

    : Json res ( json_obj_new )
    ( json_obj_set res `task_id` ( json_str_lit ( string_data id ) ) )
    ( json_obj_set res `name` ( json_str_lit ( json_as_str ?? ( json_obj_get st `name` ) { T v → v F _ → @ Json { JNull } } ) ) )
    ( json_obj_set res `format` ( json_str_lit ( string_data . ip2 format ) ) )
    ( json_obj_set res `rows` ( json_int nrows ) )
    ( json_obj_set res `imported` ( json_int . rep accepted ) )
    ( json_obj_set res `skipped` ( json_int + . ip2 skipped . rep rejected ) )
    ( json_obj_set res `clock` ( json_str_lit ? count `count` `time` ) )
    ( json_obj_set res `target_rate` ( json_float ANA_TARGET_RATE ) )
    ( json_obj_set res `votes` ( json_int minvotes ) )
    ( json_obj_set res `anomalies` ( json_int nanom ) )
    ( json_obj_set res `considered` ( json_int . so considered ) )
    ( json_obj_set res `model_versions` ( json_clone vers ) )
    ( json_obj_set res `margins` ( json_clone margins ) )
    : Json tj ( json_clone plan )
    ( json_obj_set tj `stamped` ( json_int . tr stamped ) )
    ( json_obj_set tj `failed` ( json_int . tr failed ) )
    ( json_obj_set res `time` tj )
    ( json_obj_set res `notes` ( json_clone notes ) )
    ( json_obj_set res `points` pts )
    : String rtxt ( json_stringify res )
    : ( Vec u ) rbytes ( bytes_from_str ( string_data rtxt ) )
    : i rsize ( vec_len [u] rbytes )
    : b wrote ( orgfiles_write ( string_data org ) ( string_data fname ) rbytes )
    ( vec_free [u] rbytes )
    ( string_free rtxt )
    ( json_free res )

    : ~ i rc 0
    ? wrote {
        ( json_obj_set st `state` ( json_str_lit `done` ) )
        ( json_obj_set st `finished` ( json_int ( now_seconds ) ) )
        ( json_obj_set st `rows` ( json_int nrows ) )
        ( json_obj_set st `imported` ( json_int . rep accepted ) )
        ( json_obj_set st `skipped` ( json_int + . ip2 skipped . rep rejected ) )
        ( json_obj_set st `votes` ( json_int minvotes ) )
        ( json_obj_set st `anomalies` ( json_int nanom ) )
        ( json_obj_set st `considered` ( json_int . so considered ) )
        ( json_obj_set st `model_versions` vers )
        ( json_obj_set st `margins` margins )
        ( json_obj_set st `notes` notes )
        ( json_obj_set st `file` ( json_str_lit ( string_data fname ) ) )
        ( json_obj_set st `size` ( json_int rsize ) )
        ( analyze_status_write dir st )
    } {
        ( json_free vers )
        ( json_free margins )
        ( json_free notes )
        = rc ( __ana_fail dir `the result could not be written to the organisation's folder` )
    }
    ( string_free fname )
    ( scan_free so )
    ( import_report_free rep )
    ( imp_time_result_free tr )
    ( json_free plan )
    ( model_free mo )
    ( store_free store )
    ( import_parse_free ip2 )
    ( json_free st )
    ( string_free org )
    ( string_free id )
    ( json_free params )
    ( __ana_cleanup dir )
    ^ rc
}
