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
$ `stdlib/core/rcbox.nu`
$ `run.nu`
$ `text.nu`
$ `store.nu`
$ `registry.nu`
$ `ui.nu`

: ~ i g_f5_model 0  // an F5Model's ctl word: the global is one of its owners

: ~ i g_f5_voc 0  // a Vocos's ctl word, likewise

: ~ i g_f5_vocab 0  // an F5Vocab's ctl word, likewise
// The three globals each hold one owner of what they name, taken over from
// the caller's handle: storing a new one drops the old one's owner here.
// Readers take a view (`# F5Model g_f5_model`), which owns nothing.
unsafe @ __f5s_hold_model sink F5Model m → v {
    : F5Model old @ F5Model { # s g_f5_model }
    = g_f5_model # i . m ctl
    ( mem_forget m )
}

unsafe @ __f5s_hold_voc sink Vocos vc → v {
    : Vocos old @ Vocos { # s g_f5_voc }
    = g_f5_voc # i . vc ctl
    ( mem_forget vc )
}

unsafe @ __f5s_hold_vocab sink F5Vocab vb → v {
    : F5Vocab old @ F5Vocab { # s g_f5_vocab }
    = g_f5_vocab # i . vb ctl
    ( mem_forget vb )
}

: ~ s g_f5_voices ``  // the voices directory

: ~ s g_f5_token ``

: ~ s g_f5_vocoder ``

: ~ i g_f5_reqs 0

: ~ s g_f5_models_dir ``

: ~ i g_f5_cur_id 0  // String — the model the thread currently holds

: ~ i g_f5_switches 0

: ~ i g_f5_unload_ms 0

: ~ i g_f5_idle_since 0

: ~ i g_f5_loads 1

: ~ i g_f5_unloads 0

: ~ i g_f5_load_ms 0

// ── the queue ───────────────────────────────────────────────────────
//
// One job per waiting request, linked through the jobs themselves — a
// module global holds one word, so the queue is two pointers, and its
// lock and two conditions sit in an F5Sync block the server allocates
// once and keeps for the process (the model thread and the ticker
// outlive any one scope, as the handlers do). The submitting fiber owns
// the job (an F5Job handle) until it has seen `done`; the queue and the
// model thread only borrow its address and fill it in.

: F5JobImpl {
    i next
    String voice
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
    ( Vec f ) out
    ( Vec i ) score
    b done
    b ok
    String err
}

: F5Job { s ctl }

@ F5Job_drop sink F5Job h → v {
    ( mem_forget h )
    ( rcbox_release [F5JobImpl] # i . h ctl )
}

: ~ i g_q_head 0

: ~ i g_q_tail 0

: ~ b g_q_stop F

: F5Sync {
    Mutex m  // guards the queue, g_q_stop and the idle clock
    Cond req  // a job was queued, the server is stopping, or a ticker wake
    Cond done  // a job was finished
}

: ~ i g_q_sync 0  // *F5Sync as an address (0 = never served)

unsafe @ __f5s_sync → *F5Sync { ^ # *F5Sync g_q_sync }

// ── the voice cache ─────────────────────────────────────────────────
//
// A voice costs a wav read, a resample and a mel — a tenth of a second, once.
// It is host data and survives an unload, so it is cached for the process's
// life. The model thread is the only reader and the only writer.

: ~ i g_vc_ids 0  // ( Vec String ) as a raw handle

: ~ i g_vc_ptrs 0  // ( Vec F5Voice ) as a raw handle — the cache owns them

: ~ i g_vc_rms 0  // ( Vec f ) — the loudness each was prepared at

@ __f5s_vc_ids → ( Vec String ) { ^ # ( Vec String ) g_vc_ids }

@ __f5s_vc_ptrs → ( Vec F5Voice ) { ^ # ( Vec F5Voice ) g_vc_ptrs }

@ __f5s_vc_rms → ( Vec f ) { ^ # ( Vec f ) g_vc_rms }

// A voice is cached with the loudness it was normalised TO. A request asking
// for a different target_rms gets the recording prepared again rather than
// somebody else's normalisation — the mel the model conditions on is not the
// same mel.
@ __f5s_voice_get s id f target → i {
    : ( Vec String ) ids ( __f5s_vc_ids )
    : i n ( vec_len [String] ids )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ids k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) id ) {
                    : ~ f had -1.0
                    ?? ( vec_get [f] ( __f5s_vc_rms ) k ) { T r → { = had r } F → {} }
                    ? < ( fabs - had target ) 1.0e-9 {
                        ?? ( vec_get [F5Voice] ( __f5s_vc_ptrs ) k ) { T p → { ^ # i . p ctl } F → { ^ 0 } }
                    } {
                        // prepared at a different loudness: drop it and rebuild
                        ( vec_set [F5Voice] ( __f5s_vc_ptrs ) k @ F5Voice { # s 0 } )
                        ( vec_set [f] ( __f5s_vc_rms ) k -1.0 )
                    }
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
    ?? ( f5_voice_open_dir ( string_data dir ) target ) {
        T v → {
            ( vec_push [String] ids ( string_from id ) )
            : i w # i . v ctl
            ( vec_push [F5Voice] ( __f5s_vc_ptrs ) v )
            ( vec_push [f] ( __f5s_vc_rms ) target )
            ^ w
        }
        F e → {
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

// ── switching models ────────────────────────────────────────────────
//
// One model is held at a time. A request naming a different one closes the
// current model and its vocabulary and opens the other, which costs a load
// (a second or so from the page cache) and is reported. Holding several at
// once would be faster to switch between and would also mean several
// gigabytes of a card standing idle, which is the opposite of what
// --unload-after is for.
@ __f5s_cur_id → String { ^ # String g_f5_cur_id }

@ __f5s_switch_to s id → b {
    ? == 0 ( nurl_str_len id ) { ^ T } {}
    ? != 0 ( nurl_str_eq ( string_data ( __f5s_cur_id ) ) id ) { ^ T } {}
    : String ck ( string_new )
    : String vo ( string_new )
    ? ( f5_registry_resolve g_f5_models_dir id ck vo ) {} {
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
                    : String vp ( string_from g_f5_vocoder )
                    : GpuKit nkit ( f5_kit nm )
                    ( __f5s_hold_model nm )
                    ( __f5s_hold_vocab nv )
                    ?? ( voc_open ( string_data vp ) nkit ) {
                        T nvoc → {
                            ( __f5s_hold_voc nvoc )
                            = ok T
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) )
                        }
                    }
                    ? ok {
                        // the old id leaves the global (dropped at the arm's end)
                        : String old_id # String g_f5_cur_id
                        ( mem_take old_id )
                        = g_f5_cur_id # i ( string_from id )
                        = g_f5_switches + g_f5_switches 1
                        ( __f5s_dropvoices )
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

// A voice's mel is conditioned on nothing but the recording, so it survives a
// model switch — but its VOCABULARY ids do not, and the text is tokenised per
// request anyway. What must go is nothing; this is here because the cache
// holds voices, and those are model-independent. Kept as a
// no-op with its reason rather than deleted, so the next person does not
// wonder whether it was forgotten.
@ __f5s_dropvoices → v {}

// ── the model thread ────────────────────────────────────────────────

unsafe @ __f5s_submit * F5JobImpl j → b {
    ? != g_q_sync 0 {} { ^ F }
    : *F5Sync q ( __f5s_sync )
    ( mutex_lock . q m )
    ? == g_q_tail 0 {
        = g_q_head # i j
        = g_q_tail # i j
    } {
        : *F5JobImpl t # *F5JobImpl g_q_tail
        = . t next # i j
        = g_q_tail # i j
    }
    ( cond_signal . q req )
    ~ ! . j done { ( cond_wait . q done . q m ) }
    ( mutex_unlock . q m )
    ^ . j ok
}

@ __f5s_reload → b {
    : F5Model m # F5Model g_f5_model
    : Vocos vc # Vocos g_f5_voc
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
    } {}
    ^ ok
}

// A store through the job's pointer does not drop what it overwrites: the
// empty message leaves through a take first.
unsafe @ __f5s_job_fail * F5JobImpl j s msg → v {
    : String old . j err
    ( mem_take old )
    = . j err ( string_from msg )
    = . j ok F
}

unsafe @ __f5s_run_job * F5JobImpl j → v {
    ? ( __f5s_switch_to ( string_data . j model_id ) ) {} {
        ( __f5s_job_fail j `no such model (GET /models lists what this machine can speak with)` )
        ^ v
    }
    : F5Model m # F5Model g_f5_model
    : Vocos vc # Vocos g_f5_voc
    : F5Vocab vb # F5Vocab g_f5_vocab
    ? ( __f5s_reload ) {} {
        ( __f5s_job_fail j `the weights could not be loaded` )
        ^ v
    }
    : i vp ( __f5s_voice_get ( string_data . j voice ) . j target_rms )
    ? != vp 0 {} {
        ( __f5s_job_fail j `no such voice` )
        ^ v
    }
    : F5Voice v # F5Voice vp
    : b r ( f5_synth_line m vc v vb ( string_data . j text ) . j steps . j cfg . j sway
    . j speed . j fade . j seed . j retries . j max_wer . j splitfail . j out . j score )
    ? r {} { ( __f5s_job_fail j `synthesis failed` ) }
    = . j ok r
}

unsafe @ __f5s_model_loop → v {
    // A CUDA context belongs to the thread that made it current, and this is
    // not that thread: the kit was opened while the process was still one
    // thread. Without this every launch from here fails, quietly, and a
    // request comes back as "synthesis failed" with nothing in the log.
    ? ( gk_bind_thread ( f5_kit # F5Model g_f5_model ) ) {} {
        ( nurl_eprintln `f5tts: the model thread cannot bind the device context` )
        ^
    }
    : *F5Sync q ( __f5s_sync )
    : ~ b run T
    ~ run {
        ( mutex_lock . q m )
        ~ & == g_q_head 0 ! g_q_stop {
            ( cond_wait . q req . q m )
            // a ticker wake with nothing queued: is it time to let go?
            ? & & == g_q_head 0 > g_f5_unload_ms 0 ( f5_loaded # F5Model g_f5_model ) {
                ? >= ( elapsed_ms_since g_f5_idle_since ) g_f5_unload_ms {
                    ( f5_unload # F5Model g_f5_model )
                    ( voc_unload # Vocos g_f5_voc )
                    = g_f5_unloads + g_f5_unloads 1
                    : String s ( string_from `f5tts: idle for ` )
                    ( string_push_int s / g_f5_unload_ms 1000 )
                    ( string_push_str s ` s — weights unloaded (device memory released; the next request reloads them)` )
                    ( nurl_eprintln ( string_data s ) )
                } {}
            } {}
        }
        ? == g_q_head 0 {
            ( mutex_unlock . q m )
            = run F
        } {
            : *F5JobImpl j # *F5JobImpl g_q_head
            = g_q_head . j next
            ? == g_q_head 0 { = g_q_tail 0 } {}
            ( mutex_unlock . q m )
            ( __f5s_run_job j )
            ( mutex_lock . q m )
            = g_f5_idle_since ( monotonic_ns )
            = . j done T
            ( cond_broadcast . q done )
            ( mutex_unlock . q m )
        }
    }
}

unsafe @ __f5s_ticker → v {
    : *F5Sync q ( __f5s_sync )
    ~ T {
        ( sleep_ms 200 )
        ( mutex_lock . q m )
        ( cond_broadcast . q req )
        ( mutex_unlock . q m )
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
unsafe @ __f5s_one s voice s text i steps f cfg f sway f speed f fade i seed
i retries f max_wer i splitfail f target_rms s model_id ( Vec f ) out ( Vec i ) score String err → b {
    ? ( f5_voice_id_ok voice ) {} {
        ( string_push_str err `voice id must be a plain directory name` )
        ^ F
    }
    : F5Job jh @ F5Job { # s ( rcbox_new [F5JobImpl] @ F5JobImpl {
            0 ( string_from voice ) ( string_from text ) steps cfg sway speed fade seed
            retries max_wer splitfail target_rms ( string_from model_id )
            ( vec_new [f] ) ( f5_score_new ) F F ( string_new ) } ) }
    : *F5JobImpl j ( rcbox_ptr [F5JobImpl] # i . jh ctl )
    : b r ( __f5s_submit j )
    ? r {
        : i n ( vec_len [f] . j out )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [f] . j out k ) { T x → { ( vec_push [f] out x ) } F → {} }
            = k + k 1
        }
        ( f5_score_merge score . j score )
    } { ( string_push_str err ( string_data . j err ) ) }
    ^ r
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
    : String bodys ( string_new )
    ( string_push_bytes bodys ( vec_data [u] . req body ) ( vec_len [u] . req body ) )
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
            = g_f5_reqs + g_f5_reqs 1
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
    : b loaded ( f5_loaded # F5Model g_f5_model )
    : b _a ( json_obj_set o `status` ( json_str_lit ? loaded `ok` `idle` ) )
    : b _b ( json_obj_set o `loaded` ( json_bool loaded ) )
    : b _c ( json_obj_set o `requests` ( json_int g_f5_reqs ) )
    : b _d ( json_obj_set o `unload_after_s` ( json_int / g_f5_unload_ms 1000 ) )
    : b _e ( json_obj_set o `loads` ( json_int g_f5_loads ) )
    : b _f ( json_obj_set o `unloads` ( json_int g_f5_unloads ) )
    : b _g ( json_obj_set o `last_load_ms` ( json_int g_f5_load_ms ) )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// ── the server ──────────────────────────────────────────────────────

unsafe @ f5_serve s ckpt s vocab_path s vocoder s voices_dir s models_dir s model_id
s host i port s token i device i unload_s → i {
    ( f5_ensure_dirs )
    = g_f5_models_dir models_dir
    = g_f5_vocoder vocoder
    = g_f5_cur_id # i ( string_from model_id )
    ?? ( f5_vocab_load vocab_path ) {
        T vb → { ( __f5s_hold_vocab vb ) }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    ?? ( f5_open ckpt vocab_path device ) {
        T m → { ( __f5s_hold_model m ) }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    ?? ( voc_open vocoder ( f5_kit # F5Model g_f5_model ) ) {
        T vc → { ( __f5s_hold_voc vc ) }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
    = g_f5_voices voices_dir
    = g_f5_token token
    = g_f5_unload_ms * unload_s 1000
    = g_f5_idle_since ( monotonic_ns )
    = g_vc_ids # i ( vec_new [String] )
    = g_vc_ptrs # i ( vec_new [F5Voice] )
    = g_vc_rms # i ( vec_new [f] )

    ? == g_q_sync 0 {
        : *F5Sync qs # *F5Sync ( nurl_alloc Z F5Sync )
        = . qs m ( mutex_new )
        = . qs req ( cond_new )
        = . qs done ( cond_new )
        = g_q_sync # i qs
    } {}
    : *F5Sync q ( __f5s_sync )
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
    ( mutex_lock . q m )
    = g_q_stop T
    ( cond_broadcast . q req )
    ( mutex_unlock . q m )
    ^ rc
}

// ── models and voices over HTTP ─────────────────────────────────────

@ __f5s_models HttpRequest req → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : Json arr ( json_arr_new )
    : ( Vec F5Entry ) reg ( f5_registry g_f5_models_dir )
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
    // `__f5s_cur_id` hands back a view of the GLOBAL's String, not a copy —
    // releasing it here would release the service's own current-model id, and
    // every later read of it is a use-after-free that lands in libc with no
    // NURL frame to blame. It is borrowed here, as `s`.
    : s cur ( string_data ( __f5s_cur_id ) )
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
            : String err ( f5_voice_write g_f5_voices ( string_data vid ) ( string_data txt ) wav )
            ? == 0 ( string_len err ) {
                // a re-recorded voice must not answer from the old cache
                ( __f5s_voice_forget ( string_data vid ) )
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
                    ( string_push_bytes out ( vec_data [u] . p data ) ( vec_len [u] . p data ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

// Drop a voice from the cache: a re-recorded voice with the same id must not
// keep answering from the mel of the take it replaced.
@ __f5s_voice_forget s id → v {
    : ( Vec String ) ids ( __f5s_vc_ids )
    : ~ i k 0
    ~ < k ( vec_len [String] ids ) {
        ?? ( vec_get [String] ids k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) id ) {
                    ( vec_set [F5Voice] ( __f5s_vc_ptrs ) k @ F5Voice { # s 0 } )
                    ( vec_set [f] ( __f5s_vc_rms ) k -1.0 )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
}

@ __f5s_voice_del HttpRequest req Params ps → HttpResponse {
    ? ( __f5s_authed req ) {} { ^ ( __f5s_jerr 401 `unauthorized` ) }
    : ~ s id ``
    ?? ( params_get ps `id` ) { T v → { = id ( string_data v ) } F → {} }
    ? ( f5_id_ok id ) {} { ^ ( __f5s_jerr 400 `a voice id must be a plain name` ) }
    ( __f5s_voice_forget id )
    ? ( f5_voice_delete g_f5_voices id ) {} { ^ ( __f5s_jerr 404 `no such voice` ) }
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
    : String p ( f5_voice_path g_f5_voices id )
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
