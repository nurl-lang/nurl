// packages/f5tts/src/serve.nu — the synthesis service.
//
// Shaped like the deployed FastAPI one: POST /tts and POST /dialogue take the
// same fields and answer with a wav, GET /voices lists what can speak, GET
// /health says whether the weights are on the card.
//
// One thread owns the GPU. Connections are fibers — cheap, and they spend
// their time on sockets and JSON — but the forward is handed to ONE dedicated
// model thread over a queue, one job per request. Three reasons, and the
// third is the one that bites:
//
//   * a CUDA context belongs to a thread, and every call has to be made from
//     the same one;
//   * the device has one copy of the activations, so two forwards at once
//     would be two forwards through the same scratch;
//   * a fiber's stack is small, and NVRTC's compiler is not.
//
// So a dialogue of eight lines is eight jobs, each answered in turn, and a
// second client's request queues behind the first rather than corrupting it.
//
// --unload-after N gives the card back. The model thread is the only one that
// touches the device, so it is the one that lets go: a wake with nothing
// queued and the idle clock past the limit unloads, and the next job reloads
// before it runs. The wakes come from a ticker thread, because a thread
// asleep on a condition variable has no way to notice time passing.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/cell.nu`
$ `deps/http/src/http.nu`
$ `deps/audio/src/wav.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `model.nu`
$ `sample.nu`
$ `vocos.nu`
$ `run.nu`
$ `text.nu`

: ~ i g_f5_model 0  // *F5Model, owned by the model thread

: ~ i g_f5_voc 0  // *Vocos

: ~ i g_f5_vocab 0  // *F5Vocab

: ~ s g_f5_voices ``  // the voices directory

: ~ s g_f5_token ``

: ~ i g_f5_reqs 0

: ~ i g_f5_unload_ms 0

: ~ i g_f5_idle_since 0

: ~ i g_f5_loads 1

: ~ i g_f5_unloads 0

: ~ i g_f5_load_ms 0

// ── the queue ───────────────────────────────────────────────────────

: F5Job {
    i next
    String voice
    String text
    i steps
    f cfg
    f sway
    f speed
    f fade
    i seed
    ( Vec f ) out
    b done
    b ok
    String err
}

: ~ i g_q_head 0

: ~ i g_q_tail 0

: ~ b g_q_stop F

: ~ i g_q_m_ptr 0

: ~ i g_q_m_bytes 0

: ~ i g_q_req_ptr 0

: ~ i g_q_req_bytes 0

: ~ i g_q_done_ptr 0

: ~ i g_q_done_bytes 0

@ __f5s_qm → Mutex { ^ @ Mutex { @ Cell { # s g_q_m_ptr g_q_m_bytes } } }

@ __f5s_qreq → Cond { ^ @ Cond { @ Cell { # s g_q_req_ptr g_q_req_bytes } } }

@ __f5s_qdone → Cond { ^ @ Cond { @ Cell { # s g_q_done_ptr g_q_done_bytes } } }

// ── the voice cache ─────────────────────────────────────────────────
//
// A voice costs a wav read, a resample and a mel — a tenth of a second, once.
// It is host data and survives an unload, so it is cached for the process's
// life. The model thread is the only reader and the only writer.

: ~ i g_vc_ids 0  // ( Vec String ) as a raw handle

: ~ i g_vc_ptrs 0  // ( Vec i ) of *F5Voice

@ __f5s_vc_ids → ( Vec String ) { ^ # ( Vec String ) g_vc_ids }

@ __f5s_vc_ptrs → ( Vec i ) { ^ # ( Vec i ) g_vc_ptrs }

@ __f5s_voice_get s id → i {
    : ( Vec String ) ids ( __f5s_vc_ids )
    : i n ( vec_len [String] ids )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ids k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) id ) {
                    ?? ( vec_get [i] ( __f5s_vc_ptrs ) k ) { T p → { ^ p } F → { ^ 0 } }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    // not cached: load it
    : String dir ( string_from g_f5_voices )
    ( string_push_char dir 47 )
    ( string_push_str dir id )
    ?? ( f5_voice_open_dir ( string_data dir ) ) {
        T v → {
            ( string_free dir )
            ( vec_push [String] ids ( string_from id ) )
            ( vec_push [i] ( __f5s_vc_ptrs ) # i v )
            ^ # i v
        }
        F e → {
            ( string_free dir )
            ( string_free e )
            ^ 0
        }
    }
}

// A voice id has to be a plain name: no separator, no dots. The directory is
// joined onto a path the server owns, and a request does not get to walk out
// of it.
@ f5_voice_id_ok s id → b {
    : i n ( nurl_str_len id )
    ? & > n 0 <= n 128 {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get id k )
        ? | == c 47 == c 92 { ^ F } {}
        ? == c 46 { ^ F } {}
        ? < c 33 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── the model thread ────────────────────────────────────────────────

@ __f5s_submit * F5Job j → b {
    ? != g_q_m_ptr 0 {} { ^ F }
    ( mutex_lock ( __f5s_qm ) )
    ? == g_q_tail 0 {
        = g_q_head # i j
        = g_q_tail # i j
    } {
        : *F5Job t # *F5Job g_q_tail
        = . t next # i j
        = g_q_tail # i j
    }
    ( cond_signal ( __f5s_qreq ) )
    ~ ! . j done { ( cond_wait ( __f5s_qdone ) ( __f5s_qm ) ) }
    ( mutex_unlock ( __f5s_qm ) )
    ^ . j ok
}

@ __f5s_reload → b {
    : *F5Model m # *F5Model g_f5_model
    : *Vocos vc # *Vocos g_f5_voc
    ? ( f5_loaded m ) { ^ T } {}
    : i t0 ( monotonic_ns )
    : b ok & ( f5_reload m ) ( voc_reload vc )
    ? ok {
        = g_f5_loads + g_f5_loads 1
        = g_f5_load_ms / - ( monotonic_ns ) t0 1000000
        : String s ( string_from `f5tts: weights loaded in ` )
        ( string_push_int s g_f5_load_ms )
        ( string_push_str s ` ms` )
        ( nurl_eprintln ( string_data s ) )
        ( string_free s )
    } {}
    ^ ok
}

@ __f5s_run_job * F5Job j → v {
    : *F5Model m # *F5Model g_f5_model
    : *Vocos vc # *Vocos g_f5_voc
    : *F5Vocab vb # *F5Vocab g_f5_vocab
    ? ( __f5s_reload ) {} {
        = . j err ( string_from `the weights could not be loaded` )
        = . j ok F
        ^ v
    }
    : i vp ( __f5s_voice_get ( string_data . j voice ) )
    ? != vp 0 {} {
        = . j err ( string_from `no such voice` )
        = . j ok F
        ^ v
    }
    : *F5Voice v # *F5Voice vp
    : b r ( f5_synth m vc v vb ( string_data . j text ) . j steps . j cfg . j sway
    . j speed . j fade . j seed . j out )
    ? r {} { = . j err ( string_from `synthesis failed` ) }
    = . j ok r
}

@ __f5s_model_loop → v {
    // A CUDA context belongs to the thread that made it current, and this is
    // not that thread: the kit was opened while the process was still one
    // thread. Without this every launch from here fails, quietly, and a
    // request comes back as "synthesis failed" with nothing in the log.
    ? ( gk_bind_thread ( f5_kit # *F5Model g_f5_model ) ) {} {
        ( nurl_eprintln `f5tts: the model thread cannot bind the device context` )
        ^
    }
    : ~ b run T
    ~ run {
        ( mutex_lock ( __f5s_qm ) )
        ~ & == g_q_head 0 ! g_q_stop {
            ( cond_wait ( __f5s_qreq ) ( __f5s_qm ) )
            // a ticker wake with nothing queued: is it time to let go?
            ? & & == g_q_head 0 > g_f5_unload_ms 0 ( f5_loaded # *F5Model g_f5_model ) {
                ? >= ( elapsed_ms_since g_f5_idle_since ) g_f5_unload_ms {
                    ( f5_unload # *F5Model g_f5_model )
                    ( voc_unload # *Vocos g_f5_voc )
                    = g_f5_unloads + g_f5_unloads 1
                    : String s ( string_from `f5tts: idle for ` )
                    ( string_push_int s / g_f5_unload_ms 1000 )
                    ( string_push_str s ` s — weights unloaded (device memory released; the next request reloads them)` )
                    ( nurl_eprintln ( string_data s ) )
                    ( string_free s )
                } {}
            } {}
        }
        ? == g_q_head 0 {
            ( mutex_unlock ( __f5s_qm ) )
            = run F
        } {
            : *F5Job j # *F5Job g_q_head
            = g_q_head . j next
            ? == g_q_head 0 { = g_q_tail 0 } {}
            ( mutex_unlock ( __f5s_qm ) )
            ( __f5s_run_job j )
            ( mutex_lock ( __f5s_qm ) )
            = g_f5_idle_since ( monotonic_ns )
            = . j done T
            ( cond_broadcast ( __f5s_qdone ) )
            ( mutex_unlock ( __f5s_qm ) )
        }
    }
}

@ __f5s_ticker → v {
    ~ T {
        ( sleep_ms 200 )
        ( mutex_lock ( __f5s_qm ) )
        ( cond_broadcast ( __f5s_qreq ) )
        ( mutex_unlock ( __f5s_qm ) )
    }
}

// ── HTTP ────────────────────────────────────────────────────────────

@ __f5s_jerr i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( json_free o )
    ^ r
}

// Every byte of the CONFIGURED token is looked at, and a length mismatch
// folds into the same accumulator, so the comparison does not leak the
// token's length through its timing.
@ __f5s_authed HttpRequest req → b {
    : i want ( nurl_str_len g_f5_token )
    ? == want 0 { ^ T } {}
    : ~ s got ``
    ?? ( header_get . req headers `authorization` ) { T h → { = got ( string_data h ) } F → {} }
    : i n ( nurl_str_len got )
    ? > n 7 {} { ^ F }
    ? ( nurl_str_starts got `Bearer ` ) {} { ^ F }
    : i have - n 7
    : ~ i diff ^^ have want
    : ~ i k 0
    ~ < k want {
        : i a ? < k have ( nurl_str_get got + 7 k ) 0
        = diff | diff ^^ a ( nurl_str_get g_f5_token k )
        = k + k 1
    }
    ^ == diff 0
}

@ __f5s_jnum Json root s key f dflt → f {
    ?? ( json_obj_get root key ) {
        T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F → { ^ dflt } } }
        F → { ^ dflt }
    }
}

@ __f5s_jint Json root s key i dflt → i {
    ?? ( json_obj_get root key ) {
        T v → { ?? ( json_num_as_i v ) { T x → { ^ x } F → { ^ dflt } } }
        F → { ^ dflt }
    }
}

@ __f5s_jstr Json root s key → String {
    ?? ( json_obj_get root key ) {
        T v → { ^ ( string_from ( json_as_str v ) ) }
        F → { ^ ( string_new ) }
    }
}

// One line of a dialogue, synthesised and appended to `out`.
@ __f5s_one s voice s text i steps f cfg f sway f speed f fade i seed
( Vec f ) out String err → b {
    ? ( f5_voice_id_ok voice ) {} {
        ( string_push_str err `voice id must be a plain directory name` )
        ^ F
    }
    : *F5Job j # *F5Job ( nurl_alloc Z F5Job )
    = . j next 0
    = . j voice ( string_from voice )
    = . j text ( string_from text )
    = . j steps steps
    = . j cfg cfg
    = . j sway sway
    = . j speed speed
    = . j fade fade
    = . j seed seed
    = . j out ( vec_new [f] )
    = . j done F
    = . j ok F
    = . j err ( string_new )
    : b r ( __f5s_submit j )
    ? r {
        : i n ( vec_len [f] . j out )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [f] . j out k ) { T x → { ( vec_push [f] out x ) } F → {} }
            = k + k 1
        }
    } { ( string_push_str err ( string_data . j err ) ) }
    ( vec_free [f] . j out )
    ( string_free . j voice )
    ( string_free . j text )
    ( string_free . j err )
    ( nurl_free # *u j )
    ^ r
}

@ __f5s_wav_response ( Vec f ) wave → HttpResponse {
    : ( Vec u ) bytes ( wav_encode wave 24000 1 )
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `content-type` `audio/wav` )
    ( response_set_body_bytes r bytes )
    ( vec_free [u] bytes )
    ^ r
}

// POST /dialogue — {"inputs":[{"voice_id":…,"text":…}, …], …}
// POST /tts      — {"voice_id":…,"text":…, …}, which is the same thing with
//                  one input, exactly as the reference service builds it.
@ __f5s_post_json HttpRequest req b single → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    : String bodys ( string_new )
    ( string_push_bytes bodys ( vec_data [u] . req body ) ( vec_len [u] . req body ) )
    ?? ( json_parse ( string_data bodys ) ) {
        T root → {
            ( string_free bodys )
            : i steps ( __f5s_jint root `nfe_steps` 32 )
            : f cfg ( __f5s_jnum root `cfg_strength` 2.0 )
            : f sway ( __f5s_jnum root `sway_sampling_coef` -1.0 )
            : f speed ( __f5s_jnum root `speed` 1.0 )
            : f fade ( __f5s_jnum root `cross_fade_duration` 0.15 )
            : ~ i seed ( __f5s_jint root `seed` -1 )
            ? < seed 0 { = seed & ( monotonic_ns ) 2147483647 } {}
            : ( Vec f ) wave ( vec_new [f] )
            : String err ( string_new )
            : ~ b ok T
            : ~ i count 0
            ? single {
                : String vid ( __f5s_jstr root `voice_id` )
                : String txt ( __f5s_jstr root `text` )
                = ok ( __f5s_one ( string_data vid ) ( string_data txt ) steps cfg sway
                speed fade seed wave err )
                = count 1
                ( string_free vid )
                ( string_free txt )
            } {
                ?? ( json_obj_get root `inputs` ) {
                    T arr → {
                        : i n ( json_arr_len arr )
                        : ~ i k 0
                        ~ & < k n ok {
                            ?? ( json_arr_get arr k ) {
                                T it → {
                                    : String vid ( __f5s_jstr it `voice_id` )
                                    : String txt ( __f5s_jstr it `text` )
                                    = ok ( __f5s_one ( string_data vid ) ( string_data txt ) steps cfg
                                    sway speed ? == k 0 fade 0.0 + seed k wave err )
                                    = count + count 1
                                    ( string_free vid )
                                    ( string_free txt )
                                }
                                F → {}
                            }
                            = k + k 1
                        }
                    }
                    F → {
                        = ok F
                        ( string_push_str err `body needs an "inputs" array` )
                    }
                }
            }
            ( json_free root )
            = g_f5_reqs + g_f5_reqs 1
            ? & ok > ( vec_len [f] wave ) 0 {
                : HttpResponse r ( __f5s_wav_response wave )
                ( vec_free [f] wave )
                ( string_free err )
                ^ r
            } {}
            : String msg ? > ( string_len err ) 0 ( string_clone err ) ( string_from `nothing to say` )
            : HttpResponse r ( __f5s_jerr 400 ( string_data msg ) )
            ( string_free msg )
            ( string_free err )
            ( vec_free [f] wave )
            ^ r
        }
        F _je → {
            ( string_free bodys )
            ^ ( __f5s_jerr 400 `request body is not valid JSON` )
        }
    }
}

@ __f5s_voices HttpRequest req → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : Json arr ( json_arr_new )
    ?? ( dir_list g_f5_voices ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String cfg ( string_from g_f5_voices )
                        ( string_push_char cfg 47 )
                        ( string_push_str cfg ( string_data nm ) )
                        ( string_push_str cfg `/config.json` )
                        ? ( file_exists ( string_data cfg ) ) {
                            : Json o ( json_obj_new )
                            : b _a ( json_obj_set o `voice_id` ( json_str_lit ( string_data nm ) ) )
                            : b _b ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
                            : b _c ( json_arr_push arr o )
                        } {}
                        ( string_free cfg )
                    }
                    F → {}
                }
                = k + k 1
            }
            : ( @ v String ) drop_s \ String s → v { ( string_free s ) }
            ( vec_free_with [String] names drop_s )
        }
        F _e → {}
    }
    : HttpResponse r ( response_json 200 arr )
    ( json_free arr )
    ^ r
}

@ __f5s_health HttpRequest req → HttpResponse {
    : Json o ( json_obj_new )
    : b loaded ( f5_loaded # *F5Model g_f5_model )
    : b _a ( json_obj_set o `status` ( json_str_lit ? loaded `ok` `idle` ) )
    : b _b ( json_obj_set o `loaded` ( json_bool loaded ) )
    : b _c ( json_obj_set o `requests` ( json_int g_f5_reqs ) )
    : b _d ( json_obj_set o `unload_after_s` ( json_int / g_f5_unload_ms 1000 ) )
    : b _e ( json_obj_set o `loads` ( json_int g_f5_loads ) )
    : b _f ( json_obj_set o `unloads` ( json_int g_f5_unloads ) )
    : b _g ( json_obj_set o `last_load_ms` ( json_int g_f5_load_ms ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// ── the server ──────────────────────────────────────────────────────

@ f5_serve s ckpt s vocab_path s vocoder s voices_dir s host i port s token
i device i unload_s → i {
    ?? ( f5_vocab_load vocab_path ) {
        T vb → { = g_f5_vocab # i vb }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
    ?? ( f5_open ckpt vocab_path device ) {
        T m → { = g_f5_model # i m }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
    ?? ( voc_open vocoder ( f5_kit # *F5Model g_f5_model ) ) {
        T vc → { = g_f5_voc # i vc }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
    = g_f5_voices voices_dir
    = g_f5_token token
    = g_f5_unload_ms * unload_s 1000
    = g_f5_idle_since ( monotonic_ns )
    = g_vc_ids # i ( vec_new [String] )
    = g_vc_ptrs # i ( vec_new [i] )

    : Mutex qm ( mutex_new )
    : Cond qreq ( cond_new )
    : Cond qdone ( cond_new )
    : Cell qmc . qm c
    = g_q_m_ptr # i . qmc ptr
    = g_q_m_bytes . qmc bytes
    : Cell qrc . qreq c
    = g_q_req_ptr # i . qrc ptr
    = g_q_req_bytes . qrc bytes
    : Cell qdc . qdone c
    = g_q_done_ptr # i . qdc ptr
    = g_q_done_bytes . qdc bytes
    : ( @ v ) modelfn \ → v { ( __f5s_model_loop ) }
    ?? ( thread_spawn modelfn ) {
        T th → { ( thread_detach th ) }
        F _te → {
            ( nurl_eprintln `f5tts: cannot start the model thread` )
            ^ 1
        }
    }
    ? > unload_s 0 {
        : ( @ v ) tickfn \ → v { ( __f5s_ticker ) }
        ?? ( thread_spawn_owned tickfn ) {
            T th → { ( thread_detach th ) }
            F _te → {
                ( nurl_eprintln `f5tts: cannot start the unload timer — the weights stay loaded` )
                = g_f5_unload_ms 0
            }
        }
    } {}

    : *HttpApp a ( http_app_new )
    ( http_app_async a 0 )
    ( http_app_body_max a 4194304 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 30000 )
    ( http_app_request_timeout a 600000 )
    ( http_app_post a `/tts` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_post_json rq T ) } )
    ( http_app_post a `/dialogue` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_post_json rq F ) } )
    ( http_app_get a `/voices` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_voices rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_health rq ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_health rq ) } )

    : String msg ( string_from `f5tts serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( string_push_str msg ` (POST /tts, POST /dialogue, GET /voices, GET /health)` )
    ? == ( nurl_str_len token ) 0 { ( string_push_str msg ` — NO TOKEN, keep it on loopback` ) } {}
    ? > unload_s 0 {
        ( string_push_str msg `\nf5tts: the weights are released after ` )
        ( string_push_int msg unload_s )
        ( string_push_str msg ` s idle and reloaded on the next request` )
    } {}
    ( nurl_eprintln ( string_data msg ) )
    ( string_free msg )

    : i rc ( http_app_listen a host port )
    ( mutex_lock qm )
    = g_q_stop T
    ( cond_broadcast qreq )
    ( mutex_unlock qm )
    ^ rc
}
