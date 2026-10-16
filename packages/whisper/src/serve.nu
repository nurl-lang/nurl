// packages/whisper/src/serve.nu — whisper as a service.
//
//   whisper serve <model-dir> --addr 0.0.0.0:6543 [--lang en] [--vad] [--timestamps]
//
// The point of a server is WHEN the model loads. The CLI pays the whole bill
// per invocation — read 1.5 GB of safetensors, convert f16 to f32 on the
// device, compile the kernels — and only then hears the audio. Here all of
// that happens once, before the port opens; a request pays for its own audio
// and nothing else.
//
// The HTTP surface is whisper.cpp's, so its clients work unchanged:
//
//   POST /inference    multipart/form-data with a `file` field (WAV), plus
//                      optional `language` and `response_format` (json|text)
//                      fields → {"text":"..."} or the bare text.
//                      A raw WAV body (no multipart) is also accepted —
//                      curl --data-binary @clip.wav is not a browser form,
//                      and there is no reason to make it pretend to be one.
//   GET  /health       {"status":"ok", model shape, request count}
//   GET  /             the same (a browser poking the port should learn
//                      something, not get a 404)
//
// Per-request `vad` and `timestamps` fields override the server-side flags,
// so one server can serve both a subtitle pipeline and a bare-text one.
//
// Handlers are top-level functions reading module globals, not closures over
// locals — the same idiom as nurllama's api.nu, and for the same reason:
// closure environments are manual in NURL, and a server's handlers live for
// the process.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/http/src/http.nu`
$ `src/run.nu`
$ `src/silero.nu`
$ `src/stream.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: ~ b g_srv_vad F
: ~ b g_srv_ts F
: ~ i g_srv_max 0
: ~ f g_srv_nospeech 0.6

// The server's text settings: the model argument (kept for the reloads),
// the default language, and the bearer token (empty = open server, the
// loopback default). Set before the port opens; requests and the unload
// reaper read copies. (As string globals, the compiler cannot see that
// nothing replaces them while another thread reads them, and reset at the
// end they would be.)
: SrvCfg {
    String dir
    String lang
    String token
}

@ __srv_cfg0 → ( Locked SrvCfg ) { ^ ( locked_new [SrvCfg] @ SrvCfg { ( string_new ) ( string_new ) ( string_new ) } ) }

: ( Locked SrvCfg ) g_srv_cfg ( __srv_cfg0 )

@ __srv_cfg → SrvCfg { ^ ( locked_get [SrvCfg] g_srv_cfg ) }

// ── the model as a lease: loaded on demand, released when idle ──────
//
// `--unload-after N` makes the model a thing the server HOLDS rather than
// IS. A reaper thread watches the clock; N seconds after the last request
// ends, with nothing in flight, it closes the model — device buffers,
// kernels, the CUDA context, the tokenizer stays (a few MB) — and the
// next request reloads it before it runs. What the server keeps while idle
// is the port and about a hundred megabytes of process; what it gives
// back is everything the model was (large-v3: 4.8 GB of device memory).
//
// Who may touch the model: a request holds `busy` from acquire to release,
// a WebSocket stream for the life of the connection, and the reaper only
// ever closes a model nobody holds. All of it is one Locked record set at
// start — reached from every handler and from the reaper in safe code,
// and held by nothing longer than a load.
: SrvState {
    ? Whisper w  // the loaded model, OWNED by the server (F = none loaded)
    i reqs
    i busy  // requests + streams holding the model right now
    i idle_since  // monotonic_ns when the last holder let go
    i loads  // (re)loads so far — 1 is the load before the port opened
    i unloads
    i load_ms  // the last load's wall time
    i unload_ms  // 0 = the model stays for the process's life
}

@ __srv_blank → ( Locked SrvState ) {
    ^ ( locked_new [SrvState] @ SrvState { @ ?Whisper { F } 0 0 0 0 0 0 0 } )
}

: ( Locked SrvState ) g_srv ( __srv_blank )

@ __srv_tok_blank → ( Locked ? Tok ) { ^ ( locked_new [? Tok] @ ?Tok { F } ) }

: ( Locked ? Tok ) g_srv_tok ( __srv_tok_blank )  // one owner of the tokenizer, kept while serving

// One more owner of the loaded model, for a request or a stream that holds
// `busy` (the reaper leaves a held model alone).
@ __srv_model → Whisper {
    : SrvState st ( locked_take [SrvState] g_srv )
    : ~ ? Whisper out @ ?Whisper { F }
    ?? . st w { T w → { = out @ ?Whisper { T ( Whisper_share w ) } } F → {} }
    ( locked_restore [SrvState] g_srv st )
    ?? out {
        T w → { ^ w }
        F → { ( nurl_panic `whisper: no model loaded under a busy hold` ) }
    }
}

// The tokenizer, one more owner of it.
@ __srv_tok → Tok {
    : ?Tok t ( locked_take [? Tok] g_srv_tok )
    : ~ ? Tok out @ ?Tok { F }
    ?? t { T x → { = out @ ?Tok { T ( Tok_share x ) } } F → {} }
    ( locked_restore [? Tok] g_srv_tok t )
    ?? out {
        T x → { ^ x }
        F → { ( nurl_panic `whisper: no tokenizer while serving` ) }
    }
}

// One more request served.
@ __srv_count → v {
    : ~ SrvState st ( locked_take [SrvState] g_srv )
    = . st reqs + . st reqs 1
    ( locked_restore [SrvState] g_srv st )
}

// Open the model at the configured dir into the state (taken by the caller). The
// tokenizer is not rebuilt: it was made once, before the port opened, and
// a vocabulary does not change between loads of the same file.
@ __srv_load inout SrvState st → b {
    : i t0 ( monotonic_ns )
    : ~ b ok F
    : SrvCfg cf ( __srv_cfg )
    : s dir ( string_data . cf dir )
    ? ( _wh_is_ggml dir ) {
        ?? ( wh_open_ggml dir ) {
            T w → {
                = . st w @ ?Whisper { T w }
                = ok T
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
            }
        }
    } {
        : String cfg ( _wh_path dir `config.json` )
        : String wts ( _wh_path dir `model.safetensors` )
        ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
            T w → {
                = . st w @ ?Whisper { T w }
                = ok T
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
            }
        }
    }
    ? ! ok { ^ F } {}
    = . st loads + . st loads 1
    = . st load_ms / - ( monotonic_ns ) t0 1000000
    : String m ( string_from `whisper: model loaded in ` )
    ( string_push_int m . st load_ms )
    ( string_push_str m ` ms` )
    ( nurl_eprintln ( string_data m ) )
    ^ T
}

// Take the model for one request or one stream: load it if the reaper has
// let it go. F = it could not be loaded (the log says why) — the caller
// answers 503 and the next request tries again.
@ __srv_acquire → b {
    : ~ SrvState st ( locked_take [SrvState] g_srv )
    : ~ b ok T
    ?? . st w { T _ → {} F → { = ok ( __srv_load st ) } }
    ? ok { = . st busy + . st busy 1 } {}
    ( locked_restore [SrvState] g_srv st )
    ^ ok
}

@ __srv_release → v {
    : ~ SrvState st ( locked_take [SrvState] g_srv )
    = . st busy - . st busy 1
    = . st idle_since ( monotonic_ns )
    ( locked_restore [SrvState] g_srv st )
}

// The reaper: a thread that wakes five times a second and closes the model
// once it has sat unused for the configured time. The close runs on this
// thread, so the device context is bound here first (gpu_bind_thread); the
// model's own close releases the context, and the next load on the request
// thread retains it again.
@ __srv_reaper → v {
    ~ T {
        ( sleep_ms 200 )
        : ~ SrvState st ( locked_take [SrvState] g_srv )
        ?? . st w {
            T w → {
                ? & == . st busy 0 >= ( elapsed_ms_since . st idle_since ) . st unload_ms {
                    // the server's owner is released right here, on the
                    // thread the context was just bound to
                    : b _b ( wh_bind_thread w )
                    = . st w @ ?Whisper { F }
                    = . st unloads + . st unloads 1
                    : String m ( string_from `whisper: idle for ` )
                    ( string_push_int m / . st unload_ms 1000 )
                    ( string_push_str m ` s — model unloaded (device and host memory released; the next request reloads it)` )
                    ( nurl_eprintln ( string_data m ) )
                } {}
            }
            F → {}
        }
        ( locked_restore [SrvState] g_srv st )
    }
}

// Constant-time-ish token compare: every byte of the CONFIGURED token is
// examined, and the length mismatch folds in, so response timing does not
// leak how far a guess matched. (Not a defence against a local attacker
// with a cycle counter — it defends the realistic case, a token guessed
// over the network.)
@ __srv_tok_eq s got s want → b {
    : ( Slice u ) got_v ( slice_of_str got )
    : ( Slice u ) want_v ( slice_of_str want )
    : i lg ( nurl_str_len got )
    : i lw ( nurl_str_len want )
    : ~ i diff ^^ lg lw
    : ~ i k 0
    ~ < k lw {
        : i cw ( slice_byte want_v k )
        : i cg ? < k lg ( slice_byte got_v k ) 0
        = diff | diff ^^ cw cg
        = k + k 1
    }
    ^ == diff 0
}

// `token=` out of a raw query string ("a=1&token=xyz").
@ __srv_query_token s q → String {
    : ( Slice u ) q_v ( slice_of_str q )
    : String out ( string_new )
    : i n ( nurl_str_len q )
    : ~ i k 0
    ~ < k n {
        ? | == k 0 == ( slice_byte q_v - k 1 ) 38 {
            ? & & & & & <= + k 6 n == ( slice_byte q_v k ) 116 == ( slice_byte q_v + k 1 ) 111
            == ( slice_byte q_v + k 2 ) 107 == ( slice_byte q_v + k 3 ) 101 == ( slice_byte q_v + k 4 ) 110 {
                ? == ( slice_byte q_v + k 5 ) 61 {
                    : ~ i j + k 6
                    ~ & < j n != ( slice_byte q_v j ) 38 {
                        ( string_push_char out ( slice_byte q_v j ) )
                        = j + j 1
                    }
                    ^ out
                } {}
            } {}
        } {}
        = k + k 1
    }
    ^ out
}

// Is this request allowed? No token configured → always. Otherwise the
// token must arrive as `Authorization: Bearer <t>` (HTTP clients) or
// `?token=<t>` in the query (a browser cannot set headers on a WebSocket
// upgrade or an <img>/fetch to a bare URL, so the query form is the one
// that works everywhere).
@ __srv_authed HttpRequest req → b {
    : SrvCfg cf ( __srv_cfg )
    : s tok ( string_data . cf token )
    ? == ( nurl_str_len tok ) 0 { ^ T } {}
    : ~ b ok F
    ?? ( header_get . req headers `authorization` ) {
        T hv → {
            : s h ( string_data hv )
            ? & > ( nurl_str_len h ) 7 != 0 ( nurl_str_starts h `Bearer ` ) {
                ? ( __srv_tok_eq ( nurl_str_slice h 7 - ( nurl_str_len h ) 7 ) tok ) { = ok T } {}
            } {}
        }
        F → {}
    }
    ? ok { ^ T } {}
    : String qt ( __srv_query_token ( string_data . req query ) )
    ? > ( string_len qt ) 0 {
        ? ( __srv_tok_eq ( string_data qt ) tok ) { = ok T } {}
    } {}
    ^ ok
}

@ __srv_401 → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit `unauthorized — pass the token as 'Authorization: Bearer <token>' or '?token=<token>'` ) )
    : HttpResponse r ( response_json 401 o )
    ^ r
}

// The bytes of the multipart part called `name`, copied — or an empty vec.
@ __srv_part_bytes ( Vec MultipartPart ) parts s name → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : ~ i k 0
    ~ < k ( vec_len [MultipartPart] parts ) {
        ?? ( vec_get [MultipartPart] parts k ) {
            T p → {
                ? ( nurl_str_eq ( string_data . p name ) name ) {
                    : ~ i j 0
                    ~ < j ( vec_len [u] . p data ) {
                        ?? ( vec_get [u] . p data j ) {
                            T b → { ( vec_push [u] out b ) }
                            F → {}
                        }
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

// A multipart text field as a fresh String (empty if absent).
@ __srv_field_str ( Vec MultipartPart ) parts s name → String {
    : ( Vec u ) b ( __srv_part_bytes parts name )
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [u] b ) {
        ?? ( vec_get [u] b k ) {
            T c → { ( string_push_char out c ) }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ __srv_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

// The request's WAV bytes as 16 kHz samples. Takes the bytes: the upload,
// the parsed WAV and its mono mix are all gone before the model runs.
@ __srv_pcm16 sink ( Vec u ) wav → !( Vec f ) String {
    ?? ( wav_parse wav ) {
        T aw → { ^ @ !( Vec f ) String { T ( wh_wav16 aw ) } }
        F e → { ^ @ !( Vec f ) String { F e } }
    }
}

// The transcription itself, after the request has been picked apart.
// Takes `wav`.
@ __srv_run sink ( Vec u ) wav s lang b use_vad b with_ts b as_text → HttpResponse {
    ?? ( __srv_pcm16 wav ) {
        T at16 → {

            : Whisper w ( __srv_model )
            : Tok t ( __srv_tok )
            : ( Vec u ) text ( vec_new [u] )
            ? ( wh_run w t at16 lang g_srv_max use_vad with_ts g_srv_nospeech text ) {
                // trim the leading space the tokenizer writes on plain text
                : ~ i from 0
                ? with_ts {} {
                    ?? ( vec_get [u] text 0 ) {
                        T c → { ? == c 32 { = from 1 } {} }
                        F → {}
                    }
                }
                : String st ( string_new )
                : ~ i k from
                ~ < k ( vec_len [u] text ) {
                    ?? ( vec_get [u] text k ) {
                        T c → { ( string_push_char st c ) }
                        F → {}
                    }
                    = k + k 1
                }
                ? as_text {
                    : HttpResponse r ( response_text 200 ( string_data st ) )
                    ^ r
                } {}
                : Json o ( json_obj_new )
                : b _s ( json_obj_set o `text` ( json_str_lit ( string_data st ) ) )
                : HttpResponse r ( response_json 200 o )
                ^ r
            } {}
            ^ ( __srv_err 500 `decode failed (is this a whisper tokenizer.json?)` )
        }
        F e → {
            : HttpResponse r ( __srv_err 400 ( string_data e ) )
            ^ r
        }
    }
}

// POST /inference — the whisper.cpp endpoint.
@ __srv_inference HttpRequest req → HttpResponse {
    ? ( __srv_authed req ) {} { ^ ( __srv_401 ) }
    ? ( __srv_acquire ) {} { ^ ( __srv_err 503 `the model could not be loaded — the server log has the reason` ) }
    : HttpResponse r ( __srv_inference_run req )
    ( __srv_release )
    ^ r
}

// The request proper, with the model held.
@ __srv_inference_run HttpRequest req → HttpResponse {
    ( __srv_count )

    ?? ( request_multipart_parts req ) {
        T parts → {
            : ( Vec u ) wav ( __srv_part_bytes parts `file` )
            : String lang_s ( __srv_field_str parts `language` )
            : String fmt_s ( __srv_field_str parts `response_format` )
            : String vad_s ( __srv_field_str parts `vad` )
            : String ts_s ( __srv_field_str parts `timestamps` )
            ? == 0 ( vec_len [u] wav ) {
                ^ ( __srv_err 400 `multipart form has no 'file' field` )
            } {}
            : SrvCfg cf ( __srv_cfg )
            : ~ s lang ( string_data . cf lang )
            ? > ( string_len lang_s ) 0 { = lang ( string_data lang_s ) } {}
            : b vs ? ( nurl_str_eq ( string_data vad_s ) `true` ) T F
            : b ts2 ? ( nurl_str_eq ( string_data ts_s ) `true` ) T F
            : b use_vad | g_srv_vad vs
            : b with_ts | g_srv_ts ts2
            : b as_text ? ( nurl_str_eq ( string_data fmt_s ) `text` ) T F
            : HttpResponse r ( __srv_run wav lang use_vad with_ts as_text )
            ^ r
        }
        F → {}
    }
    // no multipart boundary: the body IS the WAV
    ? == 0 ( vec_len [u] . req body ) {
        ^ ( __srv_err 400 `no audio: send multipart with a 'file' field, or a raw WAV body` )
    } {}
    : ( Vec u ) wav ( vec_new [u] )
    : ~ i k 0
    ~ < k ( vec_len [u] . req body ) {
        ?? ( vec_get [u] . req body k ) {
            T b → { ( vec_push [u] wav b ) }
            F → {}
        }
        = k + k 1
    }
    : SrvCfg cf2 ( __srv_cfg )
    ^ ( __srv_run wav ( string_data . cf2 lang ) g_srv_vad g_srv_ts F )
}

// Where the test page lives on disk. Resolution mirrors packages/anomaly's
// dashboard (nurlpkg's [install].assets stages `views` into
// $NURL_HOME/share/whisper/, a sibling of bin/):
//   <exe-dir>/views/index.html            (a hand-placed page beside the exe)
//   <exe-dir>/../share/whisper/views/…    (nurlpkg install)
//   views/index.html                      (running from the package dir)
@ __srv_page_path → String {
    : !String IoErr exe ( fs_readlink `/proc/self/exe` )
    ?? exe {
        T ep → {
            : String bindir ( path_dirname ( string_data ep ) )
            : String c1 ( path_join ( string_data bindir ) `views/index.html` )
            ? ( file_exists ( string_data c1 ) ) {
                ^ c1
            } {}
            : String share ( path_join ( string_data bindir ) `../share/whisper/views/index.html` )
            ? ( file_exists ( string_data share ) ) { ^ share } {}
        }
        F _ → {}
    }
    ? ( file_exists `views/index.html` ) { ^ ( string_from `views/index.html` ) } {}
    ^ ( string_new )
}

// GET / — the test page: upload a file, or stream the microphone over the
// same port's WebSocket. Served from disk like every other asset in this
// ecosystem; a missing page degrades to a pointer, not a broken server.
@ __srv_page HttpRequest req → HttpResponse {
    : String pp ( __srv_page_path )
    ? > ( string_len pp ) 0 {
        ?? ( read_file_bytes ( string_data pp ) ) {
            T body → {
                : HttpResponse r ( response_new 200 )
                ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
                ( response_set_body_bytes r body )
                ^ r
            }
            F _ → {}
        }
    } {}
    ^ ( response_text 404 `test page not found — reinstall the package (nurlpkg stages views/ into share/whisper/), or run from the package directory\n` )
}

@ __srv_health HttpRequest req → HttpResponse {
    : Json o ( json_obj_new )
    // `ok` = loaded and serving; `idle` = unloaded by --unload-after, the
    // next request reloads it (still healthy — a client should not treat
    // idle as down)
    : SrvState st ( locked_take [SrvState] g_srv )
    : ~ b loaded F
    ?? . st w { T _ → { = loaded T } F → {} }
    : b _a ( json_obj_set o `status` ( json_str_lit ? loaded `ok` `idle` ) )
    : b _l ( json_obj_set o `loaded` ( json_bool loaded ) )
    ?? . st w {
        T w → {
            : b _b ( json_obj_set o `d_model` ( json_int ( wh_d_model w ) ) )
            : b _c ( json_obj_set o `n_mels` ( json_int ( wh_n_mels w ) ) )
            : b _d ( json_obj_set o `encoder_layers` ( json_int ( wh_n_enc_layer w ) ) )
            : b _e ( json_obj_set o `decoder_layers` ( json_int ( wh_n_dec_layer w ) ) )
        }
        F → {}
    }
    : b _f ( json_obj_set o `requests` ( json_int . st reqs ) )
    : b _g ( json_obj_set o `unload_after_s` ( json_int / . st unload_ms 1000 ) )
    : b _h ( json_obj_set o `loads` ( json_int . st loads ) )
    : b _i ( json_obj_set o `unloads` ( json_int . st unloads ) )
    : b _j ( json_obj_set o `last_load_ms` ( json_int . st load_ms ) )
    ? & == . st busy 0 ! loaded {
        : b _k ( json_obj_set o `idle_s` ( json_int / ( elapsed_ms_since . st idle_since ) 1000 ) )
    } {}
    ( locked_restore [SrvState] g_srv st )
    : HttpResponse r ( response_json 200 o )
    ^ r
}

// ── WebSocket streaming: the microphone case ────────────────────────
//
// The same port. A client that connects with `Upgrade: websocket` streams raw
// 16 kHz mono audio (binary frames: PCM16 by default, or float32) and gets
// JSON text messages back. With no configuration it gets what it always got,
// one message per UTTERANCE:
//
//   {"text":" ...","t0":12.34,"t1":15.67,"type":"final","seg":3,
//    "speech_t0":12.64,"speech_t1":15.27,"proc_ms":0}
//
// t0/t1 are seconds on the STREAM's clock — where in everything sent so far
// the audio that was transcribed lies (lead-in and closing silence
// included); speech_t0/speech_t1 where the voice itself began and ended.
// proc_ms is what the transcription cost after the utterance closed — 0
// when the pause was used to make it ahead of time.
//
// A text message configures the stream — any time, any subset of fields —
// and is answered with {"status":"ok", …the settings in force}:
//
//   format      "pcm16" | "float32"
//   lang        "fi", "en", …  (default: the server's --lang)
//   partials    true: drafts of the utterance while it is being spoken
//                 {"type":"partial","seg":3,"text":"…","stable":"…","t0","t1","pause_ms"}
//               `stable` is the prefix two drafts in a row agreed on (the
//               words the speaker has finished); `pause_ms` how long they
//               had been quiet when the draft's audio ended. Every utterance
//               that had a draft ends in a final, an empty one included, so
//               a client can clear what it showed.
//   partial_ms  a draft per this much new speech (default 300, min 100)
//   pause_ms    the silence that ends an utterance; setting it turns the
//               adaptation off unless "adaptive":true comes with it
//   adaptive    learn the closing pause from the speaker's own gaps between
//               words (default true), within min_pause_ms…max_pause_ms
//               (default 300…1000)
//   threshold   Silero's p(speech) that opens an utterance (default 0.5)
//   near_db     the near-field gate: chunks this far below the speaker's
//               own level are someone else (default 10; 0 = off)
//   max_utt_ms  close an utterance at its best gap past this (≤ 28000)
//   events      true: {"type":"start","seg","t0"} when speech begins
//   levels      true: {"type":"level","noise_db","speech_db","snr_db",
//               "p_noise","pause_ms","threshold"} once a second
//   vad         "silero" (default when the weights are installed) | "energy"
//
// and two commands, which are not acknowledged:
//
//   {"cmd":"end"}    the utterance is over now — transcribe what was heard
//                    (a push-to-talk release, or a client that already knows)
//   {"cmd":"reset"}  forget the open utterance (a new question: what was
//                    being said is no longer an answer)
//
// What decides an utterance is stream.nu: Silero's voice probability, the
// room's noise floor and the speaker's level re-measured continuously, and
// a closing pause learned from the speaker. One port, not two: the whisper.cpp
// fork this replaces needs a second listener because its HTTP and WS stacks
// cannot share one, and ours are the same stack by construction.

// One stream's settings, from its config messages. They belong to the
// connection: as globals, two streams open at once took each other's
// sample format and language (and one could free the language string the
// other was transcribing with).
: WsCfg {
    b f32  // the client sends float32 frames, else PCM16
    String lang  // the language override ("" = the server's default)
    WssCfg st  // the endpointer's settings
    b silero  // F = the energy detector, by request
}

// The Silero network, loaded once when the server starts (F = no weights:
// every stream falls back to the energy detector).
@ __srv_vad_blank → ( Locked ? Silero ) { ^ ( locked_new [? Silero] @ ?Silero { F } ) }

: ( Locked ? Silero ) g_srv_vad_net ( __srv_vad_blank )

@ __srv_vad_net → ?Silero {
    : ?Silero n ( locked_take [? Silero] g_srv_vad_net )
    : ~ ? Silero out @ ?Silero { F }
    ?? n { T x → { = out @ ?Silero { T ( Silero_share x ) } } F → {} }
    ( locked_restore [? Silero] g_srv_vad_net n )
    ^ out
}

@ __srv_ws_send TcpConn c Json o → v {
    : String body ( json_stringify o )
    : !v WsErr _w ( ws_send_text c ( string_data body ) )
}

@ __srv_ws_ack TcpConn c WsCfg wc WsStream ws → v {
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `status` ( json_str_lit `ok` ) )
    : b _b ( json_obj_set o `format` ( json_str_lit ? . wc f32 `float32` `pcm16` ) )
    : b _c ( json_obj_set o `vad` ( json_str_lit ? & . wc silero ( __srv_has_silero ) `silero` `energy` ) )
    : b _d ( json_obj_set o `partials` ( json_bool . . wc st partials ) )
    : b _e ( json_obj_set o `partial_ms` ( json_int . . wc st partial_ms ) )
    : b _f ( json_obj_set o `pause_ms` ( json_int . ws eou_ms ) )
    : b _g ( json_obj_set o `adaptive` ( json_bool . . wc st adaptive ) )
    : b _h ( json_obj_set o `min_pause_ms` ( json_int . . wc st min_pause_ms ) )
    : b _i ( json_obj_set o `max_pause_ms` ( json_int . . wc st max_pause_ms ) )
    : b _j ( json_obj_set o `threshold` ( json_float . . wc st threshold ) )
    : b _k ( json_obj_set o `near_db` ( json_float . . wc st near_db ) )
    : b _l ( json_obj_set o `sample_rate` ( json_int 16000 ) )
    ( __srv_ws_send c o )
}

@ __srv_has_silero → b {
    ?? ( __srv_vad_net ) { T _ → { ^ T } F → { ^ F } }
}

@ __srv_jint Json j s key i def → i {
    ?? ( json_obj_get j key ) {
        T v → { ?? ( json_num_as_i v ) { T x → { ^ x } F → { ^ def } } }
        F → { ^ def }
    }
}

@ __srv_jnum Json j s key f def → f {
    ?? ( json_obj_get j key ) {
        T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F → { ^ def } } }
        F → { ^ def }
    }
}

@ __srv_jbool Json j s key b def → b {
    ?? ( json_obj_get j key ) {
        T v → { ? ( json_is_bool v ) { ^ ( json_as_bool v ) } { ^ def } }
        F → { ^ def }
    }
}

@ __srv_clamp i x i lo i hi → i { ^ ? < x lo lo ? > x hi hi x }

// A text frame: a command (T = it was one, `cmd` says which: 1 end, 2 reset)
// or a configuration, applied and acknowledged.
@ __srv_ws_text TcpConn c ( Vec u ) payload inout WsCfg wc inout WsStream ws → i {
    : String ps ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [u] payload ) {
        ( string_push_char ps ( vec_at [u] payload k ) )
        = k + k 1
    }
    ?? ( json_parse ( string_data ps ) ) {
        T j → {
            ?? ( json_obj_get j `cmd` ) {
                T cv → {
                    : s cmd ( json_as_str cv )
                    ? != 0 ( nurl_str_eq cmd `end` ) { ^ 1 } {}
                    ? != 0 ( nurl_str_eq cmd `reset` ) { ^ 2 } {}
                    : Json eo ( json_obj_new )
                    : b _e ( json_obj_set eo `error` ( json_str_lit `unknown cmd — "end" or "reset"` ) )
                    ( __srv_ws_send c eo )
                    ^ 0
                }
                F → {}
            }
            ?? ( json_obj_get j `format` ) {
                T v → { = . wc f32 != 0 ( nurl_str_eq ( json_as_str v ) `float32` ) }
                F → {}
            }
            ?? ( json_obj_get j `lang` ) {
                T v → {
                    : s ls ( json_as_str v )
                    ? > ( nurl_str_len ls ) 0 { = . wc lang ( string_from ls ) } {}
                }
                F → {}
            }
            ?? ( json_obj_get j `vad` ) {
                T v → { = . wc silero == 0 ( nurl_str_eq ( json_as_str v ) `energy` ) }
                F → {}
            }
            : ~ WssCfg st . wc st
            = . st partials ( __srv_jbool j `partials` . st partials )
            = . st partial_ms ( __srv_clamp ( __srv_jint j `partial_ms` . st partial_ms ) 100 5000 )
            = . st min_pause_ms ( __srv_clamp ( __srv_jint j `min_pause_ms` . st min_pause_ms ) 100 5000 )
            = . st max_pause_ms ( __srv_clamp ( __srv_jint j `max_pause_ms` . st max_pause_ms ) . st min_pause_ms 10000 )
            ?? ( json_obj_get j `pause_ms` ) {
                T _ → {
                    = . st pause_ms ( __srv_clamp ( __srv_jint j `pause_ms` . st pause_ms ) 100 10000 )
                    = . st adaptive F
                    ? < . st pause_ms . st min_pause_ms { = . st min_pause_ms . st pause_ms } {}
                    ? > . st pause_ms . st max_pause_ms { = . st max_pause_ms . st pause_ms } {}
                }
                F → {}
            }
            = . st adaptive ( __srv_jbool j `adaptive` . st adaptive )
            : ~ f th ( __srv_jnum j `threshold` . st threshold )
            ? < th 0.2 { = th 0.2 } {}
            ? > th 0.95 { = th 0.95 } {}
            = . st threshold th
            : ~ f nd ( __srv_jnum j `near_db` . st near_db )
            ? < nd 0.0 { = nd 0.0 } {}
            = . st near_db nd
            = . st max_utt_ms ( __srv_clamp ( __srv_jint j `max_utt_ms` . st max_utt_ms ) 2000 28000 )
            = . st events ( __srv_jbool j `events` . st events )
            = . st levels ( __srv_jbool j `levels` . st levels )
            = . wc st st
            ( ws_stream_set_cfg ws st )
            ? . wc silero {} { = . ws net @ ?Silero { F } }
        }
        F _ → {}
    }
    ( __srv_ws_ack c wc ws )
    ^ 0
}

// binary frame → f32 samples at 16 kHz (the client's job to resample; a
// microphone opened at 16 kHz is the normal case)
@ __srv_ws_samples ( Vec u ) d b f32 → ( Vec f ) {
    : i n ( vec_len [u] d )
    ? f32 {
        : ( Vec f ) out ( vec_with_cap [f] / n 4 )
        : ~ i k 0
        ~ <= + k 4 n {
            : i bits | | | # i ( vec_at [u] d k ) << # i ( vec_at [u] d + k 1 ) 8 << # i ( vec_at [u] d + k 2 ) 16 << # i ( vec_at [u] d + k 3 ) 24
            ( vec_push [f] out # f ( bits_to_f32 bits ) )
            = k + k 4
        }
        ^ out
    } {}
    : ( Vec f ) out ( vec_with_cap [f] / n 2 )
    : ~ i k 0
    ~ <= + k 2 n {
        : ~ i v | # i ( vec_at [u] d k ) << # i ( vec_at [u] d + k 1 ) 8
        ? >= v 32768 { = v - v 65536 } {}
        ( vec_push [f] out / # f v 32768.0 )
        = k + k 2
    }
    ^ out
}

@ __srv_bytes_str ( Vec u ) b → String {
    : String st ( string_with_cap ( vec_len [u] b ) )
    : ~ i k 0
    ~ < k ( vec_len [u] b ) {
        ( string_push_char st ( vec_at [u] b k ) )
        = k + k 1
    }
    ^ st
}

// One stream's drafts so far: the last one (what `stable` is agreed
// against) and the last full-context one (which can be the final).
: WsDrafts {
    ( Vec u ) last
    ( Vec u ) full
    i full_seg
}

// The audio [from, to) of the stream, transcribed. `full` = the whole 30 s
// encoder context (a final, or a draft that may become one); otherwise the
// context covers the audio plus 5 s (at least 10 s) — a draft's price.
@ __srv_ws_run WsStream ws WsCfg wc i from i to b full ( Vec u ) text → b {
    : ( Vec f ) seg ( ws_stream_audio ws from to )
    : SrvCfg cf ( __srv_cfg )
    : ~ s lang ( string_data . cf lang )
    ? > ( string_len . wc lang ) 0 { = lang ( string_data . wc lang ) } {}
    : Whisper w ( __srv_model )
    : Tok t ( __srv_tok )
    : ~ i ctx 0
    : ~ f nosp g_srv_nospeech
    ? ! full {
        : i need / + ( vec_len [f] seg ) 319 320
        = ctx ? > + need 250 500 + need 250 500
        ? >= ctx ( wh_n_ctx_enc w ) { = ctx 0 } {}
        // the no-speech gate reads the full window; a shortened one is
        // not what it was calibrated on, and a draft is not the last word
        = nosp 1.0
    } {}
    ^ ( wh_run_seg w t seg ctx lang g_srv_max nosp text )
}

@ __srv_ws_failed TcpConn c → v {
    // The decode failed (an unknown language token, most likely) — SAY SO
    // on the socket. A client staring at silence cannot tell a failed
    // request from a quiet room, and "it just did nothing" is the worst
    // bug report there is.
    : Json eo ( json_obj_new )
    : b _e ( json_obj_set eo `error` ( json_str_lit `transcription failed — check the language code (lowercase: fi, en, sv, …); the server log has the detail` ) )
    ( __srv_ws_send c eo )
}

// One action of the endpointer, carried out.
@ __srv_ws_act TcpConn c i act inout WsStream ws WsCfg wc inout WsDrafts dr → v {
    : f t0 / # f . ws act_from 16000.0
    : f t1 / # f . ws act_to 16000.0
    ? == act WSS_START {
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `type` ( json_str_lit `start` ) )
        : b _b ( json_obj_set o `seg` ( json_int . ws act_seg ) )
        : b _c ( json_obj_set o `t0` ( json_float t0 ) )
        ( __srv_ws_send c o )
        ^ {}
    } {}
    ? == act WSS_LEVEL {
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `type` ( json_str_lit `level` ) )
        : b _b ( json_obj_set o `noise_db` ( json_float . ws noise_db ) )
        : b _c ( json_obj_set o `speech_db` ( json_float . ws speech_db ) )
        : b _d ( json_obj_set o `snr_db` ( json_float - . ws speech_db . ws noise_db ) )
        : b _e ( json_obj_set o `p_noise` ( json_float . ws p_noise ) )
        : b _f ( json_obj_set o `pause_ms` ( json_int . ws eou_ms ) )
        : b _g ( json_obj_set o `threshold` ( json_float . ws th_on ) )
        ( __srv_ws_send c o )
        ^ {}
    } {}
    : i t_start ( monotonic_ns )
    ? == act WSS_PARTIAL {
        : ( Vec u ) text ( vec_new [u] )
        ? ( __srv_ws_run ws wc . ws act_from . ws act_to . ws act_full text ) {} {
            ( __srv_ws_failed c )
            ^ {}
        }
        : i agree ( wss_agree . dr last text )
        : ( Vec u ) stable ( wss_prefix text agree )
        ? . ws act_full {
            = . dr full ( vec_clone [u] text )
            = . dr full_seg . ws act_seg
        } {}
        = . dr last ( vec_clone [u] text )
        // a speculative draft (no drafts asked for) is kept, not sent
        ? | == ( vec_len [u] text ) 0 ! . . wc st partials { ^ {} } {}
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `type` ( json_str_lit `partial` ) )
        : b _b ( json_obj_set o `seg` ( json_int . ws act_seg ) )
        : b _c ( json_obj_set o `text` ( json_str_lit ( string_data ( __srv_bytes_str text ) ) ) )
        : b _d ( json_obj_set o `stable` ( json_str_lit ( string_data ( __srv_bytes_str stable ) ) ) )
        : b _e ( json_obj_set o `t0` ( json_float t0 ) )
        : b _f ( json_obj_set o `t1` ( json_float t1 ) )
        : b _g ( json_obj_set o `pause_ms` ( json_int . ws act_pause_ms ) )
        : b _h ( json_obj_set o `proc_ms` ( json_int / - ( monotonic_ns ) t_start 1000000 ) )
        : b _i ( json_obj_set o `speech_t0` ( json_float / # f . ws act_speech_from 16000.0 ) )
        : b _j ( json_obj_set o `speech_t1` ( json_float / # f . ws act_speech_to 16000.0 ) )
        ( __srv_ws_send c o )
        ^ {}
    } {}
    // WSS_FINAL
    : ~ ( Vec u ) text ( vec_new [u] )
    : b drafted & . . wc st partials > ( vec_len [u] . dr last ) 0
    ? & . ws act_reuse == . dr full_seg . ws act_seg {
        = text ( vec_clone [u] . dr full )
    } {
        ? ( __srv_ws_run ws wc . ws act_from . ws act_to T text ) {} {
            ( __srv_ws_failed c )
            ( __srv_count )
            = . dr last ( vec_new [u] )
            = . dr full ( vec_new [u] )
            ^ {}
        }
    }
    = . dr last ( vec_new [u] )
    = . dr full ( vec_new [u] )
    = . dr full_seg 0
    ( __srv_count )
    // the gate ate it: the window held no speech (a phone mic's AGC pumping
    // room noise past the floor). Nothing to say, and saying nothing is the
    // right amount — unless drafts were shown, which an empty final clears.
    ? & == ( vec_len [u] text ) 0 ! | drafted . . wc st partials { ^ {} } {}
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `text` ( json_str_lit ( string_data ( __srv_bytes_str text ) ) ) )
    : b _b ( json_obj_set o `t0` ( json_float t0 ) )
    : b _c ( json_obj_set o `t1` ( json_float t1 ) )
    : b _d ( json_obj_set o `type` ( json_str_lit `final` ) )
    : b _e ( json_obj_set o `seg` ( json_int . ws act_seg ) )
    : b _f ( json_obj_set o `proc_ms` ( json_int / - ( monotonic_ns ) t_start 1000000 ) )
    : b _g ( json_obj_set o `speech_t0` ( json_float / # f . ws act_speech_from 16000.0 ) )
    : b _h ( json_obj_set o `speech_t1` ( json_float / # f . ws act_speech_to 16000.0 ) )
    ( __srv_ws_send c o )
}

// Everything the endpointer has due, in order.
@ __srv_ws_drain TcpConn c inout WsStream ws WsCfg wc inout WsDrafts dr → v {
    : ~ b more T
    ~ more {
        : i act ( ws_stream_next ws )
        ? == act WSS_NONE { = more F } { ( __srv_ws_act c act ws wc dr ) }
    }
}

// The upgrade hook: T = this was a WebSocket connection and it has been
// served to completion; F = not an upgrade, fall through to the router.
@ __srv_ws_hook TcpConn c HttpRequest rq → b {
    ? ( ws_is_upgrade rq ) {} { ^ F }
    // An unauthorized upgrade falls through to the ordinary handler: the
    // client asked for a 101 and gets a 401 page, which every WebSocket
    // implementation reports as a failed handshake.
    ? ( __srv_authed rq ) {} { ^ F }
    ?? ( ws_perform_handshake c rq ) {
        T _ → {}
        F _ → { ^ T }
    }
    // a stream holds the model for as long as it is open
    ? ( __srv_acquire ) {} {
        : !v WsErr _c ( ws_send_close c 1011 `the model could not be loaded` )
        ^ T
    }
    : ~ WsCfg wc @ WsCfg { F ( string_new ) ( wss_default_cfg ) T }
    : ~ WsStream ws ( ws_stream_new ( __srv_vad_net ) . wc st )
    : ~ WsDrafts dr @ WsDrafts { ( vec_new [u] ) ( vec_new [u] ) 0 }
    : WsLimits lim ( ws_default_limits )
    : ~ b open T
    ~ open {
        ?? ( ws_read_message c lim ) {
            T msg → {
                ? == . msg opcode ( ws_opcode_text ) {
                    : i cmd ( __srv_ws_text c . msg payload wc ws )
                    ? == cmd 1 {
                        : b _e ( ws_stream_end ws )
                    } {}
                    ? == cmd 2 {
                        ( ws_stream_reset ws )
                        = . dr last ( vec_new [u] )
                        = . dr full ( vec_new [u] )
                    } {}
                } {
                    ( ws_stream_feed ws ( __srv_ws_samples . msg payload . wc f32 ) )
                }
                ( __srv_ws_drain c ws wc dr )
            }
            F _ → { = open F }
        }
    }
    // the stream ended: an open utterance is still an utterance — transcribe
    // and send it before answering the close (RFC 6455 allows pending frames
    // before the close reply)
    : b _e ( ws_stream_end ws )
    ( __srv_ws_drain c ws wc dr )
    : !v WsErr _c ( ws_send_close c 1000 `bye` )
    ( __srv_release )
    ^ T
}

// The server proper, once a model and tokenizer are open — one body for
// both containers. Takes the model (the server owns it: an idle unload and
// a reload swap it); the caller keeps the tokenizer.
// cert/key: PEM paths — both set = HTTPS (and wss: the TcpConn's TLS is
// transparent to the WebSocket layer). Both empty = plain HTTP.
// The streams' voice detector: Silero's weights from `path` (or the
// installed ones), unless `energy` asks for the energy detector.
@ __srv_load_vad s path b energy → v {
    ? energy {
        ( nurl_eprintln `whisper: streams use the energy detector (--energy)` )
        ^ {}
    } {}
    : ~ String vp ( string_from path )
    ? == ( string_len vp ) 0 { = vp ( silero_default_path ) } {}
    ? == ( string_len vp ) 0 {
        ( nurl_eprintln `whisper: no Silero VAD weights (vad/silero_vad_v5.safetensors beside the install, or --vad-model) — streams fall back to the energy detector` )
        ^ {}
    } {}
    ?? ( silero_open ( string_data vp ) ) {
        T n → {
            ( locked_set [? Silero] g_srv_vad_net @ ?Silero { T n } )
            : String m ( string_from `whisper: streams segment with Silero VAD (` )
            ( string_push_str m ( string_data vp ) )
            ( string_push_char m 41 )
            ( nurl_eprintln ( string_data m ) )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( nurl_eprintln `whisper: streams fall back to the energy detector` )
        }
    }
}

@ __wh_serve_run sink Whisper w Tok t s dir s host i port s lang i maxtok b use_vad b with_ts s cert s key s token i unload_s s vad_model b energy → i {
    // the server owns the model from here
    ( locked_set [SrvState] g_srv @ SrvState { @ ?Whisper { T w } 0 0 ( monotonic_ns ) 1 0 0 * unload_s 1000 } )
    ( locked_set [? Tok] g_srv_tok @ ?Tok { T ( Tok_share t ) } )
    ( locked_set [SrvCfg] g_srv_cfg @ SrvCfg { ( string_from dir ) ( string_from lang ) ( string_from token ) } )
    ? > unload_s 0 {
        : ( @ v ) reaper \ → v { ( __srv_reaper ) }
        ?? ( thread_spawn_owned reaper ) {
            T th → { ( thread_detach th ) }
            F _ → {
                ( nurl_eprintln `whisper: cannot start the unload timer — the model stays loaded` )
                : ~ SrvState st ( locked_take [SrvState] g_srv )
                = . st unload_ms 0
                ( locked_restore [SrvState] g_srv st )
            }
        }
    } {}
    = g_srv_vad use_vad
    = g_srv_ts with_ts
    ( __srv_load_vad vad_model energy )
    = g_srv_max maxtok
    : HttpApp a ( http_app_new )
    // One inference runs one model on one GPU; a second concurrent request
    // would serialise on the model mutex anyway, so a single worker is the
    // honest shape (a WebSocket stream holds its worker for the connection's
    // life — that is the streaming contract). Production hardening layered
    // on top: bounded bodies, a header cap, and per-request deadlines so a
    // slow or hostile client cannot pin the one worker forever.
    ( http_app_workers a 1 )
    // a WAV is ~2 MB/min at 16 kHz pcm16; an hour ~115 MB
    ( http_app_body_max a 268435456 )
    // a request head past 64 KB is not a browser; refuse it before the body
    ( http_app_head_max a 65536 )
    // slowloris: a client that dribbles a request head past 30 s is dropped
    ( http_app_idle_ms a 30000 )
    // a whole request (upload + transcription) that outruns 10 minutes is a
    // stuck client or an hour of audio nobody is waiting for — reclaim the
    // worker. (0 would disable it; a real hour-long file transcribes in
    // seconds, so this only ever fires on a wedged connection.)
    ( http_app_request_timeout a 600000 )
    // one malformed request must never take the server down with it: a
    // handler panic becomes a 500, and the next request is served.
    ( http_app_recover a T )
    ( http_app_stream a \ TcpConn sc HttpRequest srq → b { ^ ( __srv_ws_hook sc srq ) } )
    ( http_app_post a `/inference` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_inference rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_health rq ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_page rq ) } )

    : b tls & > ( nurl_str_len cert ) 0 > ( nurl_str_len key ) 0
    : String msg ( string_from ? tls `whisper serving on https://` `whisper serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( string_push_str msg ` (test page at /, POST /inference, GET /health, WS: stream audio)` )
    ? > unload_s 0 {
        ( string_push_str msg `\nwhisper: the model is released after ` )
        ( string_push_int msg unload_s )
        ( string_push_str msg ` s idle and reloaded on the next request` )
    } {}
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )

    : ~ i rc 0
    ? tls {
        = rc ( http_app_listen_tls a host port cert key )
    } {
        = rc ( http_app_listen a host port )
    }

    // whichever model is loaded NOW is the one to close — the reaper may
    // have replaced the caller's `w` with nothing, or a reload with a new one
    : ~ SrvState st ( locked_take [SrvState] g_srv )
    = . st w @ ?Whisper { F }  // the server's owner, dropped here
    ( locked_restore [SrvState] g_srv st )
    ( locked_set [SrvCfg] g_srv_cfg @ SrvCfg { ( string_new ) ( string_new ) ( string_new ) } )
    ^ rc
}

