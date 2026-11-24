// packages/recon-kit/src/serve.nu — `<model> serve`: the web service a
// reconstruction model package gets by handing rk_serve its RkApp.
//
//   <model> serve [--host A] [--port N] [--data DIR] [--password P]
//
// A browser uploads photos or a video, the service reconstructs them, and
// the cloud comes back in the ply viewer or as a PLY download; a region of
// it becomes a 3-D object (mesh.nu) on request.
//
//   GET    /                          the page (ui.nu)
//   GET    /view?cloud=URL            the ply package's WebGL viewer
//   GET    /healthz                   liveness, never behind the password
//   GET    /api/jobs                  every job, newest first
//   POST   /api/jobs                  {name} → a new job, state "uploading"
//   PUT    /api/jobs/:id/files/:name  one input file, the raw request body,
//                                     in pieces: ?offset=N appends at byte N
//   POST   /api/jobs/:id/start        {max_views, ...} → "queued"
//   GET    /api/jobs/:id              one job, with its whole log
//   DELETE /api/jobs/:id              the job and its files
//   GET    /jobs/:id/cloud.ply        the result
//   POST   /api/jobs/:id/mesh         {box, res} → a 3-D object queued
//   GET    /api/jobs/:id/mesh         its state, and once done its url
//   GET    /jobs/:id/object.glb       the object (binary glTF)
//   POST   /api/jobs/:id/share        a read-only link → {share, url}
//   DELETE /api/jobs/:id/share        the link stops working
//   GET    /s/:token                  WITHOUT the sign-in: what is shared,
//   GET    /s/:token/view               the viewer (no crop tool),
//   GET    /s/:token/cloud.ply          the cloud and
//   GET    /s/:token/object.glb         the object — reading only
//
// What the model's executable must answer — the whole contract between a
// model and this service:
//
//   <bin> <input> -o cloud.tmp.ply --scene scene.bin <options line>
//       <input> a video file or a directory of photos; progress on
//       stdout/stderr (the job's log); exit 0 with both files written.
//       The options line is the one the app's `opts` built.
//   <bin> mesh scene.bin -o object.tmp.glb --box x0 y0 z0 x1 y1 z1 --res N
//       which rk_mesh_main (mesh.nu) implements for it.
//
// The state is the filesystem, nothing else: a job is a directory
// <data>/jobs/<id>/ holding input/, a `state` word, `name`, `opts`,
// `created`/`started`/`finished` (unix ms), the run's `log` and, once done,
// `cloud.ply`. A restart loses nothing, and a job a restart interrupted is
// queued again.
//
// ONE worker thread takes the queued jobs oldest first and runs each as a
// child process of this same executable — `<model> <input> -o ...` —
// with the CLI's output going to the job's log, which is what the page
// shows as progress. A child per job rather than the model in this process,
// because the server then holds no GPU memory between jobs (the card is
// shared with other services), a failed run cannot take the server down,
// and the CLI stays the single implementation of the pipeline. The model
// load it costs is a few seconds from the page cache against a run of
// tens of seconds.
//
// Every state change a client and the worker can race on — the worker
// claiming a queued job, DELETE, a start — runs under one lock
// (g_rk_lk), so a job is claimed or deleted, never both. The worker's
// child records its pid in the job directory, in a file named for its run's
// one-time token (pid.<token>); a server stopped by SIGTERM
// ends the child and puts the job back in the queue, and a server that
// died without that ends the orphan it finds at the next start before
// running the job again — never two children on one job.
// One server owns a data directory at a time (an flock on
// <data>/serve.lock, released by the kernel when the process dies).
//
// Bodies are read in full before any handler runs (the stdlib server has
// no hook between the head and the body), so the sign-in can only refuse a
// request after its body arrived. The body cap is what bounds that: 40 MiB,
// which is why the page sends a file in 32 MiB pieces and the pieces go
// straight to disk.
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
$ `stdlib/std/pfile.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `deps/ply/src/view.nu`
$ `deps/video/src/video.nu`
$ `app.nu`
$ `ui.nu`

// ── configuration ───────────────────────────────────────────────────

: RkCfg {
    String data  // the data root, e.g. ~/.map-anything
    String bin  // this executable, run once per job
    String pass  // HTTP Basic password; empty = no sign-in
    String name  // the app's name, for log lines
    String page  // the upload page, rendered once at start
}

@ __rk_cfg_blank → ( Locked RkCfg ) {
    ^ ( locked_new [RkCfg] @ RkCfg { ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) } )
}

@ __rk_app_blank → ( Locked RkApp ) {
    ^ ( locked_new [RkApp] @ RkApp { ( string_new ) ( string_new ) ( string_new ) 0 ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 0 \ Json j → String { ^ ( string_new ) } } )
}

: ( Locked RkApp ) g_rk_app ( __rk_app_blank )

: ( Locked RkCfg ) g_rk_cfg ( __rk_cfg_blank )

@ __rk_cfg → RkCfg { ^ ( locked_get [RkCfg] g_rk_cfg ) }

// "<name> serve: " before a line on stderr
@ __rk_tag → v {
    : RkCfg c ( __rk_cfg )
    ( nurl_eprint ( string_data . c name ) )
    ( nurl_eprint ` serve: ` )
}

@ __rk_lk_blank → ( Locked i ) { ^ ( locked_new [i] 0 ) }

// The job-state lock: checked out for the length of a state transition.
: ( Locked i ) g_rk_lk ( __rk_lk_blank )

// 1 once the server is shutting down: the worker then leaves the job it
// was running to the shutdown, which queues it again.
: ( Locked i ) g_rk_stop ( __rk_lk_blank )

@ __rk_lock → i { ^ ( locked_take [i] g_rk_lk ) }

@ __rk_unlock i t → v { ( locked_restore [i] g_rk_lk t ) }

// ── small helpers ───────────────────────────────────────────────────

@ __rk_eq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __rk_now → String {
    : String t ( string_new )
    ( string_push_int t ( now_ms ) )
    ^ t
}

// A job id as made by __rk_new_id: digits, lowercase hex and '-'.
@ __rk_id_ok s id → b {
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

@ __rk_new_id → String {
    : String id ( __rk_now )
    ( string_push_char id 45 )
    : String rh ( rand_hex_str 3 )
    ( string_push_str id ( string_data rh ) )
    ^ id
}

// A client's file name, reduced to [A-Za-z0-9._-] (anything else becomes
// '_'), never starting with '.', at most 120 bytes. A long name loses the
// end of its stem, never its extension: the extension is what decides
// image vs video.
@ __rk_safe_name s raw → String {
    : String out ( string_new )
    : ( Slice u ) bs ( slice_of_str raw )
    : i n ( slice_len [u] bs )
    // the extension: from the last '.', when it is short enough to be one
    : ~ i dot n
    : ~ i k 0
    ~ < k n {
        ? == ( slice_byte bs k ) 46 { = dot k } {}
        = k + k 1
    }
    ? | == dot 0 > - n dot 12 { = dot n } {}
    : i room - 120 - n dot
    : i keep ? < dot room dot room
    = k 0
    ~ < k n {
        ? | < k keep >= k dot {
            : i c ( slice_byte bs k )
            : b alnum | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122
            : b punct | | == c 46 == c 45 == c 95
            : b lead_dot & == ( string_len out ) 0 == c 46
            ? & | alnum punct == lead_dot F { ( string_push_char out c ) } { ( string_push_char out 95 ) }
        } {}
        = k + k 1
    }
    ^ out
}

// Free text from a client (a job's name), kept to printable bytes and cut
// at `max` bytes on a UTF-8 character boundary.
@ __rk_clip s raw i max → String {
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
@ __rk_q String cmd s text → v {
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

// The options line handed to the CLI is built by __rk_start from
// validated integers; this re-checks it before it reaches a shell.
@ __rk_opts_ok s opts → b {
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

@ __rk_is_image s name → b {
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

@ __rk_jobs_dir → String {
    : RkCfg c ( __rk_cfg )
    : String d ( path_join ( string_data . c data ) `jobs` )
    ^ d
}

@ __rk_jdir s id → String {
    : String jd ( __rk_jobs_dir )
    : String d ( path_join ( string_data jd ) id )
    ^ d
}

@ __rk_jfile s id s name → String {
    : String jd ( __rk_jdir id )
    : String p ( path_join ( string_data jd ) name )
    ^ p
}

@ __rk_read s path → String {
    ?? ( read_file path ) {
        T t → {
            : String r ( string_trim t )
            ^ r
        }
        F _e → { ^ ( string_new ) }
    }
}

@ __rk_read_job s id s name → String {
    : String p ( __rk_jfile id name )
    : String r ( __rk_read ( string_data p ) )
    ^ r
}

@ __rk_read_int s id s name → i {
    : String t ( __rk_read_job id name )
    ? == ( string_len t ) 0 { ^ 0 } {}
    ^ ( nurl_str_to_int ( string_data t ) )
}

// Written beside and renamed over, so a reader never sees half a file.
@ __rk_write_job s id s name s text → b {
    : String p ( __rk_jfile id name )
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

@ __rk_state s id → String {
    : String st ( __rk_read_job id `state` )
    ^ st
}

@ __rk_state_is s id s want → b {
    : String st ( __rk_state id )
    ^ ( __rk_eq ( string_data st ) want )
}

@ __rk_set_state s id s st → b { ^ ( __rk_write_job id `state` st ) }

// the same for another state file of the job (mesh_state)
@ __rk_state_is_f s id s file s want → b {
    : String st ( __rk_read_job id file )
    ^ ( __rk_eq ( string_data st ) want )
}

// Every job id under jobs/, oldest first.
@ __rk_job_ids → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String jd ( __rk_jobs_dir )
    ?? ( dir_list ( string_data jd ) ) {
        F _e → {}
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( __rk_id_ok ( string_data nm ) ) {
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
@ __rk_input s id → !String String {
    : String ind ( __rk_jfile id `input` )
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
                                ? ( __rk_is_image ( string_data nm ) ) { = nimg + nimg 1 } {}
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
@ __rk_input_stats s id inout i nfiles inout i nbytes → v {
    : String ind ( __rk_jfile id `input` )
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
@ __rk_last_line String log → String {
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
@ __rk_points String log → i {
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

@ __rk_job_json s id b with_log → Json {
    : Json o ( json_obj_new )
    : String st ( __rk_state id )
    : String nm ( __rk_read_job id `name` )
    : String opts ( __rk_read_job id `opts` )
    : ~ i nfiles 0
    : ~ i nbytes 0
    ( __rk_input_stats id nfiles nbytes )
    : String logp ( __rk_jfile id `log` )
    : ~ String log ( string_new )
    ?? ( read_file ( string_data logp ) ) { T t → { = log t } F _e → {} }
    : String cloudp ( __rk_jfile id `cloud.ply` )
    : ~ i cbytes 0
    ?? ( file_size ( string_data cloudp ) ) { T z → { = cbytes z } F _e → {} }
    : b _a ( json_obj_set o `id` ( json_str_lit id ) )
    : b _b ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
    : b _c ( json_obj_set o `state` ( json_str_lit ( string_data st ) ) )
    : b _d ( json_obj_set o `created` ( json_int ( __rk_read_int id `created` ) ) )
    : b _e ( json_obj_set o `started` ( json_int ( __rk_read_int id `started` ) ) )
    : b _f ( json_obj_set o `finished` ( json_int ( __rk_read_int id `finished` ) ) )
    : b _g ( json_obj_set o `opts` ( json_str_lit ( string_data opts ) ) )
    : b _h ( json_obj_set o `files` ( json_int nfiles ) )
    : b _i ( json_obj_set o `input_bytes` ( json_int nbytes ) )
    : b _j ( json_obj_set o `cloud_bytes` ( json_int cbytes ) )
    : b _k ( json_obj_set o `points` ( json_int ( __rk_points log ) ) )
    : String last ( __rk_last_line log )
    : b _l ( json_obj_set o `progress` ( json_str_lit ( string_data last ) ) )
    : String scp ( __rk_jfile id `scene.bin` )
    : b _sc ( json_obj_set o `scene` ( json_bool == 1 ( nurl_path_type ( string_data scp ) ) ) )
    : String ms ( __rk_read_job id `mesh_state` )
    : b _ms ( json_obj_set o `mesh_state` ( json_str_lit ( string_data ms ) ) )
    : String obp ( __rk_jfile id `object.glb` )
    : ~ i obytes 0
    ?? ( file_size ( string_data obp ) ) { T z → { = obytes z } F _e → {} }
    : b _ob ( json_obj_set o `object_bytes` ( json_int obytes ) )
    : String shr ( __rk_read_job id `share` )
    : b _sh ( json_obj_set o `share` ( json_str_lit ? ( __rk_token_ok ( string_data shr ) ) ( string_data shr ) `` ) )
    ? with_log {
        : b _m ( json_obj_set o `log` ( json_str_lit ( string_data log ) ) )
    } {}
    ^ o
}

// ── the worker ──────────────────────────────────────────────────────

// The oldest queued job, claimed — its state is `running` before the
// lock is let go, so a DELETE that comes after sees it running.
//
// One job runs at a time, and that is checked here rather than assumed:
// the worker claims only when it is idle, so any job still `running` at
// this point is one a recovery or shutdown could not settle (a token it
// could not void, a child it could not end). Nothing starts beside it;
// the next start's recovery gets another go at it.
@ __rk_claim_next → String {
    : ( Vec String ) ids ( __rk_job_ids )
    : ~ String got ( string_new )
    : i t ( __rk_lock )
    // a shutdown sets its flag under this lock: claimed before it, the work
    // is swept by the shutdown; after it, nothing is claimed
    : ~ b unsettled ( __rk_stopping )
    : ~ i u 0
    ~ < u ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids u ) {
            T id → {
                ? | ( __rk_state_is ( string_data id ) `running` ) ( __rk_state_is_f ( string_data id ) `mesh_state` `running` ) { = unsettled T } {}
            }
            F → {}
        }
        = u + u 1
    }
    // the oldest queued work of either kind, by when it was queued, so a
    // stream of new reconstructions cannot starve an object asked for
    // earlier (or the other way round)
    : ~ i best_kind 0  // 0 none, 1 reconstruction, 2 object
    : ~ String best_id ( string_new )
    : ~ i best_t 0
    : ~ i k ? unsettled ( vec_len [String] ids ) 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T id → {
                : s sid ( string_data id )
                ? ( __rk_state_is sid `queued` ) {
                    : i qt ( __rk_read_int sid `queued_at` )
                    ? | == best_kind 0 < qt best_t { = best_kind 1 = best_id ( string_from sid ) = best_t qt } {}
                } {}
                // an object only of a job still done (not deleted, not re-run)
                ? & ( __rk_state_is sid `done` ) ( __rk_state_is_f sid `mesh_state` `queued` ) {
                    : i qt ( __rk_read_int sid `mesh_queued_at` )
                    ? | == best_kind 0 < qt best_t { = best_kind 2 = best_id ( string_from sid ) = best_t qt } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? == best_kind 1 {
        ? ( __rk_set_state ( string_data best_id ) `running` ) { = got ( string_from ( string_data best_id ) ) } {}
    } {}
    ? == best_kind 2 {
        ? ( __rk_write_job ( string_data best_id ) `mesh_state` `running` ) {
            = got ( string_from `m:` )
            ( string_push_str got ( string_data best_id ) )
        } {}
    } {}
    ( __rk_unlock t )
    ^ got
}

// A finished run's terminal state, written under the job lock and retried
// with a growing pause until it is on disk: the child is gone, so if the
// write were lost the job would stay `running` and hold the queue. A
// shutdown that queued the work again in the meantime is overwritten only
// by a real outcome, never by nothing (a stopped run writes nothing).
@ __rk_settle s id s file s value → v {
    : ~ i pause 500
    ~ T {
        : i t ( __rk_lock )
        : b ok ( __rk_write_job id file value )
        ( __rk_unlock t )
        ? ok { ^ v } {}
        ( __rk_tag ) ( nurl_eprint `cannot record job ` ) ( nurl_eprint id )
        ( nurl_eprint ` ` ) ( nurl_eprint file ) ( nurl_eprintln `; retrying` )
        ( sleep_ms pause )
        = pause ? < pause 30000 * pause 2 30000
    }
}

@ __rk_stopping → b { ^ != 0 ( locked_get [i] g_rk_stop ) }

// The pid of a running job's child, or 0 when there is none — and then
// none can appear. Each run publishes its pid in pid.<token>, named for
// the run's one-time token in `run`, so a shell from an older run can
// never overwrite the current run's pid. The token is read first; when no
// pid shows for it within 2 s, the token is voided and the same file is
// read once more: a shell still on its way to `exec` either sees the void
// and exits, or had already written its pid and is found. -1 when the
// void could not be written: the old token is still good, so the job must
// not run again yet (the caller leaves it `running` for a later recovery).
@ __rk_child_of s id → i {
    : String tok ( __rk_read_job id `run` )
    ? | == ( string_len tok ) 0 ( __rk_eq ( string_data tok ) `void` ) { ^ 0 } {}
    : String pname ( string_from `pid.` )
    ( string_push_str pname ( string_data tok ) )
    : ~ i n 0
    ~ < n 20 {
        : i pid ( __rk_read_int id ( string_data pname ) )
        ? > pid 0 { ^ pid } {}
        ( sleep_ms 100 )
        = n + n 1
    }
    ? ( __rk_write_job id `run` `void` ) {} { ^ -1 }
    ^ ( __rk_read_int id ( string_data pname ) )
}

// Every pid.<token> left in a job directory (by runs that are over).
@ __rk_clear_pids s id → v {
    : String jd ( __rk_jdir id )
    ?? ( dir_list ( string_data jd ) ) {
        F _e → {}
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( string_starts_with nm `pid.` ) {
                            : String fp ( path_join ( string_data jd ) ( string_data nm ) )
                            ?? ( file_delete ( string_data fp ) ) { T _ → {} F _e → {} }
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
    }
}

// Become the data directory's only server: an exclusive lock on
// <data>/serve.lock (pfile_try_lock — flock, taken without waiting). The
// kernel holds it for the open descriptor and lets go when the process
// dies, killed or not, so there is no stale lock to judge and no takeover
// to race; the file itself is never deleted. The descriptor is
// close-on-exec, so a reconstruction child does not inherit the lock and
// an orphan cannot keep the next server out. F when another process holds
// it; the caller keeps the returned handle for the server's lifetime.
@ __rk_own_data s data → ?PFile {
    : String lp ( path_join data `serve.lock` )
    ?? ( pfile_open ( string_data lp ) PFILE_CREATE ) {
        F _e → { ^ @ ?PFile { F } }
        T pf → {
            : i fd ( _pfile_fd pf )
            : i fl ( fcntl fd ( posix_const `F_GETFD` ) 0 )
            ? != fl -1 { : i _c ( fcntl fd ( posix_const `F_SETFD` ) | fl ( posix_const `FD_CLOEXEC` ) ) } {}
            ?? ( pfile_try_lock pf ) {
                T held → { ? held { ^ @ ?PFile { T pf } } {} }
                F _e → {}
            }
            ^ @ ?PFile { F }
        }
    }
}

// Is `pid` alive and one of our children — a reconstruction (its command
// line writes cloud.tmp.ply) or a mesh (object.tmp.glb)? A recycled pid
// belonging to anything else is not.
@ __rk_is_our_child i pid → b {
    ? ( __rk_cmdline_has pid `cloud.tmp.ply` ) { ^ T } {}
    ^ ( __rk_cmdline_has pid `object.tmp.glb` )
}

@ __rk_cmdline_has i pid s what → b {
    ? <= pid 0 { ^ F } {}
    : String cl ( string_from `/proc/` )
    ( string_push_int cl pid )
    ( string_push_str cl `/cmdline` )
    ?? ( read_file_bytes ( string_data cl ) ) {
        F _e → { ^ F }
        T bytes → {
            : ( Slice u ) bs ( slice_from_vec [u] bytes )
            : ( Slice u ) pat ( slice_of_str what )
            : i n ( slice_len [u] bs )
            : i m ( slice_len [u] pat )
            : ~ i k 0
            ~ <= + k m n {
                : ~ i j 0
                ~ & < j m == ( slice_byte bs + k j ) ( slice_byte pat j ) { = j + j 1 }
                ? == j m { ^ T } {}
                = k + k 1
            }
            ^ F
        }
    }
}

// SIGTERM, up to 10 s for it to go, then SIGKILL. `gone` decides when it
// has gone (a dead child of ours is a zombie until the worker reaps it,
// and a zombie's /proc command line is empty, so __rk_is_our_child says
// it has gone).
// T once `gone` holds; F if the process outlived even SIGKILL (stuck in
// uninterruptible I/O, say), and then the caller must not run its job again.
@ __rk_end_child i pid ( @ b ) gone → b {
    ? <= pid 0 { ^ T } {}
    : i32 _a ( kill # i32 pid # i32 ( posix_const `SIGTERM` ) )
    : ~ i waited 0
    ~ & < waited 100 ! ( gone ) {
        ( sleep_ms 100 )
        = waited + waited 1
    }
    ? ( gone ) {} {
        : i32 _b ( kill # i32 pid # i32 ( posix_const `SIGKILL` ) )
        : ~ i w2 0
        ~ & < w2 50 ! ( gone ) {
            ( sleep_ms 100 )
            = w2 + w2 1
        }
    }
    ^ ( gone )
}

@ __rk_log_put s id s text → v {
    : String logp ( __rk_jfile id `log` )
    ?? ( write_file ( string_data logp ) text ) { T _ → {} F _e → {} }
}

// The shell line every child starts with: into the job directory, its own
// pid into pid.<token>, on only while <token> is still the job's run, then
// `exec` the server's own binary (so the pid is the child's to the end).
// The pid file named for the token means a shell from an older run can
// never overwrite the current run's pid, and a shell delayed past a
// shutdown or a recovery — which void the token when they find no pid —
// exits instead of starting a second run.
@ __rk_cmd_head s jd s token s bin → String {
    : String cmd ( string_from `cd ` )
    ( __rk_q cmd jd )
    ( string_push_str cmd ` && echo $$ > pid.` )
    ( string_push_str cmd token )
    ( string_push_str cmd ` && [ "$(cat run)" = ` )
    ( string_push_str cmd token )
    ( string_push_str cmd ` ] && exec ` )
    ( __rk_q cmd bin )
    ^ cmd
}

// Spawn `cmd` (made with __rk_cmd_head and this `token`) under the job
// lock, unless a shutdown has begun — the shutdown takes the same lock, so
// it either runs first (nothing is spawned) or finds the child — and wait
// for it. The exit code; -1 when it could not be started; -2 when a
// shutdown began (before the spawn, or by ending the child): the job is
// then the shutdown's to queue again and the caller writes nothing.
@ __rk_spawn_wait s id s token String cmd → i {
    : String jd ( __rk_jdir id )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args ( string_data cmd ) )
    : String pidn ( string_from `pid.` )
    ( string_push_str pidn token )
    : String pidp ( path_join ( string_data jd ) ( string_data pidn ) )
    ( __rk_clear_pids id )
    : i t ( __rk_lock )
    : ~ ? ProcChild got @ ?ProcChild { F }
    : ~ b spawn_failed F
    ? ( __rk_stopping ) {} {
        ? ( __rk_write_job id `run` token ) {} { = spawn_failed T }
    }
    ? | ( __rk_stopping ) spawn_failed {} {
        ?? ( process_spawn `/bin/sh` args ) {
            T ch → { = got @ ?ProcChild { T ch } }
            F _e → { = spawn_failed T }
        }
    }
    ( __rk_unlock t )
    ? spawn_failed { ^ -1 } {}
    ?? got {
        F → { ^ -2 }
        T ch → {
            : i code ( proc_wait ch )
            ?? ( file_delete ( string_data pidp ) ) { T _ → {} F _e → {} }
            ? ( __rk_stopping ) { ^ -2 } {}
            ^ code
        }
    }
}

// Run a job the worker has claimed (its state is already `running`).
@ __rk_run s id → v {
    : RkCfg c ( __rk_cfg )
    : String jd ( __rk_jdir id )
    : String t0 ( __rk_now )
    : b _t ( __rk_write_job id `started` ( string_data t0 ) )
    : b _f ( __rk_write_job id `finished` `0` )
    : ~ b ok F
    ?? ( __rk_input id ) {
        F why → {
            ( __rk_log_put id ( string_data why ) )
        }
        T inp → {
            : String opts ( __rk_read_job id `opts` )
            ? ( __rk_opts_ok ( string_data opts ) ) {
                : String tmp ( path_join ( string_data jd ) `cloud.tmp.ply` )
                : String out ( path_join ( string_data jd ) `cloud.ply` )
                // run in the job directory, so the log the page shows names
                // the job's own files and not the server's data path; the
                // views are kept (scene.bin) for 3-D objects made later
                : String token ( rand_hex_str 8 )
                : String cmd ( __rk_cmd_head ( string_data jd ) ( string_data token ) ( string_data . c bin ) )
                ( string_push_char cmd 32 )
                ( __rk_q cmd ( string_data inp ) )
                ( string_push_str cmd ` -o cloud.tmp.ply --scene scene.bin ` )
                ( string_push_str cmd ( string_data opts ) )
                ( string_push_str cmd ` < /dev/null > log 2>&1` )
                ( __rk_tag ) ( nurl_eprint `job ` )
                ( nurl_eprint id )
                ( nurl_eprint ` running: ` )
                ( nurl_eprintln ( string_data opts ) )
                : i code ( __rk_spawn_wait id ( string_data token ) cmd )
                ? == code -2 { ^ v } {}
                ? == code -1 { ( __rk_log_put id `serve: could not start the reconstruction` ) } {}
                ? == code 0 {
                    ?? ( fs_rename ( string_data tmp ) ( string_data out ) ) {
                        T _ → { = ok T }
                        F _e → {}
                    }
                } {}
            } {
                ( __rk_log_put id `serve: the job's options are malformed` )
            }
        }
    }
    : String t1 ( __rk_now )
    : b _e ( __rk_write_job id `finished` ( string_data t1 ) )
    ( __rk_settle id `state` ? ok `done` `failed` )
    ( __rk_tag ) ( nurl_eprint `job ` )
    ( nurl_eprint id )
    ( nurl_eprintln ? ok ` done` ` failed` )
}

