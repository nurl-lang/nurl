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
// blocked on its queue has no way to notice time passing.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mp3.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `model.nu`
$ `vocos.nu`
$ `stdlib/std/arc.nu`
$ `run.nu`
$ `text.nu`
$ `store.nu`
$ `registry.nu`
$ `ui.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/bytes.nu`

// ── the server's state ──────────────────────────────────────────────
//
// What the handlers read — the configuration fixed at start and the
// counters the model thread keeps — are Locked globals set at start. What
// only the model thread touches (the engine, the vocoder, the vocabulary,
// the voice cache) is that thread's own value (F5Run), handed to it when it
// starts: nothing else can reach it, so nothing else can race it.
: F5Cfg {
    String voices  // the voices directory
    String token
    String vocoder
    String models_dir
    i unload_ms  // 0 = the weights stay for the process's life
}

: F5Stat {
    String cur_id  // the model the thread currently holds
    b loaded  // the weights are on the device
    i reqs
    i switches
    i loads  // 1 is the load before the port opened
    i unloads
    i load_ms  // the last load's wall time
}

@ __f5s_cfg_blank → ( Locked F5Cfg ) {
    ^ ( locked_new [F5Cfg] @ F5Cfg { ( string_new ) ( string_new ) ( string_new ) ( string_new ) 0 } )
}

@ __f5s_stat_blank → ( Locked F5Stat ) {
    ^ ( locked_new [F5Stat] @ F5Stat { ( string_new ) F 0 0 1 0 0 } )
}

: ( Locked F5Cfg ) g_f5_cfg ( __f5s_cfg_blank )

: ( Locked F5Stat ) g_f5_stat ( __f5s_stat_blank )

// A copy of the configuration (strings a handler reads once per request).
@ __f5s_cfg → F5Cfg { ^ ( locked_get [F5Cfg] g_f5_cfg ) }

@ __f5s_count_req → v {
    : ~ F5Stat st ( locked_take [F5Stat] g_f5_stat )
    = . st reqs + . st reqs 1
    ( locked_restore [F5Stat] g_f5_stat st )
}

@ __f5s_set_loaded b loaded → v {
    : ~ F5Stat st ( locked_take [F5Stat] g_f5_stat )
    = . st loaded loaded
    ( locked_restore [F5Stat] g_f5_stat st )
}

// ── the voice cache ─────────────────────────────────────────────────
//
// A voice costs a wav read, a resample and a mel — a tenth of a second, once.
// It is host data and survives an unload, so it is cached for the process's
// life, by the model thread, the only one that reads or writes it.
: F5VoiceCache {
    ( Vec String ) ids
    ( Vec ? F5Voice ) ptrs
    ( Vec f ) rms  // the loudness each was prepared at
}

@ __f5s_vc_new → F5VoiceCache { ^ @ F5VoiceCache { ( vec_new [String] ) ( vec_new [? F5Voice] ) ( vec_new [f] ) } }

// The model thread's own state.
: F5Run {
    F5Model model
    Vocos voc
    F5Vocab vocab
    F5VoiceCache vc
    String cur_id
    i unload_ms
    i idle_since  // monotonic_ns at the end of the last job
}

