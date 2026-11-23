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
//   PUT    /api/jobs/:id/files/:name  one input file, the raw request body,
//                                     in pieces: ?offset=N appends at byte N
//   POST   /api/jobs/:id/start        {max_views, stride, ...} → "queued"
//   GET    /api/jobs/:id              one job, with its whole log
//   DELETE /api/jobs/:id              the job and its files
//   GET    /jobs/:id/cloud.ply        the result
//   POST   /api/jobs/:id/mesh         {box, res} → a 3-D object queued
//   GET    /api/jobs/:id/mesh         its state, and once done its url
//   GET    /jobs/:id/object.glb       the object (binary glTF)
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
// Every state change a client and the worker can race on — the worker
// claiming a queued job, DELETE, a start — runs under one lock
// (g_mas_lk), so a job is claimed or deleted, never both. The worker's
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

@ __mas_lk_blank → ( Locked i ) { ^ ( locked_new [i] 0 ) }

// The job-state lock: checked out for the length of a state transition.
: ( Locked i ) g_mas_lk ( __mas_lk_blank )

// 1 once the server is shutting down: the worker then leaves the job it
// was running to the shutdown, which queues it again.
: ( Locked i ) g_mas_stop ( __mas_lk_blank )

@ __mas_lock → i { ^ ( locked_take [i] g_mas_lk ) }