// Make a job's 3-D object (its mesh_state is already `running`): the mesh
// subcommand over the views the reconstruction kept, with the box and the
// resolution the request left in mesh_req.
@ __rk_run_mesh s id → v {
    : RkCfg c ( __rk_cfg )
    : String jd ( __rk_jdir id )
    : String args ( __rk_read_job id `mesh_req` )
    : String attempt ( __rk_read_job id `mesh_attempt` )
    : ~ b ok F
    ? ( __rk_opts_ok ( string_data args ) ) {
        : String token ( rand_hex_str 8 )
        : String cmd ( __rk_cmd_head ( string_data jd ) ( string_data token ) ( string_data . c bin ) )
        ( string_push_str cmd ` mesh scene.bin -o object.tmp.glb ` )
        ( string_push_str cmd ( string_data args ) )
        ( string_push_str cmd ` < /dev/null > mesh.log 2>&1` )
        ( __rk_tag ) ( nurl_eprint `job ` ) ( nurl_eprint id )
        ( nurl_eprint ` meshing: ` ) ( nurl_eprintln ( string_data args ) )
        : i code ( __rk_spawn_wait id ( string_data token ) cmd )
        ? == code -2 { ^ v } {}
        ? == code 0 {
            : String tmp ( path_join ( string_data jd ) `object.tmp.glb` )
            : String out ( path_join ( string_data jd ) `object.glb` )
            ?? ( fs_rename ( string_data tmp ) ( string_data out ) ) { T _ → { = ok T } F _e → {} }
            // which request the object answers (the status names it)
            ? ok { ( __rk_settle id `object_attempt` ( string_data attempt ) ) } {}
        } {}
    } {}
    ( __rk_settle id `mesh_state` ? ok `done` `failed` )
    ( __rk_tag ) ( nurl_eprint `job ` ) ( nurl_eprint id )
    ( nurl_eprintln ? ok ` object done` ` object failed` )
}

