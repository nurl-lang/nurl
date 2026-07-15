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
$ `deps/http/src/http.nu`

: ~ i g_srv_w 0  // *Whisper, as an address (0 = not serving)
: ~ i g_srv_t 0  // *Tok
: ~ i g_srv_reqs 0
: ~ s g_srv_lang ``
: ~ b g_srv_vad F
: ~ b g_srv_ts F
: ~ i g_srv_max 0

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
    ( vec_free [u] b )
    ^ out
}

@ __srv_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( json_free o )
    ^ r
}

// The transcription itself, after the request has been picked apart.
// Owns `wav`; frees it.
@ __srv_run ( Vec u ) wav s lang b use_vad b with_ts b as_text → HttpResponse {
    ?? ( wav_parse wav ) {
        T aw → {
            ( vec_free [u] wav )
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) at16 ( resample mono . aw rate 16000 )
            ( wav_free aw )
            ( vec_free [f] mono )

            : *Whisper w # *Whisper g_srv_w
            : *Tok t # *Tok g_srv_t
            : ( Vec u ) text ( vec_new [u] )
            ? ( wh_run w t at16 lang g_srv_max use_vad with_ts text ) {
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
                ( vec_free [u] text )
                ? as_text {
                    : HttpResponse r ( response_text 200 ( string_data st ) )
                    ( string_free st )
                    ^ r
                } {}
                : Json o ( json_obj_new )
                : b _s ( json_obj_set o `text` ( json_str_lit ( string_data st ) ) )
                : HttpResponse r ( response_json 200 o )
                ( json_free o )
                ( string_free st )
                ^ r
            } {}
            ( vec_free [u] text )
            ^ ( __srv_err 500 `decode failed (is this a whisper tokenizer.json?)` )
        }
        F e → {
            ( vec_free [u] wav )
            : HttpResponse r ( __srv_err 400 ( string_data e ) )
            ( string_free e )
            ^ r
        }
    }
}