// A voice is cached with the loudness it was normalised TO. A request asking
// for a different target_rms gets the recording prepared again rather than
// somebody else's normalisation — the mel the model conditions on is not the
// same mel.
@ __f5s_voice_get inout F5Run r s id f target → ?F5Voice {
    : ( Vec String ) ids . . r vc ids
    : i n ( vec_len [String] ids )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ids k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) id ) {
                    : ~ f had -1.0
                    ?? ( vec_get [f] . . r vc rms k ) { T x → { = had x } F → {} }
                    ? < ( fabs - had target ) 1.0e-9 {
                        ?? ( vec_get [? F5Voice] . . r vc ptrs k ) {
                            T p → {
                                ?? p {
                                    T x → { ^ @ ?F5Voice { T ( F5Voice_share x ) } }
                                    F → { ^ @ ?F5Voice { F } }
                                }
                            }
                            F → { ^ @ ?F5Voice { F } }
                        }
                    } {
                        // prepared at a different loudness: drop it and rebuild
                        ( vec_set [? F5Voice] . . r vc ptrs k @ ?F5Voice { F } )
                        ( vec_set [f] . . r vc rms k -1.0 )
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    // not cached: load it
    : F5Cfg c ( __f5s_cfg )
    : String dir ( string_from ( string_data . c voices ) )
    ( string_push_char dir 47 )
    ( string_push_str dir id )
    ?? ( f5_voice_open_dir ( string_data dir ) target ) {
        T v → {
            ( vec_push [String] ids ( string_from id ) )
            ( vec_push [? F5Voice] . . r vc ptrs @ ?F5Voice { T ( F5Voice_share v ) } )
            ( vec_push [f] . . r vc rms target )
            ^ @ ?F5Voice { T v }
        }
        F e → {
            ^ @ ?F5Voice { F }
        }
    }
}

// Drop a voice from the cache: a re-recorded voice with the same id must not
// keep answering from the mel of the take it replaced.
@ __f5s_voice_forget inout F5Run r s id → v {
    : ( Vec String ) ids . . r vc ids
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) id ) {
                    ( vec_set [? F5Voice] . . r vc ptrs k @ ?F5Voice { F } )
                    ( vec_set [f] . . r vc rms k -1.0 )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
}