@ __rk_worker → v {
    ~ T {
        ? ( __rk_stopping ) { ( sleep_ms 1000 ) } {
            : String id ( __rk_claim_next )
            ? > ( string_len id ) 0 {
                ? ( string_starts_with id `m:` ) {
                    : String mid ( string_substr id 2 - ( string_len id ) 2 )
                    ( __rk_run_mesh ( string_data mid ) )
                } { ( __rk_run ( string_data id ) ) }
            } { ( sleep_ms 1000 ) }
        }
    }
}

// At shutdown: the child of one state file of one job, if it is running,
// ended and its work queued again. With the token not voided (pid < 0), or
// a child that outlived SIGKILL, it stays `running`: the next start's
// recovery tries again.
@ __rk_stop_one s id s file → v {
    ? ( __rk_state_is_f id file `running` ) {} { ^ v }
    : i pid ( __rk_child_of id )
    : ~ b ended T
    ? > pid 0 {
        ( __rk_tag ) ( nurl_eprint `stopping the child of job ` )
        ( nurl_eprintln id )
        = ended ( __rk_end_child pid \ → b { ^ ! ( __rk_is_our_child pid ) } )
    } {}
    ? & >= pid 0 ended {
        // only if it is still that same run: a worker that finished first
        // has recorded `done` or `failed`, and that stays
        : i t ( __rk_lock )
        ? ( __rk_state_is_f id file `running` ) { : b _q ( __rk_write_job id file `queued` ) } {}
        ( __rk_unlock t )
    } {}
}

