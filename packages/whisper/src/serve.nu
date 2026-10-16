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
// audio (binary frames: PCM16 by default, or float32 — announce with a first
// JSON text message {"format":"float32"}) and receives one JSON text message
// per UTTERANCE:
//
//   {"text":" ...","t0":12.34,"t1":15.67}
//
// t0/t1 are seconds on the STREAM's clock — where in everything sent so far
// the words were said.
//
// Segmentation is the adaptive-floor streaming VAD (packages/audio). The
// whisper.cpp fork this replaces cuts on a FIXED dB threshold and then grows a
// pile of "auto settings" heuristics to keep re-tuning that threshold per
// room — the adaptive floor (10th percentile of the trailing minute) is the
// shape of the fix rather than a patch on the symptom. And it runs on one
// port, not two: the fork needs a second listener because its HTTP and WS
// stacks cannot share one, and ours are the same stack by construction.

// One stream's settings, from its config messages. They belong to the
// connection: as globals, two streams open at once took each other's
// sample format and language (and one could free the language string the
// other was transcribing with).
: WsCfg {
    b f32  // the client sends float32 frames, else PCM16
    String lang  // the language override ("" = the server's default)
}

@ __srv_ws_ack TcpConn c WsCfg wc → v {
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `status` ( json_str_lit `ok` ) )
    : b _b ( json_obj_set o `format` ( json_str_lit ? . wc f32 `float32` `pcm16` ) )
    : b _c ( json_obj_set o `vad` ( json_str_lit `adaptive-floor` ) )
    : String body ( json_stringify o )
    : !v WsErr _w ( ws_send_text c ( string_data body ) )
}

@ __srv_ws_config TcpConn c ( Vec u ) payload inout WsCfg wc → v {
    : String ps ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [u] payload ) {
        ?? ( vec_get [u] payload k ) {
            T ch → { ( string_push_char ps ch ) }
            F → {}
        }
        = k + k 1
    }
    ?? ( json_parse ( string_data ps ) ) {
        T j → {
            ?? ( json_obj_get j `format` ) {
                T v → {
                    : s fs ( json_as_str v )
                    = . wc f32 != 0 ( nurl_str_eq fs `float32` )
                }
                F → {}
            }
            ?? ( json_obj_get j `lang` ) {
                T v → {
                    : s ls ( json_as_str v )
                    ? > ( nurl_str_len ls ) 0 {
                        = . wc lang ( string_from ls )
                    } {}
                }
                F → {}
            }
        }
        F _ → {}
    }
    ( __srv_ws_ack c wc )
}

