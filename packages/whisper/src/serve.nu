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

// Load the model, open the port, serve until stopped.
@ wh_serve s dir s host i port s lang i maxtok b use_vad b with_ts → i {
    : String cfg ( __wh_path dir `config.json` )
    : String wts ( __wh_path dir `model.safetensors` )
    : String tjs ( __wh_path dir `tokenizer.json` )
    : ~ i rc 0

    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                T w → {
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
                    ( http_app_post a `/inference` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_inference rq ) } )
                    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_health rq ) } )
                    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __srv_health rq ) } )

                    : String msg ( string_from `whisper serving on http://` )
                    ( string_push_str msg host )
                    ( string_push_char msg 58 )
                    ( string_push_int msg port )
                    ( string_push_str msg ` (POST /inference, GET /health)` )
                    ( nurl_print ( string_data msg ) )
                    ( nurl_print `\n` )
                    ( string_free msg )

                    = rc ( http_app_listen a host port )

                    = g_srv_w 0
                    = g_srv_t 0
                    ( nurl_free g_srv_lang )
                    = g_srv_lang ``
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