// One state file of one job: `running` when the last process stopped means
// its child may still be going — end it, then queue the work again.
@ __rk_recover_one s id s file → v {
    ? ( __rk_state_is_f id file `running` ) {} { ^ v }
    : i pid ( __rk_child_of id )
    ? < pid 0 {
        // its token could not be voided: running it again now could meet a
        // late child of the old run — leave it
        ( __rk_tag ) ( nurl_eprint `cannot void the run token of job ` )
        ( nurl_eprint id )
        ( nurl_eprintln `; left running until a later start can` )
        ^ v
    } {}
    : ~ b ended T
    ? ( __rk_is_our_child pid ) {
        ( __rk_tag ) ( nurl_eprint `ending the orphaned child, pid ` )
        ( nurl_eprintln ( nurl_str_int pid ) )
        = ended ( __rk_end_child pid \ → b { ^ ! ( __rk_is_our_child pid ) } )
    } {}
    ? ended {
        ( __rk_clear_pids id )
        : b _q ( __rk_write_job id file `queued` )
        ( __rk_tag ) ( nurl_eprint `re-queued the interrupted ` )
        ( nurl_eprint ? ( __rk_eq file `state` ) `job ` `object of job ` )
        ( nurl_eprintln id )
    } {
        ( __rk_tag ) ( nurl_eprint `the child of job ` )
        ( nurl_eprint id )
        ( nurl_eprintln ` outlived SIGKILL; left running, nothing starts beside it` )
    }
}

// A job the last process was running when it stopped runs again — after
// the child that process left behind, if it is still going, has ended.
@ __rk_recover → v {
    : ( Vec String ) ids ( __rk_job_ids )
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T id → {
                ( __rk_recover_one ( string_data id ) `state` )
                ( __rk_recover_one ( string_data id ) `mesh_state` )
            }
            F → {}
        }
        = k + k 1
    }
}

// ── HTTP ────────────────────────────────────────────────────────────

@ __rk_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

@ __rk_param Params ps s key → String {
    ?? ( params_get ps key ) {
        T v → { ^ v }
        F → { ^ ( string_new ) }
    }
}

// For an app's `opts`: a number from the start request, clamped to
// lo..hi, `dflt` when it is missing or not a number...
@ rk_jint Json root s key i lo i hi i dflt → i {
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

// ...a flag, F unless it is the JSON `true`...
@ rk_jbool Json root s key → b {
    ?? ( json_obj_get root key ) {
        T v → { ? ( json_is_bool v ) { ^ ( json_bool_val v ) } { ^ F } }
        F → { ^ F }
    }
}

// ...and the voxel size the page's "voxel size (mm)" field sends: -1 auto
// (` --voxel auto`), 0 off (nothing), else millimetres as metres without
// a float in the options line (` --voxel 0.005`).
@ rk_push_voxel String opts i mm → v {
    ? < mm 0 { ( string_push_str opts ` --voxel auto` ) ^ v } {}
    ? == mm 0 { ^ v } {}
    ( string_push_str opts ` --voxel 0.` )
    ? < mm 100 { ( string_push_char opts 48 ) } {}
    ? < mm 10 { ( string_push_char opts 48 ) } {}
    ( string_push_int opts mm )
}

// Every byte of the configured password is compared, and a length
// mismatch folds into the same accumulator: no early exit to time.
@ __rk_authed HttpRequest req → b {
    : RkCfg c ( __rk_cfg )
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

@ __rk_page → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_header r `Cache-Control` `no-store` )
    : RkCfg c ( __rk_cfg )
    ( response_set_body_str r ( string_data . c page ) )
    ^ r
}

@ __rk_viewer → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_header r `Cache-Control` `no-store` )
    : String page ( vw_page `` )
    ( response_set_body_str r ( string_data page ) )
    ^ r
}

@ __rk_list → HttpResponse {
    : ( Vec String ) ids ( __rk_job_ids )
    : Json arr ( json_arr_new )
    : ~ i k - ( vec_len [String] ids ) 1
    ~ >= k 0 {
        ?? ( vec_get [String] ids k ) {
            T id → { : b _p ( json_arr_push arr ( __rk_job_json ( string_data id ) F ) ) }
            F → {}
        }
        = k - k 1
    }
    : Json o ( json_obj_new )
    : b _j ( json_obj_set o `jobs` arr )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

@ __rk_create HttpRequest req → HttpResponse {
    : ~ String name ( string_new )
    ?? ( json_parse_bytes . req body ) {
        T j → {
            ?? ( json_obj_get j `name` ) {
                T v → { ? ( json_is_str v ) { = name ( __rk_clip ( json_as_str v ) 120 ) } {} }
                F → {}
            }
        }
        F _e → {}
    }
    : String id ( __rk_new_id )
    : String ind ( __rk_jfile ( string_data id ) `input` )
    ?? ( dir_create_all ( string_data ind ) ) {
        T _ → {}
        F _e → { ^ ( __rk_err 500 `cannot create the job directory` ) }
    }
    : String t0 ( __rk_now )
    : b _n ( __rk_write_job ( string_data id ) `name` ( string_data name ) )
    : b _c ( __rk_write_job ( string_data id ) `created` ( string_data t0 ) )
    : b _s ( __rk_set_state ( string_data id ) `uploading` )
    : HttpResponse r ( response_json 201 ( __rk_job_json ( string_data id ) F ) )
    ^ r
}

@ __rk_upload HttpRequest req Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : String raw ( __rk_param ps `name` )
    : String fname ( __rk_safe_name ( string_data raw ) )
    ? == ( string_len fname ) 0 { ^ ( __rk_err 400 `the file needs a name` ) } {}
    : String ind ( __rk_jfile ( string_data id ) `input` )
    : String fp ( path_join ( string_data ind ) ( string_data fname ) )
    : i off ?? ( request_query_int req `offset` ) { T v → v F → 0 }
    // The state check, the size check and the write under the job lock:
    // two pieces racing for one offset, or two first pieces for one name,
    // cannot both pass, and a job that has been queued or deleted takes
    // no more bytes. (A piece is at most 32 MiB, so the lock is short.)
    : ~ i res 0  // 0 stored, 1 not uploading, 2 name taken, 3 out of order, 4 write failed
    : i t ( __rk_lock )
    ? ( __rk_state_is ( string_data id ) `uploading` ) {
        : ~ i have -1
        ?? ( file_size ( string_data fp ) ) { T z → { = have z } F _e → {} }
        ? == off 0 {
            // two names that clean to the same one must not overwrite each other
            ? >= have 0 { = res 2 } {
                ?? ( write_file_bytes ( string_data fp ) . req body ) { T _ → {} F _e → { = res 4 } }
            }
        } {
            // a later piece continues exactly where the file ends
            ? != have off { = res 3 } {
                ?? ( append_file_bytes ( string_data fp ) . req body ) { T _ → {} F _e → { = res 4 } }
            }
        }
    } { = res 1 }
    ( __rk_unlock t )
    ? == res 1 { ^ ( __rk_err 409 `the job is not taking uploads` ) } {}
    ? == res 2 { ^ ( __rk_err 409 `the job already has a file of that name` ) } {}
    ? == res 3 { ^ ( __rk_err 409 `that piece does not continue the file` ) } {}
    ? == res 4 { ^ ( __rk_err 500 `cannot store the file` ) } {}
    : Json o ( json_obj_new )
    : b _n ( json_obj_set o `name` ( json_str_lit ( string_data fname ) ) )
    : b _b ( json_obj_set o `bytes` ( json_int + off ( vec_len [u] . req body ) ) )
    : HttpResponse r ( response_json 201 o )
    ^ r
}