@ __mas_unlock i t → v { ( locked_restore [i] g_mas_lk t ) }

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
// '_'), never starting with '.', at most 120 bytes. A long name loses the
// end of its stem, never its extension: the extension is what decides
// image vs video.
@ __mas_safe_name s raw → String {
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

// the same for another state file of the job (mesh_state)
@ __mas_state_is_f s id s file s want → b {
    : String st ( __mas_read_job id file )
    ^ ( __mas_eq ( string_data st ) want )
}

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
    : String scp ( __mas_jfile id `scene.bin` )
    : b _sc ( json_obj_set o `scene` ( json_bool == 1 ( nurl_path_type ( string_data scp ) ) ) )
    : String ms ( __mas_read_job id `mesh_state` )
    : b _ms ( json_obj_set o `mesh_state` ( json_str_lit ( string_data ms ) ) )
    : String obp ( __mas_jfile id `object.glb` )
    : ~ i obytes 0
    ?? ( file_size ( string_data obp ) ) { T z → { = obytes z } F _e → {} }
    : b _ob ( json_obj_set o `object_bytes` ( json_int obytes ) )
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
@ __mas_claim_next → String {
    : ( Vec String ) ids ( __mas_job_ids )
    : ~ String got ( string_new )
    : i t ( __mas_lock )
    // a shutdown sets its flag under this lock: claimed before it, the work
    // is swept by the shutdown; after it, nothing is claimed
    : ~ b unsettled ( __mas_stopping )
    : ~ i u 0
    ~ < u ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids u ) {
            T id → {
                ? | ( __mas_state_is ( string_data id ) `running` ) ( __mas_state_is_f ( string_data id ) `mesh_state` `running` ) { = unsettled T } {}
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
                ? ( __mas_state_is sid `queued` ) {
                    : i qt ( __mas_read_int sid `queued_at` )
                    ? | == best_kind 0 < qt best_t { = best_kind 1 = best_id ( string_from sid ) = best_t qt } {}
                } {}
                // an object only of a job still done (not deleted, not re-run)
                ? & ( __mas_state_is sid `done` ) ( __mas_state_is_f sid `mesh_state` `queued` ) {
                    : i qt ( __mas_read_int sid `mesh_queued_at` )
                    ? | == best_kind 0 < qt best_t { = best_kind 2 = best_id ( string_from sid ) = best_t qt } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? == best_kind 1 {
        ? ( __mas_set_state ( string_data best_id ) `running` ) { = got ( string_from ( string_data best_id ) ) } {}
    } {}
    ? == best_kind 2 {
        ? ( __mas_write_job ( string_data best_id ) `mesh_state` `running` ) {
            = got ( string_from `m:` )
            ( string_push_str got ( string_data best_id ) )
        } {}
    } {}
    ( __mas_unlock t )
    ^ got
}

// A finished run's terminal state, written under the job lock and retried
// with a growing pause until it is on disk: the child is gone, so if the
// write were lost the job would stay `running` and hold the queue. A
// shutdown that queued the work again in the meantime is overwritten only
// by a real outcome, never by nothing (a stopped run writes nothing).
@ __mas_settle s id s file s value → v {
    : ~ i pause 500
    ~ T {
        : i t ( __mas_lock )
        : b ok ( __mas_write_job id file value )
        ( __mas_unlock t )
        ? ok { ^ v } {}
        ( nurl_eprint `map-anything serve: cannot record job ` ) ( nurl_eprint id )
        ( nurl_eprint ` ` ) ( nurl_eprint file ) ( nurl_eprintln `; retrying` )
        ( sleep_ms pause )
        = pause ? < pause 30000 * pause 2 30000
    }
}

@ __mas_stopping → b { ^ != 0 ( locked_get [i] g_mas_stop ) }

// The pid of a running job's child, or 0 when there is none — and then
// none can appear. Each run publishes its pid in pid.<token>, named for
// the run's one-time token in `run`, so a shell from an older run can
// never overwrite the current run's pid. The token is read first; when no
// pid shows for it within 2 s, the token is voided and the same file is
// read once more: a shell still on its way to `exec` either sees the void
// and exits, or had already written its pid and is found. -1 when the
// void could not be written: the old token is still good, so the job must
// not run again yet (the caller leaves it `running` for a later recovery).
@ __mas_child_of s id → i {
    : String tok ( __mas_read_job id `run` )
    ? | == ( string_len tok ) 0 ( __mas_eq ( string_data tok ) `void` ) { ^ 0 } {}
    : String pname ( string_from `pid.` )
    ( string_push_str pname ( string_data tok ) )
    : ~ i n 0
    ~ < n 20 {
        : i pid ( __mas_read_int id ( string_data pname ) )
        ? > pid 0 { ^ pid } {}
        ( sleep_ms 100 )
        = n + n 1
    }
    ? ( __mas_write_job id `run` `void` ) {} { ^ -1 }
    ^ ( __mas_read_int id ( string_data pname ) )
}

// Every pid.<token> left in a job directory (by runs that are over).
@ __mas_clear_pids s id → v {
    : String jd ( __mas_jdir id )
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
@ __mas_own_data s data → ?PFile {
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
@ __mas_is_our_child i pid → b {
    ? ( __mas_cmdline_has pid `cloud.tmp.ply` ) { ^ T } {}
    ^ ( __mas_cmdline_has pid `object.tmp.glb` )
}

@ __mas_cmdline_has i pid s what → b {
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
// and a zombie's /proc command line is empty, so __mas_is_our_child says
// it has gone).
// T once `gone` holds; F if the process outlived even SIGKILL (stuck in
// uninterruptible I/O, say), and then the caller must not run its job again.
@ __mas_end_child i pid ( @ b ) gone → b {
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

@ __mas_log_put s id s text → v {
    : String logp ( __mas_jfile id `log` )
    ?? ( write_file ( string_data logp ) text ) { T _ → {} F _e → {} }
}

// The shell line every child starts with: into the job directory, its own
// pid into pid.<token>, on only while <token> is still the job's run, then
// `exec` the server's own binary (so the pid is the child's to the end).
// The pid file named for the token means a shell from an older run can
// never overwrite the current run's pid, and a shell delayed past a
// shutdown or a recovery — which void the token when they find no pid —
// exits instead of starting a second run.
@ __mas_cmd_head s jd s token s bin → String {
    : String cmd ( string_from `cd ` )
    ( __mas_q cmd jd )
    ( string_push_str cmd ` && echo $$ > pid.` )
    ( string_push_str cmd token )
    ( string_push_str cmd ` && [ "$(cat run)" = ` )
    ( string_push_str cmd token )
    ( string_push_str cmd ` ] && exec ` )
    ( __mas_q cmd bin )
    ^ cmd
}

// Spawn `cmd` (made with __mas_cmd_head and this `token`) under the job
// lock, unless a shutdown has begun — the shutdown takes the same lock, so
// it either runs first (nothing is spawned) or finds the child — and wait
// for it. The exit code; -1 when it could not be started; -2 when a
// shutdown began (before the spawn, or by ending the child): the job is
// then the shutdown's to queue again and the caller writes nothing.
@ __mas_spawn_wait s id s token String cmd → i {
    : String jd ( __mas_jdir id )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args ( string_data cmd ) )
    : String pidn ( string_from `pid.` )
    ( string_push_str pidn token )
    : String pidp ( path_join ( string_data jd ) ( string_data pidn ) )
    ( __mas_clear_pids id )
    : i t ( __mas_lock )
    : ~ ? ProcChild got @ ?ProcChild { F }
    : ~ b spawn_failed F
    ? ( __mas_stopping ) {} {
        ? ( __mas_write_job id `run` token ) {} { = spawn_failed T }
    }
    ? | ( __mas_stopping ) spawn_failed {} {
        ?? ( process_spawn `/bin/sh` args ) {
            T ch → { = got @ ?ProcChild { T ch } }
            F _e → { = spawn_failed T }
        }
    }
    ( __mas_unlock t )
    ? spawn_failed { ^ -1 } {}
    ?? got {
        F → { ^ -2 }
        T ch → {
            : i code ( proc_wait ch )
            ?? ( file_delete ( string_data pidp ) ) { T _ → {} F _e → {} }
            ? ( __mas_stopping ) { ^ -2 } {}
            ^ code
        }
    }
}

// Run a job the worker has claimed (its state is already `running`).
@ __mas_run s id → v {
    : MaCfg c ( __mas_cfg )
    : String jd ( __mas_jdir id )
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
                // the job's own files and not the server's data path; the
                // views are kept (scene.bin) for 3-D objects made later
                : String token ( rand_hex_str 8 )
                : String cmd ( __mas_cmd_head ( string_data jd ) ( string_data token ) ( string_data . c bin ) )
                ( string_push_char cmd 32 )
                ( __mas_q cmd ( string_data inp ) )
                ( string_push_str cmd ` -o cloud.tmp.ply --scene scene.bin ` )
                ( string_push_str cmd ( string_data opts ) )
                ( string_push_str cmd ` < /dev/null > log 2>&1` )
                ( nurl_eprint `map-anything serve: job ` )
                ( nurl_eprint id )
                ( nurl_eprint ` running: ` )
                ( nurl_eprintln ( string_data opts ) )
                : i code ( __mas_spawn_wait id ( string_data token ) cmd )
                ? == code -2 { ^ v } {}
                ? == code -1 { ( __mas_log_put id `map-anything serve: could not start the reconstruction` ) } {}
                ? == code 0 {
                    ?? ( fs_rename ( string_data tmp ) ( string_data out ) ) {
                        T _ → { = ok T }
                        F _e → {}
                    }
                } {}
            } {
                ( __mas_log_put id `map-anything serve: the job's options are malformed` )
            }
        }
    }
    : String t1 ( __mas_now )
    : b _e ( __mas_write_job id `finished` ( string_data t1 ) )
    ( __mas_settle id `state` ? ok `done` `failed` )
    ( nurl_eprint `map-anything serve: job ` )
    ( nurl_eprint id )
    ( nurl_eprintln ? ok ` done` ` failed` )
}

// Make a job's 3-D object (its mesh_state is already `running`): the mesh
// subcommand over the views the reconstruction kept, with the box and the
// resolution the request left in mesh_req.
@ __mas_run_mesh s id → v {
    : MaCfg c ( __mas_cfg )
    : String jd ( __mas_jdir id )
    : String args ( __mas_read_job id `mesh_req` )
    : String attempt ( __mas_read_job id `mesh_attempt` )
    : ~ b ok F
    ? ( __mas_opts_ok ( string_data args ) ) {
        : String token ( rand_hex_str 8 )
        : String cmd ( __mas_cmd_head ( string_data jd ) ( string_data token ) ( string_data . c bin ) )
        ( string_push_str cmd ` mesh scene.bin -o object.tmp.glb ` )
        ( string_push_str cmd ( string_data args ) )
        ( string_push_str cmd ` < /dev/null > mesh.log 2>&1` )
        ( nurl_eprint `map-anything serve: job ` ) ( nurl_eprint id )
        ( nurl_eprint ` meshing: ` ) ( nurl_eprintln ( string_data args ) )
        : i code ( __mas_spawn_wait id ( string_data token ) cmd )
        ? == code -2 { ^ v } {}
        ? == code 0 {
            : String tmp ( path_join ( string_data jd ) `object.tmp.glb` )
            : String out ( path_join ( string_data jd ) `object.glb` )
            ?? ( fs_rename ( string_data tmp ) ( string_data out ) ) { T _ → { = ok T } F _e → {} }
            // which request the object answers (the status names it)
            ? ok { ( __mas_settle id `object_attempt` ( string_data attempt ) ) } {}
        } {}
    } {}
    ( __mas_settle id `mesh_state` ? ok `done` `failed` )
    ( nurl_eprint `map-anything serve: job ` ) ( nurl_eprint id )
    ( nurl_eprintln ? ok ` object done` ` object failed` )
}

@ __mas_worker → v {
    ~ T {
        ? ( __mas_stopping ) { ( sleep_ms 1000 ) } {
            : String id ( __mas_claim_next )
            ? > ( string_len id ) 0 {
                ? ( string_starts_with id `m:` ) {
                    : String mid ( string_substr id 2 - ( string_len id ) 2 )
                    ( __mas_run_mesh ( string_data mid ) )
                } { ( __mas_run ( string_data id ) ) }
            } { ( sleep_ms 1000 ) }
        }
    }
}

// At shutdown: the child of one state file of one job, if it is running,
// ended and its work queued again. With the token not voided (pid < 0), or
// a child that outlived SIGKILL, it stays `running`: the next start's
// recovery tries again.
@ __mas_stop_one s id s file → v {
    ? ( __mas_state_is_f id file `running` ) {} { ^ v }
    : i pid ( __mas_child_of id )
    : ~ b ended T
    ? > pid 0 {
        ( nurl_eprint `map-anything serve: stopping the child of job ` )
        ( nurl_eprintln id )
        = ended ( __mas_end_child pid \ → b { ^ ! ( __mas_is_our_child pid ) } )
    } {}
    ? & >= pid 0 ended {
        // only if it is still that same run: a worker that finished first
        // has recorded `done` or `failed`, and that stays
        : i t ( __mas_lock )
        ? ( __mas_state_is_f id file `running` ) { : b _q ( __mas_write_job id file `queued` ) } {}
        ( __mas_unlock t )
    } {}
}

// One state file of one job: `running` when the last process stopped means
// its child may still be going — end it, then queue the work again.
@ __mas_recover_one s id s file → v {
    ? ( __mas_state_is_f id file `running` ) {} { ^ v }
    : i pid ( __mas_child_of id )
    ? < pid 0 {
        // its token could not be voided: running it again now could meet a
        // late child of the old run — leave it
        ( nurl_eprint `map-anything serve: cannot void the run token of job ` )
        ( nurl_eprint id )
        ( nurl_eprintln `; left running until a later start can` )
        ^ v
    } {}
    : ~ b ended T
    ? ( __mas_is_our_child pid ) {
        ( nurl_eprint `map-anything serve: ending the orphaned child, pid ` )
        ( nurl_eprintln ( nurl_str_int pid ) )
        = ended ( __mas_end_child pid \ → b { ^ ! ( __mas_is_our_child pid ) } )
    } {}
    ? ended {
        ( __mas_clear_pids id )
        : b _q ( __mas_write_job id file `queued` )
        ( nurl_eprint `map-anything serve: re-queued the interrupted ` )
        ( nurl_eprint ? ( __mas_eq file `state` ) `job ` `object of job ` )
        ( nurl_eprintln id )
    } {
        ( nurl_eprint `map-anything serve: the child of job ` )
        ( nurl_eprint id )
        ( nurl_eprintln ` outlived SIGKILL; left running, nothing starts beside it` )
    }
}

// A job the last process was running when it stopped runs again — after
// the child that process left behind, if it is still going, has ended.
@ __mas_recover → v {
    : ( Vec String ) ids ( __mas_job_ids )
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T id → {
                ( __mas_recover_one ( string_data id ) `state` )
                ( __mas_recover_one ( string_data id ) `mesh_state` )
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
    : String raw ( __mas_param ps `name` )
    : String fname ( __mas_safe_name ( string_data raw ) )
    ? == ( string_len fname ) 0 { ^ ( __mas_err 400 `the file needs a name` ) } {}
    : String ind ( __mas_jfile ( string_data id ) `input` )
    : String fp ( path_join ( string_data ind ) ( string_data fname ) )
    : i off ?? ( request_query_int req `offset` ) { T v → v F → 0 }
    // The state check, the size check and the write under the job lock:
    // two pieces racing for one offset, or two first pieces for one name,
    // cannot both pass, and a job that has been queued or deleted takes
    // no more bytes. (A piece is at most 32 MiB, so the lock is short.)
    : ~ i res 0  // 0 stored, 1 not uploading, 2 name taken, 3 out of order, 4 write failed
    : i t ( __mas_lock )
    ? ( __mas_state_is ( string_data id ) `uploading` ) {
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
    ( __mas_unlock t )
    ? == res 1 { ^ ( __mas_err 409 `the job is not taking uploads` ) } {}
    ? == res 2 { ^ ( __mas_err 409 `the job already has a file of that name` ) } {}
    ? == res 3 { ^ ( __mas_err 409 `that piece does not continue the file` ) } {}
    ? == res 4 { ^ ( __mas_err 500 `cannot store the file` ) } {}
    : Json o ( json_obj_new )
    : b _n ( json_obj_set o `name` ( json_str_lit ( string_data fname ) ) )
    : b _b ( json_obj_set o `bytes` ( json_int + off ( vec_len [u] . req body ) ) )
    : HttpResponse r ( response_json 201 o )
    ^ r
}

// Queue a job: the first time after its upload, or again with new options
// once it has finished.
@ __mas_start HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    ?? ( __mas_input ( string_data id ) ) {
        F why → { ^ ( __mas_err 400 ( string_data why ) ) }
        T _p → {}
    }
    : ~ i maxv 24
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
    // a video is sampled across its whole length (the CLI's default with a
    // view budget); "every frame" keeps the old fixed rate
    ? == maxv 0 { ( string_push_str opts ` --fps 2` ) } {}
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
    // the state check and every write under the lock; queued only once
    // all of the job's settings are on disk
    : s sid ( string_data id )
    : ~ i res 0  // 0 queued, 1 no such job, 2 busy, 3 a write failed
    : i t ( __mas_lock )
    : String st ( __mas_state sid )
    : s sd ( string_data st )
    : b meshbusy | ( __mas_state_is_f sid `mesh_state` `queued` ) ( __mas_state_is_f sid `mesh_state` `running` )
    ? & ! meshbusy | | ( __mas_eq sd `uploading` ) ( __mas_eq sd `done` ) ( __mas_eq sd `failed` ) {
        : String qnow ( __mas_now )
        ? & & & ( __mas_write_job sid `opts` ( string_data opts ) ) ( __mas_write_job sid `finished` `0` ) ( __mas_write_job sid `started` `0` ) ( __mas_write_job sid `queued_at` ( string_data qnow ) ) {
            ( __mas_log_put sid `` )
            // a new reconstruction replaces the cloud and the views: an
            // object made from the old ones would no longer match
            : String obp ( __mas_jfile sid `object.glb` )
            ?? ( file_delete ( string_data obp ) ) { T _ → {} F _e → {} }
            : b _m1 ( __mas_write_job sid `mesh_state` `` )
            : b _m2 ( __mas_write_job sid `object_attempt` `` )
            : b _m3 ( __mas_write_job sid `mesh_attempt` `` )
            ? ( __mas_set_state sid `queued` ) {} { = res 3 }
        } { = res 3 }
    } { = res ? == ( string_len st ) 0 1 2 }
    ( __mas_unlock t )
    ? == res 1 { ^ ( __mas_err 404 `no such job` ) } {}
    ? == res 2 { ^ ( __mas_err 409 `the job is already queued or running` ) } {}
    ? == res 3 { ^ ( __mas_err 500 `cannot store the job's settings` ) } {}
    : HttpResponse r ( response_json 200 ( __mas_job_json sid F ) )
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
    // check and mark under the lock: once `deleted` is on disk the worker
    // passes the job by, and once the worker has claimed it this refuses
    : ~ i res 0  // 0 marked, 1 no such job, 2 running, 3 cannot mark
    : i t ( __mas_lock )
    : String st ( __mas_state ( string_data id ) )
    ? == ( string_len st ) 0 { = res 1 } {
        ? | ( __mas_eq ( string_data st ) `running` ) ( __mas_state_is_f ( string_data id ) `mesh_state` `running` ) { = res 2 } {
            ? ( __mas_set_state ( string_data id ) `deleted` ) {} { = res 3 }
        }
    }
    ( __mas_unlock t )
    ? == res 1 { ^ ( __mas_err 404 `no such job` ) } {}
    ? == res 2 { ^ ( __mas_err 409 `the job is running` ) } {}
    ? == res 3 { ^ ( __mas_err 500 `cannot remove the job` ) } {}
    : String jd ( __mas_jdir ( string_data id ) )
    ?? ( dir_remove_all ( string_data jd ) ) {
        T _ → {}
        F _e → { ^ ( __mas_err 500 `cannot remove the job's files` ) }
    }
    : HttpResponse r ( response_status_only 204 )
    ^ r
}

// A number for the mesh command line: fixed six decimals, so the line
// holds only digits, '-', '.' and spaces (__mas_opts_ok).
@ __mas_fmt f x → String {
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
@ __mas_mesh_status s id s attempt → Json {
    : Json o ( json_obj_new )
    : String ms ( __mas_read_job id `mesh_state` )
    : String cur ( __mas_read_job id `mesh_attempt` )
    : String oat ( __mas_read_job id `object_attempt` )
    : b asked > ( nurl_str_len attempt ) 0
    : b replaced & asked ! ( __mas_eq ( string_data cur ) attempt )
    : b ours | ! asked ( __mas_eq ( string_data oat ) attempt )
    : s stv ? replaced `replaced` ? == ( string_len ms ) 0 `none` ( string_data ms )
    : b _s ( json_obj_set o `state` ( json_str_lit stv ) )
    : b _a ( json_obj_set o `attempt` ( json_str_lit ? asked attempt ( string_data cur ) ) )
    : String obp ( __mas_jfile id `object.glb` )
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
    : String lp ( __mas_jfile id `mesh.log` )
    : ~ String log ( string_new )
    ?? ( read_file ( string_data lp ) ) { T t → { = log t } F _e → {} }
    : String last ( __mas_last_line log )
    : b _p ( json_obj_set o `progress` ( json_str_lit ( string_data last ) ) )
    ^ o
}

@ __mas_mesh_get HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : String st ( __mas_state ( string_data id ) )
    ? == ( string_len st ) 0 { ^ ( __mas_err 404 `no such job` ) } {}
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
    : HttpResponse r ( response_json 200 ( __mas_mesh_status ( string_data id ) ( string_data att ) ) )
    ^ r
}

// Ask for a 3-D object: {"box": [x0, y0, z0, x1, y1, z1], "res": n} in the
// point cloud's coordinates. Queued for the worker like a reconstruction.
@ __mas_mesh_post HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    : s sid ( string_data id )
    : ( Vec f ) bx__v ( vec_zeroed [f] 6 )
    : ( Slice f ) bx ( slice_from_vec [f] bx__v )
    : ~ i res 256
    : ~ b okbox F
    ?? ( json_parse_bytes . req body ) {
        T j → {
            = res ( __mas_jint j `res` 32 512 256 )
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
    ? okbox {} { ^ ( __mas_err 400 `the request needs "box": six finite numbers` ) } {}
    : String args ( string_from `--box` )
    : ~ i k 0
    ~ < k 6 {
        ( string_push_char args 32 )
        : String fv ( __mas_fmt ( slice_at [f] bx k ) )
        ( string_push_str args ( string_data fv ) )
        = k + k 1
    }
    ( string_push_str args ` --res ` ) ( string_push_int args res )
    : String scp ( __mas_jfile sid `scene.bin` )
    // this request's own id: its status and its object are asked for by it,
    // so a second tab's request is never mistaken for this one's
    : String attempt ( rand_hex_str 6 )
    : ~ i rc 0  // 0 queued, 1 no job, 2 not done, 3 no scene, 4 busy, 5 write failed
    : i t ( __mas_lock )
    : String st ( __mas_state sid )
    ? == ( string_len st ) 0 { = rc 1 } {
        ? ( __mas_eq ( string_data st ) `done` ) {
            ? == 1 ( nurl_path_type ( string_data scp ) ) {
                ? | ( __mas_state_is_f sid `mesh_state` `queued` ) ( __mas_state_is_f sid `mesh_state` `running` ) { = rc 4 } {
                    : String qnow ( __mas_now )
                    ? & & & ( __mas_write_job sid `mesh_req` ( string_data args ) ) ( __mas_write_job sid `mesh.log` `` ) ( __mas_write_job sid `mesh_attempt` ( string_data attempt ) ) ( __mas_write_job sid `mesh_queued_at` ( string_data qnow ) ) {
                        ? ( __mas_write_job sid `mesh_state` `queued` ) {} { = rc 5 }
                    } { = rc 5 }
                }
            } { = rc 3 }
        } { = rc 2 }
    }
    ( __mas_unlock t )
    ? == rc 1 { ^ ( __mas_err 404 `no such job` ) } {}
    ? == rc 2 { ^ ( __mas_err 409 `the reconstruction is not done` ) } {}
    ? == rc 3 { ^ ( __mas_err 409 `this job kept no views: run it again to make 3-D objects` ) } {}
    ? == rc 4 { ^ ( __mas_err 409 `an object is already being made` ) } {}
    ? == rc 5 { ^ ( __mas_err 500 `cannot store the request` ) } {}
    : HttpResponse r ( response_json 202 ( __mas_mesh_status sid ( string_data attempt ) ) )
    ^ r
}

@ __mas_object HttpRequest req Params ps → HttpResponse {
    : String id ( __mas_param ps `id` )
    ? ( __mas_id_ok ( string_data id ) ) {} { ^ ( __mas_err 400 `bad job id` ) }
    // ?attempt=: only that request's object, never a later one's
    ?? ( query_value ( slice_of_str ( string_data . req query ) ) `attempt` ) {
        T v → {
            : String want ( string_new )
            : ~ i k 0
            ~ & < k ( slice_len [u] v ) < k 32 { ( string_push_char want ( slice_byte v k ) ) = k + k 1 }
            : String oat ( __mas_read_job ( string_data id ) `object_attempt` )
            ? ( __mas_eq ( string_data oat ) ( string_data want ) ) {} { ^ ( __mas_err 410 `this object was replaced by a later one` ) }
        }
        F → {}
    }
    : String op ( __mas_jfile ( string_data id ) `object.glb` )
    ?? ( read_file_bytes ( string_data op ) ) {
        F _e → { ^ ( __mas_err 404 `no object for this job (yet)` ) }
        T blob → {
            : String nm ( __mas_read_job ( string_data id ) `name` )
            : ~ String base ( __mas_safe_name ( string_data nm ) )
            ? == ( string_len base ) 0 { = base ( string_from ( string_data id ) ) } {}
            : String file ( string_from ( string_data base ) )
            ( string_push_str file `.glb` )
            : String disp ( string_from `attachment; filename="` )
            ( string_push_str disp ( string_data file ) )
            ( string_push_char disp 34 )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `model/gltf-binary` )
            ( response_set_header r `Content-Disposition` ( string_data disp ) )
            ( response_set_header r `X-Cloud-Name` ( string_data file ) )
            ( response_set_header r `Cache-Control` `no-store` )
            ( response_set_body_bytes r blob )
            ^ r
        }
    }
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
    ( nurl_print `  --tls-cert F    serve HTTPS with this certificate chain (PEM)...\n` )
    ( nurl_print `  --tls-key F     ...and its key; without them, put a TLS proxy in front\n` )
    ( nurl_print `                  of any address but loopback (Basic sign-in is plain text)\n` )
}

// `map-anything serve ...` — argv[1] is "serve". Returns the exit code.
@ mas_main → i {
    : ~ s host `127.0.0.1`
    : ~ i port 8807
    : ~ String data ( string_new )
    : ~ String pass ( string_new )
    : ~ String tcert ( string_new )
    : ~ String tkey ( string_new )
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
                        ? & ( __mas_eq a `--tls-cert` ) has { = tcert ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                            ? & ( __mas_eq a `--tls-key` ) has { = tkey ( string_from ( nurl_argv + k 1 ) ) = k + k 1 } {
                                ? | ( __mas_eq a `--help` ) ( __mas_eq a `-h` ) { ( __mas_usage ) ^ 0 } {}
                                ( nurl_print `map-anything serve: unknown option ` )
                                ( nurl_print a ) ( nurl_print `\n\n` )
                                ( __mas_usage )
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
    : b noauth == ( string_len pass ) 0
    : b hc > ( string_len tcert ) 0
    : b hk > ( string_len tkey ) 0
    : b usetls & hc hk
    ? == hc hk {} {
        ( nurl_eprintln `map-anything serve: --tls-cert and --tls-key go together` )
        ^ 1
    }
    ( locked_set [MaCfg] g_mas_cfg @ MaCfg { ( string_from ( string_data data ) ) ( string_from ( string_data bin ) ) pass } )
    // held, through this binding, until mas_main returns
    : ?PFile owner ( __mas_own_data ( string_data data ) )
    ?? owner {
        T _pf → {}
        F → {
            ( nurl_eprint `map-anything serve: another server already owns ` )
            ( nurl_eprintln ( string_data data ) )
            ^ 1
        }
    }
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
    // Bodies are buffered before the sign-in can look at them, so the cap
    // bounds what an unauthenticated request can make the server hold.
    // The page sends files in 32 MiB pieces; 40 MiB leaves room.
    ( http_app_body_max a 41943040 )
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
    ( http_app_get a `/jobs/:id/object.glb` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_object rq ps ) } )
    ( http_app_get a `/api/jobs/:id/mesh` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_mesh_get rq ps ) } )
    ( http_app_post a `/api/jobs/:id/mesh` \ HttpRequest rq Params ps → HttpResponse { ^ ( __mas_mesh_post rq ps ) } )
    ? noauth {} {
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

    ( nurl_eprint ? usetls `map-anything serve: https://` `map-anything serve: http://` )
    ( nurl_eprint host ) ( nurl_eprint `:` ) ( nurl_eprint ( nurl_str_int port ) )
    ( nurl_eprint `  data ` ) ( nurl_eprint ( string_data data ) )
    ( nurl_eprintln ? noauth `  (NO PASSWORD — keep it on a private network)` `  (password required)` )
    : b loopback | ( __mas_eq host `127.0.0.1` ) ( __mas_eq host `localhost` )
    ? & & ! noauth ! usetls ! loopback {
        ( nurl_eprintln `map-anything serve: the Basic sign-in crosses the network in plain text here — front this port with a TLS proxy (an ingress) or pass --tls-cert/--tls-key` )
    } {}
    : i rc ? usetls ( http_app_listen_tls a host port ( string_data tcert ) ( string_data tkey ) ) ( http_app_listen a host port )

    // SIGTERM ended the listener: end the reconstruction in flight and
    // queue its job again, so the next start resumes it
    // the stop flag under the job lock: a spawn either happened before
    // (and its child is found below) or does not happen at all
    : i t0 ( __mas_lock )
    ( locked_set [i] g_mas_stop 1 )
    ( __mas_unlock t0 )
    : ( Vec String ) ids ( __mas_job_ids )
    : ~ i j 0
    ~ < j ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids j ) {
            T id → {
                ( __mas_stop_one ( string_data id ) `state` )
                ( __mas_stop_one ( string_data id ) `mesh_state` )
            }
            F → {}
        }
        = j + j 1
    }
    ^ ? == rc 0 0 1
}