// A voice id has to be a plain name: no separator, no dots. The directory is
// joined onto a path the server owns, and a request does not get to walk out
// of it.
@ f5_voice_id_ok s id → b {
    : ( Slice u ) id_v ( slice_of_str id )
    : i n ( nurl_str_len id )
    ? & > n 0 <= n 128 {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte id_v k )
        ? | == c 47 == c 92 { ^ F } {}
        ? == c 46 { ^ F } {}
        ? < c 33 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── switching models ────────────────────────────────────────────────
//
// One model is held at a time. A request naming a different one closes the
// current model and its vocabulary and opens the other, which costs a load
// (a second or so from the page cache) and is reported. Holding several at
// once would be faster to switch between and would also mean several
// gigabytes of a card standing idle, which is the opposite of what
// --unload-after is for.
@ __f5s_cur_id → String { ^ . ( locked_get [F5Stat] g_f5_stat ) cur_id }

@ __f5s_switch_to inout F5Run r s id → b {
    ? == 0 ( nurl_str_len id ) { ^ T } {}
    ? != 0 ( nurl_str_eq ( string_data . r cur_id ) id ) { ^ T } {}
    : F5Cfg c ( __f5s_cfg )
    : String ck ( string_new )
    : String vo ( string_new )
    ? ( f5_registry_resolve ( string_data . c models_dir ) id ck vo ) {} {
        ^ F
    }
    : i t0 ( monotonic_ns )
    : ~ b ok F
    ?? ( f5_vocab_load ( string_data vo ) ) {
        T nv → {
            ?? ( f5_open ( string_data ck ) ( string_data vo ) -1 ) {
                T nm → {
                    // the vocoder runs on the model's kit, so it is reopened
                    // against the new one (the old vocoder keeps the old kit
                    // alive until it is replaced)
                    : GpuKit nkit ( f5_kit nm )
                    = . r model nm
                    = . r vocab nv
                    ?? ( voc_open ( string_data . c vocoder ) nkit ) {
                        T nvoc → {
                            = . r voc nvoc
                            = ok T
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) )
                        }
                    }
                    ? ok {
                        = . r cur_id ( string_from id )
                        : ~ F5Stat st ( locked_take [F5Stat] g_f5_stat )
                        = . st cur_id ( string_from id )
                        = . st switches + . st switches 1
                        ( locked_restore [F5Stat] g_f5_stat st )
                        : String msg ( string_from `f5tts: switched to model ` )
                        ( string_push_str msg id )
                        ( string_push_str msg ` in ` )
                        ( string_push_int msg / - ( monotonic_ns ) t0 1000000 )
                        ( string_push_str msg ` ms` )
                        ( nurl_eprintln ( string_data msg ) )
                    } {}
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
        }
    }
    ^ ok
}

// ── the model thread ────────────────────────────────────────────────
//
// One message per waiting request on a channel the model thread drains;
// a job carries the channel its answer goes back on, and the submitting
// fiber waits on that. A tick (the unload timer), a cache drop and a stop
// travel the same queue, so the model thread waits on one thing — and a
// voice re-recorded before a request is forgotten before that request
// runs.
: i F5_JOB 0
: i F5_TICK 1
: i F5_STOP 2
: i F5_FORGET 3

: F5Reply {
    b ok
    ( Vec f ) out
    ( Vec i ) score
    String err
}

: F5Msg {
    i kind
    String voice  // the voice id (F5_FORGET: the voice to drop)
    String text
    i steps
    f cfg
    f sway
    f speed
    f fade
    i seed
    i retries
    f max_wer
    i splitfail
    f target_rms
    String model_id
    ( Channel F5Reply ) reply
}

@ __f5s_queue_new → ( Channel F5Msg ) { ^ ( chan_new [F5Msg] ) }

: ( Channel F5Msg ) g_q ( __f5s_queue_new )

@ __f5s_signal i kind s voice → v {
    : b _s ( chan_send [F5Msg] g_q @ F5Msg { kind ( string_from voice ) ( string_new ) 0 0.0 0.0 0.0 0.0 0 0 0.0 0 0.0
        ( string_new ) ( chan_new [F5Reply] ) } )
}

@ __f5s_fail s msg → F5Reply { ^ @ F5Reply { F ( vec_new [f] ) ( f5_score_new ) ( string_from msg ) } }

@ __f5s_reload inout F5Run r → b {
    ? ( f5_loaded . r model ) { ^ T } {}
    : i t0 ( monotonic_ns )
    : b ok & ( f5_reload . r model ) ( voc_reload . r voc )
    ? ok {
        : i ms / - ( monotonic_ns ) t0 1000000
        : ~ F5Stat st ( locked_take [F5Stat] g_f5_stat )
        = . st loads + . st loads 1
        = . st load_ms ms
        = . st loaded T
        ( locked_restore [F5Stat] g_f5_stat st )
        : String s ( string_from `f5tts: weights loaded in ` )
        ( string_push_int s ms )
        ( string_push_str s ` ms` )
        ( nurl_eprintln ( string_data s ) )
    } {}
    ^ ok
}

@ __f5s_run_job inout F5Run r F5Msg j → F5Reply {
    ? ( __f5s_switch_to r ( string_data . j model_id ) ) {} {
        ^ ( __f5s_fail `no such model (GET /models lists what this machine can speak with)` )
    }
    ? ( __f5s_reload r ) {} {
        ^ ( __f5s_fail `the weights could not be loaded` )
    }
    : F5Voice v ?? ( __f5s_voice_get r ( string_data . j voice ) . j target_rms ) {
        T x → x
        F → { ^ ( __f5s_fail `no such voice` ) }
    }
    : ( Vec f ) out ( vec_new [f] )
    : ( Vec i ) score ( f5_score_new )
    : b ok ( f5_synth_line . r model . r voc v . r vocab ( string_data . j text ) . j steps . j cfg . j sway
    . j speed . j fade . j seed . j retries . j max_wer . j splitfail out score )
    ? ok { ^ @ F5Reply { T out score ( string_new ) } } {}
    ^ ( __f5s_fail `synthesis failed` )
}

// A tick with the idle clock past the limit lets the weights go.
@ __f5s_idle_check inout F5Run r → v {
    ? & > . r unload_ms 0 ( f5_loaded . r model ) {
        ? >= ( elapsed_ms_since . r idle_since ) . r unload_ms {
            ( f5_unload . r model )
            ( voc_unload . r voc )
            : ~ F5Stat st ( locked_take [F5Stat] g_f5_stat )
            = . st unloads + . st unloads 1
            = . st loaded F
            ( locked_restore [F5Stat] g_f5_stat st )
            : String s ( string_from `f5tts: idle for ` )
            ( string_push_int s / . r unload_ms 1000 )
            ( string_push_str s ` s — weights unloaded (device memory released; the next request reloads them)` )
            ( nurl_eprintln ( string_data s ) )
        } {}
    } {}
}

@ __f5s_model_loop sink F5Run start → v {
    : ~ F5Run r start
    // A CUDA context belongs to the thread that made it current, and this is
    // not that thread: the kit was opened while the process was still one
    // thread. Without this every launch from here fails, quietly, and a
    // request comes back as "synthesis failed" with nothing in the log.
    ? ( gk_bind_thread ( f5_kit . r model ) ) {} {
        ( nurl_eprintln `f5tts: the model thread cannot bind the device context` )
        ^
    }
    : ~ b run T
    ~ run {
        ?? ( chan_recv [F5Msg] g_q ) {
            T j → {
                ? == . j kind F5_STOP { = run F } {}
                ? == . j kind F5_TICK { ( __f5s_idle_check r ) } {}
                ? == . j kind F5_FORGET { ( __f5s_voice_forget r ( string_data . j voice ) ) } {}
                ? == . j kind F5_JOB {
                    : F5Reply rep ( __f5s_run_job r j )
                    = . r idle_since ( monotonic_ns )
                    : b _s ( chan_send [F5Reply] . j reply rep )
                } {}
            }
            F → { = run F }
        }
    }
}

@ __f5s_ticker → v {
    ~ T {
        ( sleep_ms 200 )
        ( __f5s_signal F5_TICK `` )
    }
}

// ── HTTP ────────────────────────────────────────────────────────────

@ __f5s_jerr i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

// Every byte of the CONFIGURED token is looked at, and a length mismatch
// folds into the same accumulator, so the comparison does not leak the
// token's length through its timing.
@ __f5s_authed HttpRequest req → b {
    : F5Cfg c ( __f5s_cfg )
    : s token ( string_data . c token )
    : i want ( nurl_str_len token )
    ? == want 0 { ^ T } {}
    : ~ s got ``
    ?? ( header_get . req headers `authorization` ) { T h → { = got ( string_data h ) } F → {} }
    : i n ( nurl_str_len got )
    ? > n 7 {} { ^ F }
    ? ( nurl_str_starts got `Bearer ` ) {} { ^ F }
    : i have - n 7
    : ( Slice u ) got_v ( slice_of_str got )
    : ( Slice u ) tok_v ( slice_of_str token )
    : ~ i diff ^^ have want
    : ~ i k 0
    ~ < k want {
        : i a ? < k have ( slice_byte got_v + 7 k ) 0
        = diff | diff ^^ a ( slice_byte tok_v k )
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
i retries f max_wer i splitfail f target_rms s model_id ( Vec f ) out ( Vec i ) score String err → b {
    ? ( f5_voice_id_ok voice ) {} {
        ( string_push_str err `voice id must be a plain directory name` )
        ^ F
    }
    : ( Channel F5Reply ) reply ( chan_new [F5Reply] )
    : b sent ( chan_send [F5Msg] g_q @ F5Msg { F5_JOB ( string_from voice ) ( string_from text ) steps cfg sway speed fade seed
        retries max_wer splitfail target_rms ( string_from model_id ) ( Channel_share [F5Reply] reply ) } )
    ? sent {} {
        ( string_push_str err `the model thread is not running` )
        ^ F
    }
    ?? ( chan_recv [F5Reply] reply ) {
        T rep → {
            ? . rep ok {
                ( vec_extend [f] out . rep out )
                ( f5_score_merge score . rep score )
                ^ T
            } {}
            ( string_push_str err ( string_data . rep err ) )
            ^ F
        }
        F → {
            ( string_push_str err `the model thread stopped` )
            ^ F
        }
    }
}

// `wav` (the default), `mp3`, or `pcm` — raw signed 16-bit little-endian
// mono at 24 kHz, which is the wav without its header. The mp3 is MPEG-2
// Layer III at 24 kHz, encoded here rather than by a subprocess. `ogg` is the
// reference service's fourth and there is no Vorbis encoder in this ecosystem
// yet, so it is refused by name instead of answered with something else.
@ __f5s_audio_response ( Vec f ) wave s fmt i kbps → HttpResponse {
    ( f5_limit_peak wave )
    ? ( nurl_str_eq fmt `ogg` ) {
        ^ ( __f5s_jerr 400 `ogg is not encoded here; ask for wav, mp3 or pcm` )
    } {}
    ? ( nurl_str_eq fmt `mp3` ) {
        ?? ( mp3_encode wave 24000 1 kbps ) {
            T mp3 → {
                : HttpResponse r ( response_new 200 )
                ( response_set_header r `content-type` `audio/mpeg` )
                ( response_set_body_bytes r mp3 )
                ^ r
            }
            F e → {
                : HttpResponse r ( __f5s_jerr 400 ( string_data e ) )
                ^ r
            }
        }
    } {}
    : ( Vec u ) bytes ( wav_encode wave 24000 1 )
    : HttpResponse r ( response_new 200 )
    ? ( nurl_str_eq fmt `pcm` ) {
        // the same samples without the 44-byte RIFF header
        : ( Vec u ) raw ( vec_new [u] )
        : ~ i k 44
        ~ < k ( vec_len [u] bytes ) {
            ?? ( vec_get [u] bytes k ) { T b → { ( vec_push [u] raw b ) } F → {} }
            = k + k 1
        }
        ( response_set_header r `content-type` `audio/L16; rate=24000; channels=1` )
        ( response_set_body_bytes r raw )
    } {
        ( response_set_header r `content-type` `audio/wav` )
        ( response_set_body_bytes r bytes )
    }
    ^ r
}

// POST /dialogue — {"inputs":[{"voice_id":…,"text":…}, …], …}
// POST /tts      — {"voice_id":…,"text":…, …}, which is the same thing with
//                  one input, exactly as the reference service builds it.
@ __f5s_post_json HttpRequest req b single → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    : String bodys ( bytes_to_str . req body )
    ?? ( json_parse ( string_data bodys ) ) {
        T root → {
            : i steps ( __f5s_jint root `nfe_steps` 32 )
            : f cfg ( __f5s_jnum root `cfg_strength` 2.0 )
            : f sway ( __f5s_jnum root `sway_sampling_coef` -1.0 )
            : f speed ( __f5s_jnum root `speed` 1.0 )
            : f fade ( __f5s_jnum root `cross_fade_duration` 0.15 )
            : ~ i seed ( __f5s_jint root `seed` -1 )
            ? < seed 0 { = seed & ( monotonic_ns ) 2147483647 } {}
            // 128 kbit/s is what the reference service asks ffmpeg for
            : i kbps ( __f5s_jint root `mp3_bitrate` 128 )
            // The quality gate. whisper_retry is a count of RETRIES — how many
            // more times a line may be generated when the transcriber says
            // it came out wrong — so 0 generates once. max_wer is the word
            // error rate a line has to stay under; asking for either turns
            // the gate on, with the reference service's default for the
            // other (0.15), and splitfail N generates a line a sentence at a
            // time when it is still failing after N attempts. All three
            // need a transcriber (--whisper) to do anything.
            : i retries ( __f5s_jint root `whisper_retry` 0 )
            : f max_wer ( __f5s_jnum root `max_wer` ? > retries 0 0.15 1.0 )
            : i splitfail ( __f5s_jint root `splitfail` 0 )
            // the reference normalises the recording to an rms of 0.1 before
            // the mel and scales the result back; a target at or below zero
            // turns both off, which is what a negative one means there too
            : f target_rms ( __f5s_jnum root `target_rms` 0.1 )
            : String model_id ( __f5s_jstr root `model_id` )
            : String fmt ( __f5s_jstr root `output_format` )
            ? == 0 ( string_len fmt ) { ( string_push_str fmt `wav` ) } {}
            : ( Vec f ) wave ( vec_new [f] )
            : ( Vec i ) score ( f5_score_new )
            : String err ( string_new )
            : ~ b ok T
            : ~ i count 0
            ? single {
                : String vid ( __f5s_jstr root `voice_id` )
                : String txt ( __f5s_jstr root `text` )
                = ok ( __f5s_one ( string_data vid ) ( string_data txt ) steps cfg sway
                speed fade seed retries max_wer splitfail target_rms ( string_data model_id ) wave score err )
                = count 1
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
                                    // a per-input voice_settings block overrides
                                    // the request's own defaults, field by field
                                    : ~ i i_steps steps
                                    : ~ f i_cfg cfg
                                    : ~ f i_sway sway
                                    : ~ f i_speed speed
                                    : ~ f i_fade fade
                                    : ~ i i_seed + seed k
                                    : ~ i i_retries retries
                                    : ~ f i_wer max_wer
                                    : ~ i i_split splitfail
                                    : ~ f i_rms target_rms
                                    ?? ( json_obj_get it `voice_settings` ) {
                                        T vs → {
                                            = i_steps ( __f5s_jint vs `nfe_steps` i_steps )
                                            = i_cfg ( __f5s_jnum vs `cfg_strength` i_cfg )
                                            = i_sway ( __f5s_jnum vs `sway_sampling_coef` i_sway )
                                            = i_speed ( __f5s_jnum vs `speed` i_speed )
                                            = i_fade ( __f5s_jnum vs `cross_fade_duration` i_fade )
                                            = i_seed ( __f5s_jint vs `seed` i_seed )
                                            = i_retries ( __f5s_jint vs `whisper_retry` i_retries )
                                            = i_wer ( __f5s_jnum vs `max_wer` ? & > i_retries 0 >= i_wer 1.0 0.15 i_wer )
                                            = i_split ( __f5s_jint vs `splitfail` i_split )
                                            = i_rms ( __f5s_jnum vs `target_rms` i_rms )
                                        }
                                        F → {}
                                    }
                                    // a tenth of a second between speakers
                                    ? > k 0 { ( f5_append_silence wave 100 ) } {}
                                    = ok ( __f5s_one ( string_data vid ) ( string_data txt ) i_steps i_cfg
                                    i_sway i_speed i_fade i_seed i_retries i_wer i_split i_rms
                                    ( string_data model_id ) wave score err )
                                    = count + count 1
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
            ( __f5s_count_req )
            ? & ok > ( vec_len [f] wave ) 0 {
                : HttpResponse r ( __f5s_audio_response wave ( string_data fmt ) kbps )
                // what the gate heard, for a caller that wants to know
                ? | ( f5_score_checked score ) > ( f5_score_unheard score ) 0 {
                    : String he ( string_new )
                    ( string_push_int he ( f5_score_errs score ) )
                    ( response_set_header r `x-f5tts-word-errors` ( string_data he ) )
                    : String hw ( string_new )
                    ( string_push_int hw ( f5_score_words score ) )
                    ( response_set_header r `x-f5tts-words` ( string_data hw ) )
                    : String ha ( string_new )
                    ( string_push_int ha ( f5_score_attempts score ) )
                    ( response_set_header r `x-f5tts-attempts` ( string_data ha ) )
                    : String hu ( string_new )
                    ( string_push_int hu ( f5_score_unheard score ) )
                    ( response_set_header r `x-f5tts-unheard` ( string_data hu ) )
                } {}
                ^ r
            } {}
            : String msg ? > ( string_len err ) 0 ( string_clone err ) ( string_from `nothing to say` )
            : HttpResponse r ( __f5s_jerr 400 ( string_data msg ) )
            ^ r
        }
        F _je → {
            ^ ( __f5s_jerr 400 `request body is not valid JSON` )
        }
    }
}

@ __f5s_voices HttpRequest req → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : Json arr ( json_arr_new )
    : F5Cfg c ( __f5s_cfg )
    ?? ( dir_list ( string_data . c voices ) ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String cfg ( string_from ( string_data . c voices ) )
                        ( string_push_char cfg 47 )
                        ( string_push_str cfg ( string_data nm ) )
                        ( string_push_str cfg `/config.json` )
                        ? ( file_exists ( string_data cfg ) ) {
                            : Json o ( json_obj_new )
                            : b _a ( json_obj_set o `voice_id` ( json_str_lit ( string_data nm ) ) )
                            : b _b ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
                            : b _c ( json_arr_push arr o )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F _e → {}
    }
    : HttpResponse r ( response_json 200 arr )
    ^ r
}

// The page, and the only route that does not want a token: a browser cannot
// put one in a header before it has any JavaScript, and the page itself asks
// for nothing — every call it makes carries the token from ?token=.
@ __f5s_page → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `content-type` `text/html; charset=utf-8` )
    ( response_set_body_str r ( f5_ui_html ) )
    ^ r
}

@ __f5s_health HttpRequest req → HttpResponse {
    : Json o ( json_obj_new )
    : F5Stat st ( locked_get [F5Stat] g_f5_stat )
    : F5Cfg c ( __f5s_cfg )
    : b loaded . st loaded
    : b _a ( json_obj_set o `status` ( json_str_lit ? loaded `ok` `idle` ) )
    : b _b ( json_obj_set o `loaded` ( json_bool loaded ) )
    : b _c ( json_obj_set o `requests` ( json_int . st reqs ) )
    : b _d ( json_obj_set o `unload_after_s` ( json_int / . c unload_ms 1000 ) )
    : b _e ( json_obj_set o `loads` ( json_int . st loads ) )
    : b _f ( json_obj_set o `unloads` ( json_int . st unloads ) )
    : b _g ( json_obj_set o `last_load_ms` ( json_int . st load_ms ) )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// ── the server ──────────────────────────────────────────────────────

@ f5_serve s ckpt s vocab_path s vocoder s voices_dir s models_dir s model_id
s host i port s token i device i unload_s → i {
    ( f5_ensure_dirs )
    : i unload_ms * unload_s 1000
    ( locked_set [F5Cfg] g_f5_cfg @ F5Cfg { ( string_from voices_dir ) ( string_from token ) ( string_from vocoder )
        ( string_from models_dir ) unload_ms } )
    : F5Vocab vb ?? ( f5_vocab_load vocab_path ) {
        T x → x
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    : F5Model m ?? ( f5_open ckpt vocab_path device ) {
        T x → x
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    : Vocos vc ?? ( voc_open vocoder ( f5_kit m ) ) {
        T x → x
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    ( locked_set [F5Stat] g_f5_stat @ F5Stat { ( string_from model_id ) T 0 0 1 0 0 } )
    : String cur ( string_from model_id )
    : ( @ v ) modelfn \ → v {
        ( __f5s_model_loop @ F5Run { ( F5Model_share m ) ( Vocos_share vc ) ( F5Vocab_share vb ) ( __f5s_vc_new )
            ( string_from ( string_data cur ) ) unload_ms ( monotonic_ns ) } )
    }
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
            }
        }
    } {}

    : HttpApp a ( http_app_new )
    ( http_app_async a 0 )
    ( http_app_body_max a 4194304 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 30000 )
    ( http_app_request_timeout a 600000 )
    ( http_app_post a `/tts` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_post_json rq T ) } )
    ( http_app_post a `/dialogue` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_post_json rq F ) } )
    ( http_app_get a `/voices` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_voices rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_health rq ) } )
    ( http_app_get a `/models` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_models rq ) } )
    ( http_app_post a `/voices/add` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_voice_add rq ) } )
    ( http_app_get a `/voices/:id/sample` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_voice_sample rq ps ) } )
    ( http_app_delete a `/voices/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_voice_del rq ps ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __f5s_page ) } )

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

    : i rc ( http_app_listen a host port )
    ( __f5s_signal F5_STOP `` )
    ^ rc
}

// ── models and voices over HTTP ─────────────────────────────────────

@ __f5s_models HttpRequest req → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : Json arr ( json_arr_new )
    : F5Cfg c ( __f5s_cfg )
    : ( Vec F5Entry ) reg ( f5_registry ( string_data . c models_dir ) )
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] reg ) {
        ?? ( vec_get [F5Entry] reg k ) {
            T e → {
                : Json o ( json_obj_new )
                : b _a ( json_obj_set o `model_id` ( json_str_lit ( string_data . e id ) ) )
                : b _b ( json_obj_set o `source` ( json_str_lit ? . e local `local` `huggingface` ) )
                : b _c ( json_obj_set o `path` ( json_str_lit ( string_data . e ckpt ) ) )
                : b _d ( json_obj_set o `on_this_machine` ( json_bool . e cached ) )
                : b _e ( json_obj_set o `current`
                ( json_bool != 0 ( nurl_str_eq ( string_data . e id ) ( string_data ( __f5s_cur_id ) ) ) ) )
                : b _f ( json_arr_push arr o )
            }
            F → {}
        }
        = k + k 1
    }
    // The model in use may be a repository reference rather than a directory
    // on this machine, and a list that leaves out what is currently loaded is
    // a list nobody can trust.
    //
    : String cur_id ( __f5s_cur_id )
    : s cur ( string_data cur_id )
    ? & > ( nurl_str_len cur ) 0 ! ( f5_registry_has reg cur ) {
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `model_id` ( json_str_lit cur ) )
        : b _b ( json_obj_set o `source` ( json_str_lit `reference` ) )
        : b _c ( json_obj_set o `path` ( json_str_lit cur ) )
        : b _d ( json_obj_set o `on_this_machine` ( json_bool T ) )
        : b _e ( json_obj_set o `current` ( json_bool T ) )
        : b _f ( json_arr_push arr o )
    } {}
    : HttpResponse r ( response_json 200 arr )
    ^ r
}

// POST /voices/add — multipart with `voice_id`, `ref_text` and a `file` that
// is a wav. The recording is stored as it arrived; f5tts resamples and trims
// it when it first speaks with the voice, so a 44.1 kHz stereo take is fine.
@ __f5s_voice_add HttpRequest req → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    ?? ( request_multipart_parts req ) {
        T parts → {
            : ( Vec u ) wav ( __f5s_part_bytes parts `file` )
            : String vid ( __f5s_part_str parts `voice_id` )
            : String txt ( __f5s_part_str parts `ref_text` )
            : F5Cfg c ( __f5s_cfg )
            : String err ( f5_voice_write ( string_data . c voices ) ( string_data vid ) ( string_data txt ) wav )
            ? == 0 ( string_len err ) {
                // a re-recorded voice must not answer from the old cache
                ( __f5s_signal F5_FORGET ( string_data vid ) )
                : Json o ( json_obj_new )
                : b _a ( json_obj_set o `voice_id` ( json_str_lit ( string_data vid ) ) )
                : b _b ( json_obj_set o `ref_text` ( json_str_lit ( string_data txt ) ) )
                : HttpResponse r ( response_json 200 o )
                ^ r
            } {}
            : HttpResponse r ( __f5s_jerr 400 ( string_data err ) )
            ^ r
        }
        F → {}
    }
    ^ ( __f5s_jerr 400 `send multipart/form-data with voice_id, ref_text and a wav in 'file'` )
}

@ __f5s_part_bytes ( Vec MultipartPart ) parts s name → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : ~ i k 0
    ~ < k ( vec_len [MultipartPart] parts ) {
        ?? ( vec_get [MultipartPart] parts k ) {
            T p → {
                ? != 0 ( nurl_str_eq ( string_data . p name ) name ) {
                    : ~ i j 0
                    ~ < j ( vec_len [u] . p data ) {
                        ?? ( vec_get [u] . p data j ) { T b → { ( vec_push [u] out b ) } F → {} }
                        = j + j 1
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ __f5s_part_str ( Vec MultipartPart ) parts s name → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [MultipartPart] parts ) {
        ?? ( vec_get [MultipartPart] parts k ) {
            T p → {
                ? != 0 ( nurl_str_eq ( string_data . p name ) name ) {
                    : String piece ( bytes_to_str . p data )
                    ( string_append out piece )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ __f5s_voice_del HttpRequest req Params ps → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : ~ s id ``
    ?? ( params_get ps `id` ) { T v → { = id ( string_data v ) } F → {} }
    ? ( f5_id_ok id ) {} { ^ ( __f5s_jerr 400 `a voice id must be a plain name` ) }
    ( __f5s_signal F5_FORGET id )
    : F5Cfg c ( __f5s_cfg )
    ? ( f5_voice_delete ( string_data . c voices ) id ) {} { ^ ( __f5s_jerr 404 `no such voice` ) }
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `deleted` ( json_str_lit id ) )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// GET /voices/{id}/sample — the reference recording itself, so a listener can
// hear what the voice is before asking it to say anything.
@ __f5s_voice_sample HttpRequest req Params ps → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : ~ s id ``
    ?? ( params_get ps `id` ) { T v → { = id ( string_data v ) } F → {} }
    ? ( f5_id_ok id ) {} { ^ ( __f5s_jerr 400 `a voice id must be a plain name` ) }
    : F5Cfg c ( __f5s_cfg )
    : String p ( f5_voice_path ( string_data . c voices ) id )
    ( string_push_str p `/reference.wav` )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bytes → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `content-type` `audio/wav` )
            ( response_set_body_bytes r bytes )
            ^ r
        }
        F _e → {
            ^ ( __f5s_jerr 404 `no such voice` )
        }
    }
}