// Queue a job: the first time after its upload, or again with new options
// once it has finished.
@ __rk_start HttpRequest req Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    ?? ( __rk_input ( string_data id ) ) {
        F why → { ^ ( __rk_err 400 ( string_data why ) ) }
        T _p → {}
    }
    // the model's own: the request's JSON → its CLI's options line
    : RkApp app ( locked_get [RkApp] g_rk_app )
    : ( @ String Json ) mk . app opts
    : ~ String opts ( string_new )
    ?? ( json_parse_bytes . req body ) {
        T j → { = opts ( mk j ) }
        F _e → {
            ?? ( json_parse `{}` ) { T j0 → { = opts ( mk j0 ) } F _e2 → {} }
        }
    }
    ? ( __rk_opts_ok ( string_data opts ) ) {} { ^ ( __rk_err 400 `bad options` ) }
    // the state check and every write under the lock; queued only once
    // all of the job's settings are on disk
    : s sid ( string_data id )
    : ~ i res 0  // 0 queued, 1 no such job, 2 busy, 3 a write failed
    : i t ( __rk_lock )
    : String st ( __rk_state sid )
    : s sd ( string_data st )
    : b meshbusy | ( __rk_state_is_f sid `mesh_state` `queued` ) ( __rk_state_is_f sid `mesh_state` `running` )
    ? & ! meshbusy | | ( __rk_eq sd `uploading` ) ( __rk_eq sd `done` ) ( __rk_eq sd `failed` ) {
        : String qnow ( __rk_now )
        ? & & & ( __rk_write_job sid `opts` ( string_data opts ) ) ( __rk_write_job sid `finished` `0` ) ( __rk_write_job sid `started` `0` ) ( __rk_write_job sid `queued_at` ( string_data qnow ) ) {
            ( __rk_log_put sid `` )
            // a new reconstruction replaces the cloud and the views: an
            // object made from the old ones would no longer match
            : String obp ( __rk_jfile sid `object.glb` )
            ?? ( file_delete ( string_data obp ) ) { T _ → {} F _e → {} }
            : b _m1 ( __rk_write_job sid `mesh_state` `` )
            : b _m2 ( __rk_write_job sid `object_attempt` `` )
            : b _m3 ( __rk_write_job sid `mesh_attempt` `` )
            ? ( __rk_set_state sid `queued` ) {} { = res 3 }
        } { = res 3 }
    } { = res ? == ( string_len st ) 0 1 2 }
    ( __rk_unlock t )
    ? == res 1 { ^ ( __rk_err 404 `no such job` ) } {}
    ? == res 2 { ^ ( __rk_err 409 `the job is already queued or running` ) } {}
    ? == res 3 { ^ ( __rk_err 500 `cannot store the job's settings` ) } {}
    : HttpResponse r ( response_json 200 ( __rk_job_json sid F ) )
    ^ r
}

@ __rk_one Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : String st ( __rk_state ( string_data id ) )
    ? == ( string_len st ) 0 { ^ ( __rk_err 404 `no such job` ) } {}
    : HttpResponse r ( response_json 200 ( __rk_job_json ( string_data id ) T ) )
    ^ r
}

@ __rk_delete Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    // check and mark under the lock: once `deleted` is on disk the worker
    // passes the job by, and once the worker has claimed it this refuses
    : ~ i res 0  // 0 marked, 1 no such job, 2 running, 3 cannot mark
    : i t ( __rk_lock )
    : String st ( __rk_state ( string_data id ) )
    ? == ( string_len st ) 0 { = res 1 } {
        ? | ( __rk_eq ( string_data st ) `running` ) ( __rk_state_is_f ( string_data id ) `mesh_state` `running` ) { = res 2 } {
            ? ( __rk_set_state ( string_data id ) `deleted` ) { : b _gone ( __rk_unshare ( string_data id ) ) } { = res 3 }
        }
    }
    ( __rk_unlock t )
    ? == res 1 { ^ ( __rk_err 404 `no such job` ) } {}
    ? == res 2 { ^ ( __rk_err 409 `the job is running` ) } {}
    ? == res 3 { ^ ( __rk_err 500 `cannot remove the job` ) } {}
    : String jd ( __rk_jdir ( string_data id ) )
    ?? ( dir_remove_all ( string_data jd ) ) {
        T _ → {}
        F _e → { ^ ( __rk_err 500 `cannot remove the job's files` ) }
    }
    : HttpResponse r ( response_status_only 204 )
    ^ r
}

// A number for the mesh command line: fixed six decimals, so the line
// holds only digits, '-', '.' and spaces (__rk_opts_ok).
@ __rk_fmt f x → String {
    : String o ( string_new )
    : ~ f v x
    ? < v 0.0 { ( string_push_char o 45 ) = v - 0.0 v } {}
    : ~ i ip # i ( float_floor v )
    : ~ i fp # i ( float_round * - v # f ip 1000000.0 )
    ? >= fp 1000000 { = ip + ip 1 = fp - fp 1000000 } {}
    ( string_push_int o ip )
    ( string_push_char o 46 )
    : ~ i d 100000
    ~ > d 0 { ( string_push_char o + 48 % / fp d 10 ) = d / d 10 }
    ^ o
}

// The object's status, the shape the viewer reads: state (none, queued,
// running, done, failed), and once there is an object its url, view and
// bytes; `progress` is the last line of the mesh log.
// With `attempt` (a request's id) the status is that request's: `replaced`
// once a later request (or a new reconstruction) took its place, and the
// object only when it is the one this request made.
@ __rk_mesh_status s id s attempt → Json {
    : Json o ( json_obj_new )
    : String ms ( __rk_read_job id `mesh_state` )
    : String cur ( __rk_read_job id `mesh_attempt` )
    : String oat ( __rk_read_job id `object_attempt` )
    : b asked > ( nurl_str_len attempt ) 0
    : b replaced & asked ! ( __rk_eq ( string_data cur ) attempt )
    : b ours | ! asked ( __rk_eq ( string_data oat ) attempt )
    : s stv ? replaced `replaced` ? == ( string_len ms ) 0 `none` ( string_data ms )
    : b _s ( json_obj_set o `state` ( json_str_lit stv ) )
    : b _a ( json_obj_set o `attempt` ( json_str_lit ? asked attempt ( string_data cur ) ) )
    : String obp ( __rk_jfile id `object.glb` )
    : ~ i osize -1
    ? & ours ! replaced {
        ?? ( file_size ( string_data obp ) ) { T z → { = osize z } F _e → {} }
    } {}
    ? >= osize 0 {
        // the object's url names the request it answers: once another
        // request replaces it, that url answers 410 instead of the newer one
        : String url ( string_from `/jobs/` )
        ( string_push_str url id ) ( string_push_str url `/object.glb?attempt=` )
        ( string_push_str url ( string_data oat ) )
        : String view ( string_from `/view?glb=` )
        ( string_push_str view ( string_data url ) )
        : b _u ( json_obj_set o `url` ( json_str_lit ( string_data url ) ) )
        : b _v ( json_obj_set o `view` ( json_str_lit ( string_data view ) ) )
        : b _b ( json_obj_set o `bytes` ( json_int osize ) )
    } {}
    : String lp ( __rk_jfile id `mesh.log` )
    : ~ String log ( string_new )
    ?? ( read_file ( string_data lp ) ) { T t → { = log t } F _e → {} }
    : String last ( __rk_last_line log )
    : b _p ( json_obj_set o `progress` ( json_str_lit ( string_data last ) ) )
    ^ o
}

@ __rk_mesh_get HttpRequest req Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : String st ( __rk_state ( string_data id ) )
    ? == ( string_len st ) 0 { ^ ( __rk_err 404 `no such job` ) } {}
    // ?attempt=<hex>: kept only while it is hex, so it is safe to echo
    : String att ( string_new )
    ?? ( query_value ( slice_of_str ( string_data . req query ) ) `attempt` ) {
        T v → {
            : ~ i k 0
            ~ & < k ( slice_len [u] v ) < k 32 {
                : i c ( slice_byte v k )
                ? | & >= c 48 <= c 57 & >= c 97 <= c 102 { ( string_push_char att c ) } {}
                = k + k 1
            }
        }
        F → {}
    }
    : HttpResponse r ( response_json 200 ( __rk_mesh_status ( string_data id ) ( string_data att ) ) )
    ^ r
}

