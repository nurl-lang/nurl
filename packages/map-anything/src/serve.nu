// packages/map-anything/src/serve.nu — `map-anything serve`: the web
// service.
//
//   map-anything serve [--host A] [--port N] [--data DIR] [--password P]
//
// A browser uploads photos or a video, the service reconstructs them, and
// the cloud comes back in the ply viewer or as a PLY download.
//
//   GET    /                          the page (ui.nu)
//   GET    /view?cloud=URL            the ply package's WebGL viewer
//   GET    /healthz                   liveness, never behind the password
//   GET    /api/jobs                  every job, newest first
//   POST   /api/jobs                  {name} → a new job, state "uploading"
//   PUT    /api/jobs/:id/files/:name  one input file, the raw request body
//   POST   /api/jobs/:id/start        {max_views, fps, ...} → "queued"
//   GET    /api/jobs/:id              one job, with its whole log
//   DELETE /api/jobs/:id              the job and its files
//   GET    /jobs/:id/cloud.ply        the result
//
// The state is the filesystem, nothing else: a job is a directory
// <data>/jobs/<id>/ holding input/, a `state` word, `name`, `opts`,
// `created`/`started`/`finished` (unix ms), the run's `log` and, once done,
// `cloud.ply`. A restart loses nothing, and a job a restart interrupted is
// queued again.
//
// ONE worker thread takes the queued jobs oldest first and runs each as a
// child process of this same executable — `map-anything <input> -o ...` —
// with the CLI's output going to the job's log, which is what the page
// shows as progress. A child per job rather than the model in this process,
// because the server then holds no GPU memory between jobs (the card is
// shared with other services), a failed run cannot take the server down,
// and the CLI stays the single implementation of the pipeline. The model
// load it costs is a few seconds from the page cache against a run of
// tens of seconds.
//
// Ids are `<unix ms>-<random hex>`: they sort by creation, and they are
// the only part of a path a client chooses besides a file name — both are
// checked to a closed alphabet before they touch the filesystem.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `deps/ply/src/view.nu`
$ `deps/video/src/video.nu`
$ `ui.nu`

// ── configuration ───────────────────────────────────────────────────

: MaCfg {
    String data  // the data root, e.g. ~/.map-anything
    String bin  // this executable, run once per job
    String pass  // HTTP Basic password; empty = no sign-in
}

@ __mas_cfg_blank → ( Locked MaCfg ) {
    ^ ( locked_new [MaCfg] @ MaCfg { ( string_new ) ( string_new ) ( string_new ) } )
}

: ( Locked MaCfg ) g_mas_cfg ( __mas_cfg_blank )

@ __mas_cfg → MaCfg { ^ ( locked_get [MaCfg] g_mas_cfg ) }

// ── small helpers ───────────────────────────────────────────────────

@ __mas_eq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __mas_now → String {
    : String t ( string_new )
    ( string_push_int t ( now_ms ) )
    ^ t
}

// A job id as made by __mas_new_id: digits, lowercase hex and '-'.
@ __mas_id_ok s id → b {
    : ( Slice u ) bs ( slice_of_str id )
    : i n ( slice_len [u] bs )
    ? | < n 1 > n 48 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte bs k )
        ? | | & >= c 48 <= c 57 & >= c 97 <= c 102 == c 45 {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __mas_new_id → String {
    : String id ( __mas_now )
    ( string_push_char id 45 )
    : String rh ( rand_hex_str 3 )
    ( string_push_str id ( string_data rh ) )
    ^ id
}

// A client's file name, reduced to [A-Za-z0-9._-] (anything else becomes
// '_'), never starting with '.', at most 120 bytes. The extension survives,
// which is what decides image vs video.
@ __mas_safe_name s raw → String {
    : String out ( string_new )
    : ( Slice u ) bs ( slice_of_str raw )
    : i n ( slice_len [u] bs )
    : ~ i k 0
    ~ & < k n < k 120 {
        : i c ( slice_byte bs k )
        : b alnum | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122
        : b punct | | == c 46 == c 45 == c 95
        : b lead_dot & == k 0 == c 46
        ? & | alnum punct == lead_dot F { ( string_push_char out c ) } { ( string_push_char out 95 ) }
        = k + k 1
    }
    ^ out
}

// Free text from a client (a job's name), kept to printable bytes and cut
// at `max` bytes on a UTF-8 character boundary.
@ __mas_clip s raw i max → String {
    : String out ( string_new )
    : ( Slice u ) bs ( slice_of_str raw )
    : i n ( slice_len [u] bs )
    : ~ i k 0
    : ~ b more T
    ~ & more < k n {
        : i c ( slice_byte bs k )
        ? & >= ( string_len out ) max != 128 & c 192 { = more F } {
            ? & >= c 32 != c 127 { ( string_push_char out c ) } {}
            = k + k 1
        }
    }
    ^ out
}

// Append `text` to `cmd` as one single-quoted /bin/sh word.
@ __mas_q String cmd s text → v {
    ( string_push_char cmd 39 )
    : ( Slice u ) bs ( slice_of_str text )
    : i n ( slice_len [u] bs )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte bs k )
        ? == c 39 { ( string_push_str cmd `'\''` ) } { ( string_push_char cmd c ) }
        = k + k 1
    }
    ( string_push_char cmd 39 )
}