// Load the model, open the port, serve until stopped.
@ wh_serve s dir s host i port s lang i maxtok b use_vad b with_ts s cert s key s token i unload_s s vad_model b energy → i {
    : String cfg ( _wh_path dir `config.json` )
    : String wts ( _wh_path dir `model.safetensors` )
    : String tjs ( _wh_path dir `tokenizer.json` )
    : ~ i rc 0

    // a whisper.cpp ggml container serves as itself: one file, no sidecars
    ? ( _wh_is_ggml dir ) {
        ?? ( wh_open_ggml dir ) {
            T w → {
                ?? ( wh_gg w ) {
                    T gg → {
                        ?? ( gg_build_tok gg ) {
                            T t → {
                                // the run owns the model from here: it closes
                                // whatever is loaded when it returns
                                : i rc2 ( __wh_serve_run w t dir host port lang maxtok use_vad with_ts cert key token unload_s vad_model energy )
                                ^ rc2
                            }
                            F e → {
                                ( nurl_eprintln ( string_data e ) )
                                ^ 1
                            }
                        }
                    }
                    F → { ^ 1 }
                }
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ^ 1
            }
        }
    } {}
    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                T w → {
                    : i rc2 ( __wh_serve_run w t dir host port lang maxtok use_vad with_ts cert key token unload_s vad_model energy )
                    = rc rc2
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    = rc 1
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            = rc 1
        }
    }
    ^ rc
}