// Ask for a 3-D object: {"box": [x0, y0, z0, x1, y1, z1], "res": n} in the
// point cloud's coordinates. Queued for the worker like a reconstruction.
@ __rk_mesh_post HttpRequest req Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : s sid ( string_data id )
    : ( Vec f ) bx__v ( vec_zeroed [f] 6 )
    : ( Slice f ) bx ( slice_from_vec [f] bx__v )
    : ~ i res 256
    : ~ b okbox F
    ?? ( json_parse_bytes . req body ) {
        T j → {
            = res ( rk_jint j `res` 32 512 256 )
            ?? ( json_obj_get j `box` ) {
                T b → {
                    ? == ( json_arr_len b ) 6 {
                        = okbox T
                        : ~ i k 0
                        ~ < k 6 {
                            : ~ f x 0.0
                            : ~ b num F
                            ?? ( json_arr_get b k ) {
                                T e → { ?? ( json_num_as_f e ) { T v → { = x v = num T } F → {} } }
                                F → {}
                            }
                            // finite and within a kilometre: anything else is not a box
                            ? & & num == 0 ( nurl_is_nan x ) & < x 1000000.0 > x -1000000.0 { ( slice_put [f] bx k x ) } { = okbox F }
                            = k + k 1
                        }
                    } {}
                }
                F → {}
            }
        }
        F _e → {}
    }
    ? okbox {} { ^ ( __rk_err 400 `the request needs "box": six finite numbers` ) } {}
    : String args ( string_from `--box` )
    : ~ i k 0
    ~ < k 6 {
        ( string_push_char args 32 )
        : String fv ( __rk_fmt ( slice_at [f] bx k ) )
        ( string_push_str args ( string_data fv ) )
        = k + k 1
    }
    ( string_push_str args ` --res ` ) ( string_push_int args res )
    : String scp ( __rk_jfile sid `scene.bin` )
    // this request's own id: its status and its object are asked for by it,
    // so a second tab's request is never mistaken for this one's
    : String attempt ( rand_hex_str 6 )
    : ~ i rc 0  // 0 queued, 1 no job, 2 not done, 3 no scene, 4 busy, 5 write failed
    : i t ( __rk_lock )
    : String st ( __rk_state sid )
    ? == ( string_len st ) 0 { = rc 1 } {
        ? ( __rk_eq ( string_data st ) `done` ) {
            ? == 1 ( nurl_path_type ( string_data scp ) ) {
                ? | ( __rk_state_is_f sid `mesh_state` `queued` ) ( __rk_state_is_f sid `mesh_state` `running` ) { = rc 4 } {
                    : String qnow ( __rk_now )
                    ? & & & ( __rk_write_job sid `mesh_req` ( string_data args ) ) ( __rk_write_job sid `mesh.log` `` ) ( __rk_write_job sid `mesh_attempt` ( string_data attempt ) ) ( __rk_write_job sid `mesh_queued_at` ( string_data qnow ) ) {
                        ? ( __rk_write_job sid `mesh_state` `queued` ) {} { = rc 5 }
                    } { = rc 5 }
                }
            } { = rc 3 }
        } { = rc 2 }
    }
    ( __rk_unlock t )
    ? == rc 1 { ^ ( __rk_err 404 `no such job` ) } {}
    ? == rc 2 { ^ ( __rk_err 409 `the reconstruction is not done` ) } {}
    ? == rc 3 { ^ ( __rk_err 409 `this job kept no views: run it again to make 3-D objects` ) } {}
    ? == rc 4 { ^ ( __rk_err 409 `an object is already being made` ) } {}
    ? == rc 5 { ^ ( __rk_err 500 `cannot store the request` ) } {}
    : HttpResponse r ( response_json 202 ( __rk_mesh_status sid ( string_data attempt ) ) )
    ^ r
}

@ __rk_object HttpRequest req Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    // ?attempt=: only that request's object, never a later one's
    ?? ( query_value ( slice_of_str ( string_data . req query ) ) `attempt` ) {
        T v → {
            : String want ( string_new )
            : ~ i k 0
            ~ & < k ( slice_len [u] v ) < k 32 { ( string_push_char want ( slice_byte v k ) ) = k + k 1 }
            : String oat ( __rk_read_job ( string_data id ) `object_attempt` )
            ? ( __rk_eq ( string_data oat ) ( string_data want ) ) {} { ^ ( __rk_err 410 `this object was replaced by a later one` ) }
        }
        F → {}
    }
    ^ ( __rk_send_file ( string_data id ) `object.glb` `.glb` `model/gltf-binary` `no object for this job (yet)` )
}

// A job's file as a download named after the job ("<name><ext>").
@ __rk_send_file s id s file s ext s ctype s missing → HttpResponse {
    : String cp ( __rk_jfile id file )
    ?? ( read_file_bytes ( string_data cp ) ) {
        F _e → { ^ ( __rk_err 404 missing ) }
        T blob → {
            : String nm ( __rk_read_job id `name` )
            : ~ String base ( __rk_safe_name ( string_data nm ) )
            ? == ( string_len base ) 0 { = base ( string_from id ) } {}
            : String fname ( string_from ( string_data base ) )
            ( string_push_str fname ext )
            : String disp ( string_from `attachment; filename="` )
            ( string_push_str disp ( string_data fname ) )
            ( string_push_char disp 34 )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` ctype )
            ( response_set_header r `Content-Disposition` ( string_data disp ) )
            ( response_set_header r `X-Cloud-Name` ( string_data fname ) )
            ( response_set_header r `Cache-Control` `no-store` )
            ( response_set_body_bytes r blob )
            ^ r
        }
    }
}

@ __rk_cloud Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( __rk_err 400 `bad job id` ) }
    ^ ( __rk_send_file ( string_data id ) `cloud.ply` `.ply` `application/octet-stream` `no cloud for this job (yet)` )
}

// ── sharing ─────────────────────────────────────────────────────────

// A job shared read-only. A random token (128 bits, 32 hex digits) names
// it in <data>/shares/<token>, which holds the job id, and in the job's
// own `share` file; both must agree. Under /s/<token> it answers WITHOUT
// the sign-in — a page, the viewer, the cloud, the object — and only
// ever reads: no route under /s/ changes anything, and the viewer is
// served without its crop tool. DELETE .../share, or deleting the job,
// ends the link.

@ __rk_shares_dir → String {
    : RkCfg c ( __rk_cfg )
    ^ ( path_join ( string_data . c data ) `shares` )
}

@ __rk_token_ok s t → b {
    : ( Slice u ) bs ( slice_of_str t )
    ? != ( slice_len [u] bs ) 32 { ^ F } {}
    : ~ i k 0
    ~ < k 32 {
        : i c ( slice_byte bs k )
        ? | & >= c 48 <= c 57 & >= c 97 <= c 102 {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __rk_share_file s token → String {
    : String d ( __rk_shares_dir )
    ^ ( path_join ( string_data d ) token )
}

// The job a token shares, or "" — the token, the index and the job's own
// record must all agree, and the job must not be on its way out.
@ __rk_shared_job s token → String {
    ? ( __rk_token_ok token ) {} { ^ ( string_new ) }
    : String sf ( __rk_share_file token )
    : String raw ( __rk_read ( string_data sf ) )
    : String id ( string_trim raw )
    ? ( __rk_id_ok ( string_data id ) ) {} { ^ ( string_new ) }
    : String mine ( __rk_read_job ( string_data id ) `share` )
    ? ( __rk_eq ( string_data mine ) token ) {} { ^ ( string_new ) }
    : String st ( __rk_state ( string_data id ) )
    ? | == ( string_len st ) 0 ( __rk_eq ( string_data st ) `deleted` ) { ^ ( string_new ) } {}
    ^ id
}

// Ends a job's link (both records); the caller holds the job lock. Either
// deletion alone ends it, so a record already gone is no failure; false
// only when the token still resolves afterwards (a read-only disk).
@ __rk_unshare s id → b {
    : String tok ( __rk_read_job id `share` )
    ? ( __rk_token_ok ( string_data tok ) ) {
        : String sf ( __rk_share_file ( string_data tok ) )
        ?? ( file_delete ( string_data sf ) ) { T _ → {} F _e → {} }
    } {}
    : String jf ( __rk_jfile id `share` )
    ?? ( file_delete ( string_data jf ) ) { T _ → {} F _e → {} }
    ^ == ( string_len ( __rk_shared_job ( string_data tok ) ) ) 0
}

@ __rk_share_json s id s token → HttpResponse {
    : Json o ( json_obj_new )
    : String url ( string_from `/s/` )
    ( string_push_str url token )
    : b _a ( json_obj_set o `id` ( json_str_lit id ) )
    : b _b ( json_obj_set o `share` ( json_str_lit token ) )
    : b _c ( json_obj_set o `url` ( json_str_lit ( string_data url ) ) )
    ^ ( response_json 200 o )
}

// POST /api/jobs/:id/share — the job's link, made on the first call; a
// finished job only (there is nothing to look at before).
@ __rk_share_post Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    : s sid ( string_data id )
    ? ( __rk_id_ok sid ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : ~ i res 0  // 0 shared, 1 no such job, 2 not done, 3 a write failed
    : ~ String tok ( string_new )
    : i t ( __rk_lock )
    : String st ( __rk_state sid )
    ? == ( string_len st ) 0 { = res 1 } {
        ? ( __rk_eq ( string_data st ) `done` ) {
            : String have ( __rk_read_job sid `share` )
            ? ( __rk_token_ok ( string_data have ) ) { = tok ( string_from ( string_data have ) ) } {
                = tok ( rand_hex_str 16 )
                : String sf ( __rk_share_file ( string_data tok ) )
                ?? ( write_file ( string_data sf ) sid ) {
                    T _ → { ? ( __rk_write_job sid `share` ( string_data tok ) ) {} { = res 3 } }
                    F _e → { = res 3 }
                }
            }
        } { = res 2 }
    }
    ( __rk_unlock t )
    ? == res 1 { ^ ( __rk_err 404 `no such job` ) } {}
    ? == res 2 { ^ ( __rk_err 409 `only a finished job can be shared` ) } {}
    ? == res 3 { ^ ( __rk_err 500 `cannot store the link` ) } {}
    ^ ( __rk_share_json sid ( string_data tok ) )
}

// DELETE /api/jobs/:id/share — the link stops working.
@ __rk_share_delete Params ps → HttpResponse {
    : String id ( __rk_param ps `id` )
    : s sid ( string_data id )
    ? ( __rk_id_ok sid ) {} { ^ ( __rk_err 400 `bad job id` ) }
    : i t ( __rk_lock )
    : String st ( __rk_state sid )
    : b known > ( string_len st ) 0
    : ~ b gone T
    ? known { = gone ( __rk_unshare sid ) } {}
    ( __rk_unlock t )
    ? known {} { ^ ( __rk_err 404 `no such job` ) }
    ? gone {} { ^ ( __rk_err 500 `the link could not be ended` ) }
    ^ ( response_status_only 204 )
}

// Text into HTML: the five characters that could end an element or an
// attribute, as entities.
@ __rk_html String out s text → v {
    : ( Slice u ) bs ( slice_of_str text )
    : ~ i k 0
    ~ < k ( slice_len [u] bs ) {
        : i c ( slice_byte bs k )
        ? == c 38 { ( string_push_str out `&amp;` ) } {
            ? == c 60 { ( string_push_str out `&lt;` ) } {
                ? == c 62 { ( string_push_str out `&gt;` ) } {
                    ? == c 34 { ( string_push_str out `&quot;` ) } {
                        ? == c 39 { ( string_push_str out `&#39;` ) } { ( string_push_char out c ) }
                    }
                }
            }
        }
        = k + k 1
    }
}