// The options line handed to the CLI is built by __mas_start from
// validated integers; this re-checks it before it reaches a shell.
@ __mas_opts_ok s opts → b {
    : ( Slice u ) bs ( slice_of_str opts )
    : i n ( slice_len [u] bs )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte bs k )
        ? | | & >= c 48 <= c 57 & >= c 97 <= c 122 | | == c 45 == c 32 == c 46 {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __mas_is_image s name → b {
    : String lo ( string_new )
    : ( Slice u ) bs ( slice_of_str name )
    : i n ( slice_len [u] bs )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte bs k )
        ( string_push_char lo ? & >= c 65 <= c 90 + c 32 c )
        = k + k 1
    }
    ? ( string_ends_with lo `.jpg` ) { ^ T } {}
    ? ( string_ends_with lo `.jpeg` ) { ^ T } {}
    ^ ( string_ends_with lo `.png` )
}

// ── the job directory ───────────────────────────────────────────────

@ __mas_jobs_dir → String {
    : MaCfg c ( __mas_cfg )
    : String d ( path_join ( string_data . c data ) `jobs` )
    ^ d
}

@ __mas_jdir s id → String {
    : String jd ( __mas_jobs_dir )
    : String d ( path_join ( string_data jd ) id )
    ^ d
}

@ __mas_jfile s id s name → String {
    : String jd ( __mas_jdir id )
    : String p ( path_join ( string_data jd ) name )
    ^ p
}

@ __mas_read s path → String {
    ?? ( read_file path ) {
        T t → {
            : String r ( string_trim t )
            ^ r
        }
        F _e → { ^ ( string_new ) }
    }
}

@ __mas_read_job s id s name → String {
    : String p ( __mas_jfile id name )
    : String r ( __mas_read ( string_data p ) )
    ^ r
}

@ __mas_read_int s id s name → i {
    : String t ( __mas_read_job id name )
    ? == ( string_len t ) 0 { ^ 0 } {}
    ^ ( nurl_str_to_int ( string_data t ) )
}

// Written beside and renamed over, so a reader never sees half a file.
@ __mas_write_job s id s name s text → b {
    : String p ( __mas_jfile id name )
    : String tmp ( string_from ( string_data p ) )
    ( string_push_str tmp `.tmp` )
    ?? ( write_file ( string_data tmp ) text ) {
        T _ → {}
        F _e → { ^ F }
    }
    ?? ( fs_rename ( string_data tmp ) ( string_data p ) ) {
        T _ → { ^ T }
        F _e → { ^ F }
    }
}

@ __mas_state s id → String {
    : String st ( __mas_read_job id `state` )
    ^ st
}

@ __mas_state_is s id s want → b {
    : String st ( __mas_state id )
    ^ ( __mas_eq ( string_data st ) want )
}

@ __mas_set_state s id s st → b { ^ ( __mas_write_job id `state` st ) }