// POST /inference — the whisper.cpp endpoint.
@ __srv_inference HttpRequest req → HttpResponse {
    ? == g_srv_w 0 { ^ ( __srv_err 503 `no model loaded` ) } {}
    = g_srv_reqs + g_srv_reqs 1

    ?? ( request_multipart_parts req ) {
        T parts → {
            : ( Vec u ) wav ( __srv_part_bytes parts `file` )
            : String lang_s ( __srv_field_str parts `language` )
            : String fmt_s ( __srv_field_str parts `response_format` )
            : String vad_s ( __srv_field_str parts `vad` )
            : String ts_s ( __srv_field_str parts `timestamps` )
            ( multipart_parts_free parts )
            ? == 0 ( vec_len [u] wav ) {
                ( vec_free [u] wav )
                ( string_free lang_s ) ( string_free fmt_s )
                ( string_free vad_s ) ( string_free ts_s )
                ^ ( __srv_err 400 `multipart form has no 'file' field` )
            } {}
            : ~ s lang g_srv_lang
            ? > ( string_len lang_s ) 0 { = lang ( string_data lang_s ) } {}
            : b vs ? ( nurl_str_eq ( string_data vad_s ) `true` ) T F
            : b ts2 ? ( nurl_str_eq ( string_data ts_s ) `true` ) T F
            : b use_vad | g_srv_vad vs
            : b with_ts | g_srv_ts ts2
            : b as_text ? ( nurl_str_eq ( string_data fmt_s ) `text` ) T F
            : HttpResponse r ( __srv_run wav lang use_vad with_ts as_text )
            ( string_free lang_s ) ( string_free fmt_s )
            ( string_free vad_s ) ( string_free ts_s )
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
    ^ ( __srv_run wav g_srv_lang g_srv_vad g_srv_ts F )
}

// GET / — the built-in test page: upload a file, or stream the microphone
// over the same port's WebSocket. Embedded (src/page_data.nu) so an
// installed binary needs nothing on disk.
@ __srv_page HttpRequest req → HttpResponse {
    : ~ String body ( string_with_cap 10240 )
    : i nch ( wh_page_chunks )
    : ~ i c 0
    ~ < c nch {
        ( string_push_str body ( wh_page_chunk c ) )
        = c + c 1
    }
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_body_str r ( string_data body ) )
    ( string_free body )
    ^ r
}

@ __srv_health HttpRequest req → HttpResponse {
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `status` ( json_str_lit ? == g_srv_w 0 `loading` `ok` ) )
    ? != g_srv_w 0 {
        : *Whisper w # *Whisper g_srv_w
        : b _b ( json_obj_set o `d_model` ( json_int . w d_model ) )
        : b _c ( json_obj_set o `n_mels` ( json_int . w n_mels ) )
        : b _d ( json_obj_set o `encoder_layers` ( json_int . w n_enc_layer ) )
        : b _e ( json_obj_set o `decoder_layers` ( json_int . w n_dec_layer ) )
    } {}
    : b _f ( json_obj_set o `requests` ( json_int g_srv_reqs ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
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

: ~ i g_ws_f32 0  // 1 = client sends float32 frames, else PCM16
: ~ s g_ws_lang ``  // per-connection language override (`` = server default)

@ __srv_ws_ack TcpConn c → v {
    : Json o ( json_obj_new )
    : b _a ( json_obj_set o `status` ( json_str_lit `ok` ) )
    : b _b ( json_obj_set o `format` ( json_str_lit ? != g_ws_f32 0 `float32` `pcm16` ) )
    : b _c ( json_obj_set o `vad` ( json_str_lit `adaptive-floor` ) )
    : String body ( json_stringify o )
    : !v WsErr _w ( ws_send_text c ( string_data body ) )
    ( string_free body )
    ( json_free o )
}

@ __srv_ws_config TcpConn c ( Vec u ) payload → v {
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
                    = g_ws_f32 ? ( nurl_str_eq fs `float32` ) 1 0
                }
                F → {}
            }
            ?? ( json_obj_get j `lang` ) {
                T v → {
                    : s ls ( json_as_str v )
                    ? > ( nurl_str_len ls ) 0 {
                        ? > ( nurl_str_len g_ws_lang ) 0 { ( nurl_free g_ws_lang ) } {}
                        = g_ws_lang ( strdup ls )
                    } {}
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ( string_free ps )
    ( __srv_ws_ack c )
}

// binary frame → f32 samples at 16 kHz (the client's job to resample; a
// microphone opened at 16 kHz is the normal case)
@ __srv_ws_samples ( Vec u ) d → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : i n ( vec_len [u] d )
    ? != g_ws_f32 0 {
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
@ __srv_ws_emit TcpConn c * VadStream vs → v {
    : VadSeg g ( vad_stream_seg vs )
    : ( Vec f ) seg ( vad_stream_take vs )
    : ~ s lang g_srv_lang
    ? > ( nurl_str_len g_ws_lang ) 0 { = lang g_ws_lang } {}
    : *Whisper w # *Whisper g_srv_w
    : *Tok t # *Tok g_srv_t
    : ( Vec u ) text ( vec_new [u] )
    // no VAD inside — the stream already segmented; no timestamps — the
    // segment IS the timestamp, and t0/t1 carry it
    ? ( wh_run w t seg lang g_srv_max F F text ) {
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
        ( string_free body )
        ( json_free o )
        ( string_free st )
    } {}
    ( vec_free [u] text )
    = g_srv_reqs + g_srv_reqs 1
}

// The upgrade hook: T = this was a WebSocket connection and it has been
// served to completion; F = not an upgrade, fall through to the router.
@ __srv_ws_hook TcpConn c HttpRequest rq → b {
    ? ( ws_is_upgrade rq ) {} { ^ F }
    ?? ( ws_perform_handshake c rq ) {
        T _ → {}
        F _ → { ^ T }
    }
    = g_ws_f32 0
    ? > ( nurl_str_len g_ws_lang ) 0 { ( nurl_free g_ws_lang ) } {}
    = g_ws_lang ``
    : *VadStream vs ( vad_stream_new 16000 ( vad_default_opts ) )
    : WsLimits lim ( ws_default_limits )
    : ~ b open T
    ~ open {
        ?? ( ws_read_message c lim ) {
            T msg → {
                ? == . msg opcode ( ws_opcode_text ) {
                    ( __srv_ws_config c . msg payload )
                } {
                    : ( Vec f ) x ( __srv_ws_samples . msg payload )
                    ( vad_stream_push vs x )
                    ( vec_free [f] x )
                    ~ ( vad_stream_poll vs ) { ( __srv_ws_emit c vs ) }
                }
                ( vec_free [u] . msg payload )
            }
            F _ → { = open F }
        }
    }
    // the stream ended: an open utterance is still an utterance — transcribe
    // and send it before answering the close (RFC 6455 allows pending frames
    // before the close reply)
    ? ( vad_stream_flush vs ) { ( __srv_ws_emit c vs ) } {}
    : !v WsErr _c ( ws_send_close c 1000 `bye` )
    ( vad_stream_free vs )
    ? > ( nurl_str_len g_ws_lang ) 0 { ( nurl_free g_ws_lang ) } {}
    = g_ws_lang ``
    ^ T
}

// The server proper, once a model and tokenizer are open — one body for
// both containers. Owns neither; the caller closes them.
@ __wh_serve_run * Whisper w * Tok t s host i port s lang i maxtok b use_vad b with_ts → i {
    = g_srv_w # i w
    = g_srv_t # i t
    = g_srv_lang ( strdup lang )
    = g_srv_vad use_vad
    = g_srv_ts with_ts
    = g_srv_max maxtok

    : *HttpApp a ( http_app_new )
    ( http_app_workers a 1 )
    // a WAV is ~2 MB/min at 16 kHz pcm16; an hour ~115 MB
    ( http_app_body_max a 268435456 )
    ( http_app_stream a \ TcpConn sc HttpRequest srq → b { ^ ( __srv_ws_hook sc srq ) } )
    ( http_app_post a `/inference` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_inference rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_health rq ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_page rq ) } )

    : String msg ( string_from `whisper serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( string_push_str msg ` (test page at /, POST /inference, GET /health, WS: stream audio)` )
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )
    ( string_free msg )

    : i rc ( http_app_listen a host port )

    = g_srv_w 0
    = g_srv_t 0
    ( nurl_free g_srv_lang )
    = g_srv_lang ``
    ^ rc
}

// Load the model, open the port, serve until stopped.
@ wh_serve s dir s host i port s lang i maxtok b use_vad b with_ts → i {
    : String cfg ( _wh_path dir `config.json` )
    : String wts ( _wh_path dir `model.safetensors` )
    : String tjs ( _wh_path dir `tokenizer.json` )
    : ~ i rc 0

    // a whisper.cpp ggml container serves as itself: one file, no sidecars
    ? ( __wh_is_ggml dir ) {
        ( string_free cfg ) ( string_free wts ) ( string_free tjs )
        ?? ( wh_open_ggml dir ) {
            T w → {
                ?? ( gg_build_tok # *Gg . w gg ) {
                    T t → {
                        : i rc2 ( __wh_serve_run w t host port lang maxtok use_vad with_ts )
                        ( tok_free t )
                        ( wh_close w )
                        ^ rc2
                    }
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        ( string_free e )
                        ( wh_close w )
                        ^ 1
                    }
                }
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ( string_free e )
                ^ 1
            }
        }
    } {}
    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                T w → {
                    : i rc2 ( __wh_serve_run w t host port lang maxtok use_vad with_ts )
                    = rc rc2
                    ( wh_close w )
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    = rc 1
                }
            }
            ( tok_free t )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ( string_free cfg ) ( string_free wts ) ( string_free tjs )
    ^ rc
}