@ __rk_mb i n → String {
    : String o ( string_new )
    ? >= n 1048576 {
        ( string_push_int o / n 1048576 ) ( string_push_char o 46 ) ( string_push_int o / % n 1048576 104858 )
        ( string_push_str o ` MB` )
    } {
        ( string_push_int o ? > / n 1024 0 / n 1024 1 ) ( string_push_str o ` kB` )
    }
    ^ o
}

@ __rk_shared_head HttpResponse r → v {
    ( response_set_header r `Cache-Control` `no-store` )
    // the token is the key: it must not leave in a Referer
    ( response_set_header r `Referrer-Policy` `no-referrer` )
    ( response_set_header r `X-Robots-Tag` `noindex` )
}

// GET /s/:token — what is shared: the cloud (and the object, if one was
// made) to open in the viewer or download. Nothing to change.
@ __rk_shared_page Params ps → HttpResponse {
    : String tok ( __rk_param ps `token` )
    : String id ( __rk_shared_job ( string_data tok ) )
    ? == ( string_len id ) 0 { ^ ( __rk_err 404 `this link is not shared (any more)` ) } {}
    : s sid ( string_data id )
    : RkCfg c ( __rk_cfg )
    : String nm ( __rk_read_job sid `name` )
    : ~ i cb 0
    : String cp ( __rk_jfile sid `cloud.ply` )
    ?? ( file_size ( string_data cp ) ) { T z → { = cb z } F _e → {} }
    : ~ i ob 0
    : String op ( __rk_jfile sid `object.glb` )
    ?? ( file_size ( string_data op ) ) { T z → { = ob z } F _e → {} }
    : String base ( string_from `/s/` )
    ( string_push_str base ( string_data tok ) )
    : s b ( string_data base )
    : String h ( string_from `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>` )
    ( __rk_html h ( string_data nm ) )
    ( string_push_str h `</title>
<style>
:root { color-scheme: dark; --bg: #0b0d12; --card: #141821; --fg: #e8eaf0; --dim: #8a93a6; --acc: #4c9aff; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.5 system-ui, sans-serif; }
main { max-width: 640px; margin: 0 auto; padding: 32px 16px; }
h1 { font-size: 22px; margin: 0 0 4px; word-break: break-word; }
.sub { color: var(--dim); font-size: 13px; }
.card { background: var(--card); border-radius: 12px; padding: 18px; margin-top: 20px; }
.card h2 { font-size: 14px; margin: 0 0 10px; color: var(--dim); font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
.row { display: flex; gap: 10px; flex-wrap: wrap; }
a.btn { display: inline-block; padding: 10px 16px; border-radius: 8px; background: #222a38; color: var(--fg); text-decoration: none; }
a.btn.primary { background: var(--acc); color: #fff; }
footer { color: var(--dim); font-size: 12px; margin-top: 28px; }
</style></head><body><main>
<h1>` )
    ( __rk_html h ( string_data nm ) )
    ( string_push_str h `</h1>
<div class="sub">a shared 3-D reconstruction &middot; view or download, nothing to sign in to</div>
<div class="card"><h2>Point cloud</h2><div class="row">` )
    ? > cb 0 {
        ( string_push_str h `<a class="btn primary" href="` ) ( string_push_str h b )
        ( string_push_str h `/view?cloud=` ) ( string_push_str h b ) ( string_push_str h `/cloud.ply">View in 3-D</a>` )
        ( string_push_str h `<a class="btn" download href="` ) ( string_push_str h b )
        ( string_push_str h `/cloud.ply">Download .ply (` )
        : String m1 ( __rk_mb cb )
        ( string_push_str h ( string_data m1 ) ) ( string_push_str h `)</a>` )
    } { ( string_push_str h `<span class="sub">the cloud is not there any more</span>` ) }
    ( string_push_str h `</div></div>` )
    ? > ob 0 {
        ( string_push_str h `<div class="card"><h2>3-D object</h2><div class="row"><a class="btn primary" href="` )
        ( string_push_str h b ) ( string_push_str h `/view?glb=` ) ( string_push_str h b )
        ( string_push_str h `/object.glb">View the object</a><a class="btn" download href="` )
        ( string_push_str h b ) ( string_push_str h `/object.glb">Download .glb (` )
        : String m2 ( __rk_mb ob )
        ( string_push_str h ( string_data m2 ) ) ( string_push_str h `)</a></div></div>` )
    } {}
    ( string_push_str h `<footer>Made with ` )
    ( __rk_html h ( string_data . c name ) )
    ( string_push_str h `. The .ply opens in MeshLab, CloudCompare or Blender; the .glb in Blender, the Windows 3D viewer or a browser.</footer>
</main></body></html>
` )
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( __rk_shared_head r )
    ( response_set_body_str r ( string_data h ) )
    ^ r
}

// GET /s/:token/view — the viewer, for a shared link only. Served without
// ?crop, so there is no region tool, and its only data is under /s/.
@ __rk_shared_view Params ps → HttpResponse {
    : String tok ( __rk_param ps `token` )
    : String id ( __rk_shared_job ( string_data tok ) )
    ? == ( string_len id ) 0 { ^ ( __rk_err 404 `this link is not shared (any more)` ) } {}
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( __rk_shared_head r )
    : String page ( vw_page `` )
    ( response_set_body_str r ( string_data page ) )
    ^ r
}

@ __rk_shared_cloud Params ps → HttpResponse {
    : String tok ( __rk_param ps `token` )
    : String id ( __rk_shared_job ( string_data tok ) )
    ? == ( string_len id ) 0 { ^ ( __rk_err 404 `this link is not shared (any more)` ) } {}
    : HttpResponse r ( __rk_send_file ( string_data id ) `cloud.ply` `.ply` `application/octet-stream` `no cloud for this job` )
    ( response_set_header r `Referrer-Policy` `no-referrer` )
    ^ r
}

@ __rk_shared_object Params ps → HttpResponse {
    : String tok ( __rk_param ps `token` )
    : String id ( __rk_shared_job ( string_data tok ) )
    ? == ( string_len id ) 0 { ^ ( __rk_err 404 `this link is not shared (any more)` ) } {}
    : HttpResponse r ( __rk_send_file ( string_data id ) `object.glb` `.glb` `model/gltf-binary` `no object for this job` )
    ( response_set_header r `Referrer-Policy` `no-referrer` )
    ^ r
}

// ── the server ──────────────────────────────────────────────────────

@ __rk_usage RkApp app → v {
    : s nm ( string_data . app name )
    ( nurl_print `usage: ` ) ( nurl_print nm ) ( nurl_print ` serve [--host A] [--port N] [--data DIR] [--password P]\n\n` )
    ( nurl_print `  --host A        bind address (default 127.0.0.1; 0.0.0.0 = every interface)\n` )
    ( nurl_print `  --port N        port (default ` ) ( nurl_print ( nurl_str_int . app port ) ) ( nurl_print `)\n` )
    ( nurl_print `  --data DIR      jobs, uploads and clouds (default ~/` ) ( nurl_print ( string_data . app home_dir ) ) ( nurl_print `)\n` )
    ( nurl_print `  --password P    require HTTP Basic sign-in with this password, any user name\n` )
    ( nurl_print `                  (or $` ) ( nurl_print ( string_data . app pass_env ) ) ( nurl_print `)\n` )
    ( nurl_print `  --tls-cert F    serve HTTPS with this certificate chain (PEM)...\n` )
    ( nurl_print `  --tls-key F     ...and its key; without them, put a TLS proxy in front\n` )
    ( nurl_print `                  of any address but loopback (Basic sign-in is plain text)\n` )
}