// Every job id under jobs/, oldest first.
@ __mas_job_ids → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String jd ( __mas_jobs_dir )
    ?? ( dir_list ( string_data jd ) ) {
        F _e → {}
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( __mas_id_ok ( string_data nm ) ) {
                            ( vec_push [String] out ( string_from ( string_data nm ) ) )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
    }
    ( sort_by [String] out \ String x String y → i {
        ^ ( nurl_str_cmp ( string_data x ) ( string_data y ) ) } )
    ^ out
}

// The input to hand the CLI: the one video, or the input directory when
// it holds photos. F carries the reason there is nothing to run.
@ __mas_input s id → !String String {
    : String ind ( __mas_jfile id `input` )
    : ~ i nimg 0
    : ~ i nvid 0
    : ~ String vid ( string_new )
    ?? ( dir_list ( string_data ind ) ) {
        F _e → { ^ @ !String String { F ( string_from `the job has no input directory` ) } }
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String p ( path_join ( string_data ind ) ( string_data nm ) )
                        ? == 1 ( nurl_path_type ( string_data p ) ) {
                            ? ( vid_is_video ( string_data p ) ) {
                                = nvid + nvid 1
                                = vid p
                            } {
                                ? ( __mas_is_image ( string_data nm ) ) { = nimg + nimg 1 } {}
                            }
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
    }
    ? > nvid 1 { ^ @ !String String { F ( string_from `upload one video per job` ) } } {}
    ? & == nvid 1 > nimg 0 { ^ @ !String String { F ( string_from `a job takes a video or photos, not both` ) } } {}
    ? == nvid 1 { ^ @ !String String { T vid } } {}
    ? > nimg 0 { ^ @ !String String { T ind } } {}
    ^ @ !String String { F ( string_from `no .jpg / .png photos and no video in the upload` ) }
}

// Files in input/ and their total size.
@ __mas_input_stats s id inout i nfiles inout i nbytes → v {
    : String ind ( __mas_jfile id `input` )
    = nfiles 0
    = nbytes 0
    ?? ( dir_list ( string_data ind ) ) {
        F _e → {}
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String p ( path_join ( string_data ind ) ( string_data nm ) )
                        ? == 1 ( nurl_path_type ( string_data p ) ) {
                            = nfiles + nfiles 1
                            ?? ( file_size ( string_data p ) ) { T z → { = nbytes + nbytes z } F _e → {} }
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
    }
}

// The last non-empty line of a log the CLI wrote, where `\r` also ends a
// line (its progress counters rewrite one line in place).
@ __mas_last_line String log → String {
    : i n ( string_len log )
    : ~ i e n
    : ~ b skip T
    ~ & skip > e 0 {
        : i c ( string_get log - e 1 )
        ? | | == c 10 == c 13 == c 32 { = e - e 1 } { = skip F }
    }
    : ~ i st e
    : ~ b back T
    ~ & back > st 0 {
        : i c ( string_get log - st 1 )
        ? | == c 10 == c 13 { = back F } { = st - st 1 }
    }
    : String r ( string_substr log st - e st )
    ^ r
}

// "wrote   cloud.ply (278380 points)" → 278380, 0 when not there yet.
@ __mas_points String log → i {
    : ?i at ( string_index_of log `wrote   ` )
    ?? at {
        F _ → { ^ 0 }
        T w → {
            : i n ( string_len log )
            : ~ i k w
            ~ & < k n != ( string_get log k ) 40 { = k + k 1 }
            : ~ i v 0
            = k + k 1
            ~ & < k n & >= ( string_get log k ) 48 <= ( string_get log k ) 57 {
                = v + * v 10 - ( string_get log k ) 48
                = k + k 1
            }
            ^ v
        }
    }
}

@ __mas_job_json s id b with_log → Json {
    : Json o ( json_obj_new )
    : String st ( __mas_state id )
    : String nm ( __mas_read_job id `name` )
    : String opts ( __mas_read_job id `opts` )
    : ~ i nfiles 0
    : ~ i nbytes 0
    ( __mas_input_stats id nfiles nbytes )
    : String logp ( __mas_jfile id `log` )
    : ~ String log ( string_new )
    ?? ( read_file ( string_data logp ) ) { T t → { = log t } F _e → {} }
    : String cloudp ( __mas_jfile id `cloud.ply` )
    : ~ i cbytes 0
    ?? ( file_size ( string_data cloudp ) ) { T z → { = cbytes z } F _e → {} }
    : b _a ( json_obj_set o `id` ( json_str_lit id ) )
    : b _b ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
    : b _c ( json_obj_set o `state` ( json_str_lit ( string_data st ) ) )
    : b _d ( json_obj_set o `created` ( json_int ( __mas_read_int id `created` ) ) )
    : b _e ( json_obj_set o `started` ( json_int ( __mas_read_int id `started` ) ) )
    : b _f ( json_obj_set o `finished` ( json_int ( __mas_read_int id `finished` ) ) )
    : b _g ( json_obj_set o `opts` ( json_str_lit ( string_data opts ) ) )
    : b _h ( json_obj_set o `files` ( json_int nfiles ) )
    : b _i ( json_obj_set o `input_bytes` ( json_int nbytes ) )
    : b _j ( json_obj_set o `cloud_bytes` ( json_int cbytes ) )
    : b _k ( json_obj_set o `points` ( json_int ( __mas_points log ) ) )
    : String last ( __mas_last_line log )
    : b _l ( json_obj_set o `progress` ( json_str_lit ( string_data last ) ) )
    ? with_log {
        : b _m ( json_obj_set o `log` ( json_str_lit ( string_data log ) ) )
    } {}
    ^ o
}

// ── the worker ──────────────────────────────────────────────────────

@ __mas_next_queued → String {
    : ( Vec String ) ids ( __mas_job_ids )
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T id → {
                ? ( __mas_state_is ( string_data id ) `queued` ) {
                    ^ ( string_from ( string_data id ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ ( string_new )
}

@ __mas_log_put s id s text → v {
    : String logp ( __mas_jfile id `log` )
    ?? ( write_file ( string_data logp ) text ) { T _ → {} F _e → {} }
}

@ __mas_run s id → v {
    : MaCfg c ( __mas_cfg )
    : String jd ( __mas_jdir id )
    : b _r ( __mas_set_state id `running` )
    : String t0 ( __mas_now )
    : b _t ( __mas_write_job id `started` ( string_data t0 ) )
    : b _f ( __mas_write_job id `finished` `0` )
    : ~ b ok F
    ?? ( __mas_input id ) {
        F why → {
            ( __mas_log_put id ( string_data why ) )
        }
        T inp → {
            : String opts ( __mas_read_job id `opts` )
            ? ( __mas_opts_ok ( string_data opts ) ) {
                : String tmp ( path_join ( string_data jd ) `cloud.tmp.ply` )
                : String out ( path_join ( string_data jd ) `cloud.ply` )
                // run in the job directory, so the log the page shows names
                // the job's own files and not the server's data path
                : String cmd ( string_from `cd ` )
                ( __mas_q cmd ( string_data jd ) )
                ( string_push_str cmd ` && exec ` )
                ( __mas_q cmd ( string_data . c bin ) )
                ( string_push_char cmd 32 )
                ( __mas_q cmd ( string_data inp ) )
                ( string_push_str cmd ` -o cloud.tmp.ply ` )
                ( string_push_str cmd ( string_data opts ) )
                ( string_push_str cmd ` < /dev/null > log 2>&1` )
                ( nurl_eprint `map-anything serve: job ` )
                ( nurl_eprint id )
                ( nurl_eprint ` running: ` )
                ( nurl_eprintln ( string_data opts ) )
                ?? ( process_run_shell ( string_data cmd ) ) {
                    T o → {
                        ? == 0 ( output_exit_code o ) {
                            ?? ( fs_rename ( string_data tmp ) ( string_data out ) ) {
                                T _ → { = ok T }
                                F _e → {}
                            }
                        } {}
                    }
                    F _e → { ( __mas_log_put id `map-anything serve: could not start the reconstruction` ) }
                }
            } {
                ( __mas_log_put id `map-anything serve: the job's options are malformed` )
            }
        }
    }
    : String t1 ( __mas_now )
    : b _e ( __mas_write_job id `finished` ( string_data t1 ) )
    : b _s ( __mas_set_state id ? ok `done` `failed` )
    ( nurl_eprint `map-anything serve: job ` )
    ( nurl_eprint id )
    ( nurl_eprintln ? ok ` done` ` failed` )
}

@ __mas_worker → v {
    ~ T {
        : String id ( __mas_next_queued )
        ? > ( string_len id ) 0 { ( __mas_run ( string_data id ) ) } { ( sleep_ms 1000 ) }
    }
}

// A job the last process was running when it stopped runs again.
@ __mas_recover → v {
    : ( Vec String ) ids ( __mas_job_ids )
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T id → {
                ? ( __mas_state_is ( string_data id ) `running` ) {
                    : b _q ( __mas_set_state ( string_data id ) `queued` )
                    ( nurl_eprint `map-anything serve: re-queued the interrupted job ` )
                    ( nurl_eprintln ( string_data id ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
}

// ── HTTP ────────────────────────────────────────────────────────────

@ __mas_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

@ __mas_param Params ps s key → String {
    ?? ( params_get ps key ) {
        T v → { ^ v }
        F → { ^ ( string_new ) }
    }
}

@ __mas_jint Json root s key i lo i hi i dflt → i {
    ?? ( json_obj_get root key ) {
        T v → {
            ?? ( json_num_as_i v ) {
                T x → { ^ ? < x lo lo ? > x hi hi x }
                F → { ^ dflt }
            }
        }
        F → { ^ dflt }
    }
}

@ __mas_jbool Json root s key → b {
    ?? ( json_obj_get root key ) {
        T v → { ? ( json_is_bool v ) { ^ ( json_bool_val v ) } { ^ F } }
        F → { ^ F }
    }
}

// Every byte of the configured password is compared, and a length
// mismatch folds into the same accumulator: no early exit to time.
@ __mas_authed HttpRequest req → b {
    : MaCfg c ( __mas_cfg )
    : s want ( string_data . c pass )
    : i wn ( nurl_str_len want )
    ? == wn 0 { ^ T } {}
    ?? ( parse_basic_auth req ) {
        F _ → { ^ F }
        T ba → {
            : s got ( string_data . ba pass )
            : i gn ( nurl_str_len got )
            : ( Slice u ) gv ( slice_of_str got )
            : ( Slice u ) wv ( slice_of_str want )
            : ~ i diff ^^ gn wn
            : ~ i k 0
            ~ < k wn {
                : i a ? < k gn ( slice_byte gv k ) 0
                = diff | diff ^^ a ( slice_byte wv k )
                = k + k 1
            }
            ^ == diff 0
        }
    }
}

@ __mas_page → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_header r `Cache-Control` `no-store` )
    ( response_set_body_str r ( mas_ui_html ) )
    ^ r
}

@ __mas_viewer → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_header r `Cache-Control` `no-store` )
    : String page ( vw_page `` )
    ( response_set_body_str r ( string_data page ) )
    ^ r
}

@ __mas_list → HttpResponse {
    : ( Vec String ) ids ( __mas_job_ids )
    : Json arr ( json_arr_new )
    : ~ i k - ( vec_len [String] ids ) 1
    ~ >= k 0 {
        ?? ( vec_get [String] ids k ) {
            T id → { : b _p ( json_arr_push arr ( __mas_job_json ( string_data id ) F ) ) }
            F → {}
        }
        = k - k 1
    }
    : Json o ( json_obj_new )
    : b _j ( json_obj_set o `jobs` arr )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

@ __mas_create HttpRequest req → HttpResponse {
    : ~ String name ( string_new )
    ?? ( json_parse_bytes . req body ) {
        T j → {
            ?? ( json_obj_get j `name` ) {
                T v → { ? ( json_is_str v ) { = name ( __mas_clip ( json_as_str v ) 120 ) } {} }
                F → {}
            }
        }
        F _e → {}
    }
    : String id ( __mas_new_id )
    : String ind ( __mas_jfile ( string_data id ) `input` )
    ?? ( dir_create_all ( string_data ind ) ) {
        T _ → {}
        F _e → { ^ ( __mas_err 500 `cannot create the job directory` ) }
    }
    : String t0 ( __mas_now )
    : b _n ( __mas_write_job ( string_data id ) `name` ( string_data name ) )
    : b _c ( __mas_write_job ( string_data id ) `created` ( string_data t0 ) )
    : b _s ( __mas_set_state ( string_data id ) `uploading` )
    : HttpResponse r ( response_json 201 ( __mas_job_json ( string_data id ) F ) )
    ^ r
}

@ __mas_upload HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    ? ( __mas_state_is ( string_data id ) `uploading` ) {} {
        ^ ( __mas_err 409 `the job is not taking uploads` )
    }
    : String raw ( __mas_param ps `name` )
    : String fname ( __mas_safe_name ( string_data raw ) )
    ? == ( string_len fname ) 0 { ^ ( __mas_err 400 `the file needs a name` ) } {}
    : String ind ( __mas_jfile ( string_data id ) `input` )
    : String fp ( path_join ( string_data ind ) ( string_data fname ) )
    ?? ( write_file_bytes ( string_data fp ) . req body ) {
        T _ → {}
        F _e → { ^ ( __mas_err 500 `cannot store the file` ) }
    }
    : Json o ( json_obj_new )
    : b _n ( json_obj_set o `name` ( json_str_lit ( string_data fname ) ) )
    : b _b ( json_obj_set o `bytes` ( json_int ( vec_len [u] . req body ) ) )
    : HttpResponse r ( response_json 201 o )
    ^ r
}

// Queue a job: the first time after its upload, or again with new options
// once it has finished.
@ __mas_start HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : String st ( __mas_state ( string_data id ) )
    : s sd ( string_data st )
    ? | | ( __mas_eq sd `uploading` ) ( __mas_eq sd `done` ) ( __mas_eq sd `failed` ) {} {
        ? == ( string_len st ) 0 { ^ ( __mas_err 404 `no such job` ) } {}
        ^ ( __mas_err 409 `the job is already queued or running` )
    }
    ?? ( __mas_input ( string_data id ) ) {
        F why → { ^ ( __mas_err 400 ( string_data why ) ) }
        T _p → {}
    }
    : ~ i maxv 24
    : ~ i fps 2
    : ~ i stride 1
    : ~ i pstride 1
    : ~ i conf 0
    : ~ i win 24
    : ~ b sky F
    : ~ i align 3
    : ~ i mvneed 1
    : ~ i voxmm -1  // -1 auto, 0 off, else millimetres
    ?? ( json_parse_bytes . req body ) {
        T j → {
            = maxv ( __mas_jint j `max_views` 0 2000 24 )
            = fps ( __mas_jint j `fps` 1 30 2 )
            = stride ( __mas_jint j `stride` 1 100 1 )
            = pstride ( __mas_jint j `pixel_stride` 1 16 1 )
            = conf ( __mas_jint j `conf_pct` 0 95 0 )
            = win ( __mas_jint j `window` 4 64 24 )
            = sky ( __mas_jbool j `mask_sky` )
            = align ( __mas_jint j `align` 0 10 3 )
            = mvneed ( __mas_jint j `mv_check` 0 4 1 )
            = voxmm ( __mas_jint j `voxel_mm` -1 999 -1 )
        }
        F _e → {}
    }
    : String opts ( string_from `--max-views ` )
    ( string_push_int opts maxv )
    ( string_push_str opts ` --fps ` ) ( string_push_int opts fps )
    ( string_push_str opts ` --stride ` ) ( string_push_int opts stride )
    ( string_push_str opts ` --pixel-stride ` ) ( string_push_int opts pstride )
    ( string_push_str opts ` --window ` ) ( string_push_int opts win )
    ? > conf 0 { ( string_push_str opts ` --conf-pct ` ) ( string_push_int opts conf ) } {}
    ? sky { ( string_push_str opts ` --mask-sky` ) } {}
    ? > align 0 { ( string_push_str opts ` --align ` ) ( string_push_int opts align ) } {}
    ? > mvneed 0 { ( string_push_str opts ` --mv-check ` ) ( string_push_int opts mvneed ) } {}
    ? < voxmm 0 { ( string_push_str opts ` --voxel auto` ) } {
        ? > voxmm 0 {
            // millimetres as metres, without a float in the options line
            ( string_push_str opts ` --voxel 0.` )
            ? < voxmm 100 { ( string_push_char opts 48 ) } {}
            ? < voxmm 10 { ( string_push_char opts 48 ) } {}
            ( string_push_int opts voxmm )
        } {}
    }
    : b _o ( __mas_write_job ( string_data id ) `opts` ( string_data opts ) )
    : b _f ( __mas_write_job ( string_data id ) `finished` `0` )
    : b _t ( __mas_write_job ( string_data id ) `started` `0` )
    ( __mas_log_put ( string_data id ) `` )
    : b _q ( __mas_set_state ( string_data id ) `queued` )
    : HttpResponse r ( response_json 200 ( __mas_job_json ( string_data id ) F ) )
    ^ r
}

@ __mas_one Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : String st ( __mas_state ( string_data id ) )
    ? == ( string_len st ) 0 { ^ ( __mas_err 404 `no such job` ) } {}
    : HttpResponse r ( response_json 200 ( __mas_job_json ( string_data id ) T ) )
    ^ r
}

@ __mas_delete Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : String st ( __mas_state ( string_data id ) )
    ? == ( string_len st ) 0 { ^ ( __mas_err 404 `no such job` ) } {}
    ? ( __mas_eq ( string_data st ) `running` ) { ^ ( __mas_err 409 `the job is running` ) } {}
    // a queued job is taken off the queue first, so the worker passes it by
    : b _c ( __mas_set_state ( string_data id ) `deleted` )
    : String jd ( __mas_jdir ( string_data id ) )
    ?? ( dir_remove_all ( string_data jd ) ) {
        T _ → {}
        F _e → { ^ ( __mas_err 500 `cannot remove the job's files` ) }
    }
    : HttpResponse r ( response_status_only 204 )
    ^ r
}

@ __mas_cloud Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : String cp ( __mas_jfile ( string_data id ) `cloud.ply` )
    ?? ( read_file_bytes ( string_data cp ) ) {
        F _e → { ^ ( __mas_err 404 `no cloud for this job (yet)` ) }
        T blob → {
            : String nm ( __mas_read_job ( string_data id ) `name` )
            : ~ String base ( __mas_safe_name ( string_data nm ) )
            ? == ( string_len base ) 0 { = base ( string_from ( string_data id ) ) } {}
            : String file ( string_from ( string_data base ) )
            ( string_push_str file `.ply` )
            : String disp ( string_from `attachment; filename="` )
            ( string_push_str disp ( string_data file ) )
            ( string_push_char disp 34 )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `application/octet-stream` )
            ( response_set_header r `Content-Disposition` ( string_data disp ) )
            ( response_set_header r `X-Cloud-Name` ( string_data file ) )
            ( response_set_header r `Cache-Control` `no-store` )
            ( response_set_body_bytes r blob )
            ^ r
        }
    }
}

// ── the server ──────────────────────────────────────────────────────

@ __mas_usage → v {
    ( nurl_print `usage: map-anything serve [--host A] [--port N] [--data DIR] [--password P]\n\n` )
    ( nurl_print `  --host A        bind address (default 127.0.0.1; 0.0.0.0 = every interface)\n` )
    ( nurl_print `  --port N        port (default 8807)\n` )
    ( nurl_print `  --data DIR      jobs, uploads and clouds (default ~/.map-anything)\n` )
    ( nurl_print `  --password P    require HTTP Basic sign-in with this password, any user name\n` )
    ( nurl_print `                  (or $MAP_ANYTHING_PASSWORD)\n` )
}

// `map-anything serve ...` — argv[1] is "serve". Returns the exit code.
@ mas_main → i {
    : ~ s host `127.0.0.1`
    : ~ i port 8807
    : ~ String data ( string_new )
    : ~ String pass ( string_new )
    ?? ( env_get `MAP_ANYTHING_PASSWORD` ) { T v → { = pass v } F → {} }
    : i argc ( nurl_argc )
    : ~ i k 2
    ~ < k argc {
        : s a ( nurl_argv k )
        : b has < + k 1 argc
        ? & | ( __mas_eq a `--host` ) ( __mas_eq a `--addr` ) has { = host ( nurl_argv + k 1 ) = k + k 1 } {
            ? & ( __mas_eq a `--port` ) has { = port ( nurl_str_to_int ( nurl_argv + k 1 ) ) = k + k 1 } {
                ? & ( __mas_eq a `--data` ) has { = data ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                    ? & ( __mas_eq a `--password` ) has { = pass ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                        ? | ( __mas_eq a `--help` ) ( __mas_eq a `-h` ) { ( __mas_usage ) ^ 0 } {}
                        ( nurl_print `map-anything serve: unknown option ` )
                        ( nurl_print a ) ( nurl_print `\n\n` )
                        ( __mas_usage )
                        ^ 1
                    }
                }
            }
        }
        = k + k 1
    }
    ? == ( string_len data ) 0 {
        : String home ( env_home_dir )
        = data ( path_join ( string_data home ) `.map-anything` )
    } {}
    // absolute, because each job's child runs in its own job directory
    ? != ( string_get data 0 ) 47 {
        ?? ( env_cwd ) {
            T cwd → { = data ( path_join ( string_data cwd ) ( string_data data ) ) }
            F _e → {}
        }
    } {}
    // the child's command line goes through /bin/sh — single-quoted, so
    // only a quote in the data path itself could break it
    : ?i q ( string_index_of data `'` )
    ?? q { T _ → { ( nurl_eprintln `map-anything serve: the data directory may not contain a single quote` ) ^ 1 } F _ → {} }
    : ~ String bin ( string_new )
    ?? ( fs_readlink `/proc/self/exe` ) {
        T p → { = bin p }
        F _e → { = bin ( string_from ( nurl_argv 0 ) ) }
    }
    : String jobs ( path_join ( string_data data ) `jobs` )
    ?? ( dir_create_all ( string_data jobs ) ) {
        T _ → {}
        F _e → {
            ( nurl_eprint `map-anything serve: cannot create ` )
            ( nurl_eprintln ( string_data jobs ) )
            ^ 1
        }
    }
    : b open == ( string_len pass ) 0
    ( locked_set [MaCfg] g_mas_cfg @ MaCfg { ( string_from ( string_data data ) ) ( string_from ( string_data bin ) ) pass } )
    ( __mas_recover )

    : ( @ v ) workfn \ → v { ( __mas_worker ) }
    ?? ( thread_spawn workfn ) {
        T th → { ( thread_detach th ) }
        F _te → {
            ( nurl_eprintln `map-anything serve: cannot start the worker thread` )
            ^ 1
        }
    }

    : HttpApp a ( http_app_new )
    ( http_app_async a 0 )
    // a phone video is easily a few hundred MB, and it arrives as one
    // body held in memory: 2 GiB per file is the cap
    ( http_app_body_max a 2147483648 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 60000 )
    ( http_app_get a `/healthz` \ HttpRequest rq Params ps → HttpResponse { ^ ( response_text 200 `ok` ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_page ) } )
    ( http_app_get a `/view` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_viewer ) } )
    ( http_app_get a `/api/jobs` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_list ) } )
    ( http_app_post a `/api/jobs` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_create rq ) } )
    ( http_app_get a `/api/jobs/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_one ps ) } )
    ( http_app_delete a `/api/jobs/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_delete ps ) } )
    ( http_app_put a `/api/jobs/:id/files/:name` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_upload rq ps ) } )
    ( http_app_post a `/api/jobs/:id/start` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_start rq ps ) } )
    ( http_app_get a `/jobs/:id/cloud.ply` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_cloud ps ) } )
    ? open {} {
        : ( @ ( @ HttpResponse HttpRequest ) ( @ HttpResponse HttpRequest ) ) gate
        \ ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
            ^ \ HttpRequest req → HttpResponse {
                ? | ( __mas_eq ( string_data . req path ) `/healthz` ) ( __mas_authed req ) { ^ ( inner req ) } {}
                : HttpResponse r ( response_text 401 `sign in to use map-anything\n` )
                ( response_set_header r `WWW-Authenticate` `Basic realm="map-anything", charset="UTF-8"` )
                ^ r
            }
        }
        ( http_app_use a gate )
    }

    ( nurl_eprint `map-anything serve: http://` )
    ( nurl_eprint host ) ( nurl_eprint `:` ) ( nurl_eprint ( nurl_str_int port ) )
    ( nurl_eprint `  data ` ) ( nurl_eprint ( string_data data ) )
    ( nurl_eprintln ? open `  (NO PASSWORD — keep it on a private network)` `  (password required)` )
    : i rc ( http_app_listen a host port )
    ^ ? == rc 0 0 1
}