// binary frame → f32 samples at 16 kHz (the client's job to resample; a
// microphone opened at 16 kHz is the normal case)
@ __srv_ws_samples ( Vec u ) d b f32 → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : i n ( vec_len [u] d )
    ? f32 {
        : ~ i k 0
        ~ <= + k 4 n {
            : ~ i b0 0
            : ~ i b1 0
            : ~ i b2 0
            : ~ i b3 0
            ?? ( vec_get [u] d k ) { T x0 → { = b0 # i x0 } F → {} }
            ?? ( vec_get [u] d + k 1 ) { T x1 → { = b1 # i x1 } F → {} }
            ?? ( vec_get [u] d + k 2 ) { T x2 → { = b2 # i x2 } F → {} }
            ?? ( vec_get [u] d + k 3 ) { T x3 → { = b3 # i x3 } F → {} }
            : i bits | | | b0 << b1 8 << b2 16 << b3 24
            ( vec_push [f] out # f ( bits_to_f32 bits ) )
            = k + k 4
        }
        ^ out
    } {}
    : ~ i k 0
    ~ <= + k 2 n {
        : ~ i lo 0
        : ~ i hi 0
        ?? ( vec_get [u] d k ) { T xl → { = lo # i xl } F → {} }
        ?? ( vec_get [u] d + k 1 ) { T xh → { = hi # i xh } F → {} }
        : ~ i v | lo << hi 8
        ? >= v 32768 { = v - v 65536 } {}
        ( vec_push [f] out / # f v 32768.0 )
        = k + k 2
    }
    ^ out
}

// A closed utterance: transcribe it, send {"text","t0","t1"}.
@ __srv_ws_emit TcpConn c VadStream vs WsCfg wc → v {
    : VadSeg g ( vad_stream_seg vs )
    : ( Vec f ) seg ( vad_stream_take vs )
    : SrvCfg cf ( __srv_cfg )
    : ~ s lang ( string_data . cf lang )
    ? > ( string_len . wc lang ) 0 { = lang ( string_data . wc lang ) } {}
    : Whisper w ( __srv_model )
    : Tok t ( __srv_tok )
    : ( Vec u ) text ( vec_new [u] )
    // no VAD inside — the stream already segmented; no timestamps — the
    // segment IS the timestamp, and t0/t1 carry it
    ? ( wh_run w t seg lang g_srv_max F F g_srv_nospeech text ) {
        // the gate ate it: the window held no speech (a phone mic's AGC
        // pumping room noise past the energy floor). Nothing to say, and
        // saying nothing is the right amount.
        ? == ( vec_len [u] text ) 0 {
            ( __srv_count )
            ^ {}
        } {}
        : String st ( string_new )
        : ~ i k 0
        ~ < k ( vec_len [u] text ) {
            ?? ( vec_get [u] text k ) {
                T ch → { ( string_push_char st ch ) }
                F → {}
            }
            = k + k 1
        }
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `text` ( json_str_lit ( string_data st ) ) )
        : b _b ( json_obj_set o `t0` ( json_float / # f . g start 16000.0 ) )
        : b _c ( json_obj_set o `t1` ( json_float / # f . g end 16000.0 ) )
        : String body ( json_stringify o )
        : !v WsErr _w ( ws_send_text c ( string_data body ) )
    } {
        // The decode failed (an unknown language token, most likely) —
        // SAY SO on the socket. A client staring at silence cannot tell a
        // failed request from a quiet room, and "it just did nothing" is
        // the worst bug report there is.
        : Json eo ( json_obj_new )
        : b _e ( json_obj_set eo `error` ( json_str_lit `transcription failed — check the language code (lowercase: fi, en, sv, …); the server log has the detail` ) )
        : String eb ( json_stringify eo )
        : !v WsErr _we ( ws_send_text c ( string_data eb ) )
    }
    ( __srv_count )
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
    : ~ WsCfg wc @ WsCfg { F ( string_new ) }
    : VadStream vs ( vad_stream_new 16000 ( vad_default_opts ) )
    : WsLimits lim ( ws_default_limits )
    : ~ b open T
    ~ open {
        ?? ( ws_read_message c lim ) {
            T msg → {
                ? == . msg opcode ( ws_opcode_text ) {
                    ( __srv_ws_config c . msg payload wc )
                } {
                    : ( Vec f ) x ( __srv_ws_samples . msg payload . wc f32 )
                    ( vad_stream_push vs x )
                    ~ ( vad_stream_poll vs ) { ( __srv_ws_emit c vs wc ) }
                }
            }
            F _ → { = open F }
        }
    }
    // the stream ended: an open utterance is still an utterance — transcribe
    // and send it before answering the close (RFC 6455 allows pending frames
    // before the close reply)
    ? ( vad_stream_flush vs ) { ( __srv_ws_emit c vs wc ) } {}
    : !v WsErr _c ( ws_send_close c 1000 `bye` )
    ( __srv_release )
    ^ T
}

// The server proper, once a model and tokenizer are open — one body for
// both containers. Takes the model (the server owns it: an idle unload and
// a reload swap it); the caller keeps the tokenizer.
// cert/key: PEM paths — both set = HTTPS (and wss: the TcpConn's TLS is
// transparent to the WebSocket layer). Both empty = plain HTTP.
@ __wh_serve_run sink Whisper w Tok t s dir s host i port s lang i maxtok b use_vad b with_ts s cert s key s token i unload_s → i {
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
@ wh_serve s dir s host i port s lang i maxtok b use_vad b with_ts s cert s key s token i unload_s → i {
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
                                : i rc2 ( __wh_serve_run w t dir host port lang maxtok use_vad with_ts cert key token unload_s )
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
                    : i rc2 ( __wh_serve_run w t dir host port lang maxtok use_vad with_ts cert key token unload_s )
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