// `<model> serve ...` — argv[1] is "serve". Returns the exit code.
@ rk_serve RkApp app → i {
    : String nmv ( string_from ( string_data . app name ) )
    : s nm ( string_data nmv )
    : ~ s host `127.0.0.1`
    : ~ i port . app port
    : ~ String data ( string_new )
    : ~ String pass ( string_new )
    : ~ String tcert ( string_new )
    : ~ String tkey ( string_new )
    ?? ( env_get ( string_data . app pass_env ) ) { T v → { = pass v } F → {} }
    : i argc ( nurl_argc )
    : ~ i k 2
    ~ < k argc {
        : s a ( nurl_argv k )
        : b has < + k 1 argc
        ? & | ( __rk_eq a `--host` ) ( __rk_eq a `--addr` ) has { = host ( nurl_argv + k 1 ) = k + k 1 } {
            ? & ( __rk_eq a `--port` ) has { = port ( nurl_str_to_int ( nurl_argv + k 1 ) ) = k + k 1 } {
                ? & ( __rk_eq a `--data` ) has { = data ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                    ? & ( __rk_eq a `--password` ) has { = pass ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                        ? & ( __rk_eq a `--tls-cert` ) has { = tcert ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                            ? & ( __rk_eq a `--tls-key` ) has { = tkey ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                                ? | ( __rk_eq a `--help` ) ( __rk_eq a `-h` ) { ( __rk_usage app ) ^ 0 } {}
                                ( nurl_print nm ) ( nurl_print ` serve: unknown option ` )
                                ( nurl_print a ) ( nurl_print `\n\n` )
                                ( __rk_usage app )
                                ^ 1
                            }
                        }
                    }
                }
            }
        }
        = k + k 1
    }
    ? == ( string_len data ) 0 {
        : String home ( env_home_dir )
        = data ( path_join ( string_data home ) ( string_data . app home_dir ) )
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
    ?? q { T _ → { ( __rk_tag ) ( nurl_eprintln `the data directory may not contain a single quote` ) ^ 1 } F _ → {} }
    : ~ String bin ( string_new )
    ?? ( fs_readlink `/proc/self/exe` ) {
        T p → { = bin p }
        F _e → { = bin ( string_from ( nurl_argv 0 ) ) }
    }
    : String jobs ( path_join ( string_data data ) `jobs` )
    : String shd ( path_join ( string_data data ) `shares` )
    ?? ( dir_create_all ( string_data shd ) ) { T _ → {} F _e → {} }
    ?? ( dir_create_all ( string_data jobs ) ) {
        T _ → {}
        F _e → {
            ( __rk_tag ) ( nurl_eprint `cannot create ` )
            ( nurl_eprintln ( string_data jobs ) )
            ^ 1
        }
    }
    : b noauth == ( string_len pass ) 0
    : b hc > ( string_len tcert ) 0
    : b hk > ( string_len tkey ) 0
    : b usetls & hc hk
    ? == hc hk {} {
        ( __rk_tag ) ( nurl_eprintln `--tls-cert and --tls-key go together` )
        ^ 1
    }
    : String page ( rk_ui_page app )
    ( locked_set [RkApp] g_rk_app app )
    ( locked_set [RkCfg] g_rk_cfg @ RkCfg { ( string_from ( string_data data ) ) ( string_from ( string_data bin ) ) pass ( string_from nm ) page } )
    // held, through this binding, until rk_serve returns
    : ?PFile owner ( __rk_own_data ( string_data data ) )
    ?? owner {
        T _pf → {}
        F → {
            ( __rk_tag ) ( nurl_eprint `another server already owns ` )
            ( nurl_eprintln ( string_data data ) )
            ^ 1
        }
    }
    ( __rk_recover )

    : ( @ v ) workfn \ → v { ( __rk_worker ) }
    ?? ( thread_spawn workfn ) {
        T th → { ( thread_detach th ) }
        F _te → {
            ( __rk_tag ) ( nurl_eprintln `cannot start the worker thread` )
            ^ 1
        }
    }

    : HttpApp a ( http_app_new )
    ( http_app_async a 0 )
    // Bodies are buffered before the sign-in can look at them, so the cap
    // bounds what an unauthenticated request can make the server hold.
    // The page sends files in 32 MiB pieces; 40 MiB leaves room.
    ( http_app_body_max a 41943040 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 60000 )
    ( http_app_get a `/healthz` \ HttpRequest rq Params ps → HttpResponse { ^ ( response_text 200 `ok` ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_page ) } )
    ( http_app_get a `/view` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_viewer ) } )
    ( http_app_get a `/api/jobs` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_list ) } )
    ( http_app_post a `/api/jobs` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_create rq ) } )
    ( http_app_get a `/api/jobs/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_one ps ) } )
    ( http_app_delete a `/api/jobs/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_delete ps ) } )
    ( http_app_put a `/api/jobs/:id/files/:name` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_upload rq ps ) } )
    ( http_app_post a `/api/jobs/:id/start` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_start rq ps ) } )
    ( http_app_get a `/jobs/:id/cloud.ply` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_cloud ps ) } )
    ( http_app_post a `/api/jobs/:id/share` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_share_post ps ) } )
    ( http_app_delete a `/api/jobs/:id/share` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_share_delete ps ) } )
    // read-only and without the sign-in (see the gate below)
    ( http_app_get a `/s/:token` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_shared_page ps ) } )
    ( http_app_get a `/s/:token/view` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_shared_view ps ) } )
    ( http_app_get a `/s/:token/cloud.ply` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_shared_cloud ps ) } )
    ( http_app_get a `/s/:token/object.glb` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_shared_object ps ) } )
    ( http_app_get a `/jobs/:id/object.glb` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_object rq ps ) } )
    ( http_app_get a `/api/jobs/:id/mesh` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_mesh_get rq ps ) } )
    ( http_app_post a `/api/jobs/:id/mesh` \ HttpRequest rq Params ps → HttpResponse { ^ ( __rk_mesh_post rq ps ) } )
    ? noauth {} {
        : ( @ ( @ HttpResponse HttpRequest ) ( @ HttpResponse HttpRequest ) ) gate
        \ ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
            ^ \ HttpRequest req → HttpResponse {
                // a shared link's GETs are the token's to answer, not the
                // password's: every /s/ route reads, and checks its token
                : b shared & ( __rk_eq ( string_data . req method ) `GET` ) ( string_starts_with . req path `/s/` )
                ? | | ( __rk_eq ( string_data . req path ) `/healthz` ) shared ( __rk_authed req ) { ^ ( inner req ) } {}
                : RkCfg cc ( __rk_cfg )
                : String msg ( string_from `sign in to use ` )
                ( string_push_str msg ( string_data . cc name ) ) ( string_push_str msg `\n` )
                : HttpResponse r ( response_text 401 ( string_data msg ) )
                : String realm ( string_from `Basic realm="` )
                ( string_push_str realm ( string_data . cc name ) ) ( string_push_str realm `", charset="UTF-8"` )
                ( response_set_header r `WWW-Authenticate` ( string_data realm ) )
                ^ r
            }
        }
        ( http_app_use a gate )
    }

    ( __rk_tag ) ( nurl_eprint ? usetls `https://` `http://` )
    ( nurl_eprint host ) ( nurl_eprint `:` ) ( nurl_eprint ( nurl_str_int port ) )
    ( nurl_eprint `  data ` ) ( nurl_eprint ( string_data data ) )
    ( nurl_eprintln ? noauth `  (NO PASSWORD — keep it on a private network)` `  (password required)` )
    : b loopback | ( __rk_eq host `127.0.0.1` ) ( __rk_eq host `localhost` )
    ? & & ! noauth ! usetls ! loopback {
        ( __rk_tag ) ( nurl_eprintln `the Basic sign-in crosses the network in plain text here — front this port with a TLS proxy (an ingress) or pass --tls-cert/--tls-key` )
    } {}
    : i rc ? usetls ( http_app_listen_tls a host port ( string_data tcert ) ( string_data tkey ) ) ( http_app_listen a host port )

    // SIGTERM ended the listener: end the reconstruction in flight and
    // queue its job again, so the next start resumes it
    // the stop flag under the job lock: a spawn either happened before
    // (and its child is found below) or does not happen at all
    : i t0 ( __rk_lock )
    ( locked_set [i] g_rk_stop 1 )
    ( __rk_unlock t0 )
    : ( Vec String ) ids ( __rk_job_ids )
    : ~ i j 0
    ~ < j ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids j ) {
            T id → {
                ( __rk_stop_one ( string_data id ) `state` )
                ( __rk_stop_one ( string_data id ) `mesh_state` )
            }
            F → {}
        }
        = j + j 1
    }
    ^ ? == rc 0 0 1
}
