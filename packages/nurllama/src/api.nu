// packages/nurllama/src/api.nu — an ollama-compatible HTTP API.
//
// Speaks enough of ollama's wire protocol that existing clients work
// unchanged:
//
//   POST /api/generate   { model, prompt, stream?, options? }
//   POST /api/chat       { model, messages[{role,content}], stream?, options? }
//        → NDJSON: one JSON object per token while generating, then a
//          final object with done:true (+ token counts). stream:false
//          returns a single aggregated object.
//   GET  /api/tags       the local store, as ollama's model list
//   POST /api/show       { model } → the model's metadata
//   GET  /                "nurllama is running"
//
// Streaming rides the http package's stream hook (http_app_stream):
// the handler owns the TcpConn and writes chunked NDJSON itself, so a
// token reaches the client the moment it is decoded.
//
// One model is resident at a time (LRU of one): a request naming a
// different model swaps it in. Generation is serialised — the decode
// loop owns the device — which is honest for a single-GPU host; the
// server is single-worker so that serialisation is structural rather
// than a lock.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `deps/gguf/src/gguf.nu`
$ `src/tokenizer.nu`
$ `src/model.nu`
$ `src/diffuse.nu`
$ `src/sample.nu`
$ `src/chat.nu`
$ `src/store.nu`

// The resident model + the store root, reachable from the handlers.
// Globals may only carry scalar/`s` literals, so the two strings are
// plain owned C-strings (strdup'd in, nurl_free'd out) rather than
// String structs.
: ~ i g_api_llm 0
: ~ i g_api_style 0
: ~ s g_api_name ``
: ~ s g_api_root ``

@ __api_set_name s name → v {
    ? != 0 ( nurl_str_len g_api_name ) { ( nurl_free g_api_name ) } {}
    = g_api_name ( strdup name )
}

@ api_set_root String root → v {
    ? != 0 ( nurl_str_len g_api_root ) { ( nurl_free g_api_root ) } {}
    = g_api_root ( strdup ( string_data root ) )
}

@ __api_unload → v {
    ? != g_api_llm 0 {
        ( llm_close # *Llm g_api_llm )
        = g_api_llm 0
    } {}
    ? != 0 ( nurl_str_len g_api_name ) {
        ( nurl_free g_api_name )
        = g_api_name ``
    } {}
}

// Load `name` unless it is already resident. Empty error = success.
@ __api_ensure s name → String {
    ? & != g_api_llm 0 != 0 ( nurl_str_eq g_api_name name ) { ^ ( string_new ) } {}
    ( __api_unload )
    : String rootS ( string_from g_api_root )
    : ?String rp ( nl_resolve rootS name )
    ( string_free rootS )
    ?? rp {
        T path → {
            // the chat style comes from the model's own metadata
            : ~ i style CHAT_PLAIN
            ?? ( gguf_open ( string_data path ) ) {
                T gg → {
                    = style ( chat_style_of gg )
                    ( gguf_close gg )
                }
                F e → { ( string_free e ) }
            }
            : !*Llm String lr ( llm_open ( string_data path ) 0 )
            ( string_free path )
            ?? lr {
                T m → {
                    = g_api_llm # i m
                    = g_api_style style
                    ( __api_set_name name )
                    ^ ( string_new )
                }
                F e → { ^ e }
            }
        }
        F → {
            : String msg ( string_from `model '` )
            ( string_push_str msg name )
            ( string_push_str msg `' not found — pull it first` )
            ^ msg
        }
    }
}

// ── request-body helpers ────────────────────────────────────────────

@ __api_body_json HttpRequest req → !Json JsonError {
    : String txt ( bytes_to_str . req body )
    : !Json JsonError r ( json_parse ( string_data txt ) )
    ( string_free txt )
    ^ r
}

@ __api_str Json j s key s def → String {
    ?? ( json_obj_get j key ) {
        T v → { ^ ( string_from ( json_str_data v ) ) }
        F → { ^ ( string_from def ) }
    }
}

@ __api_bool Json j s key b def → b {
    ?? ( json_obj_get j key ) {
        T v → { ^ ? ( json_is_bool v ) ( json_bool_val v ) def }
        F → { ^ def }
    }
}

// options.<key>, ollama's nesting
@ __api_opt_i Json j s key i def → i {
    ?? ( json_obj_get j `options` ) {
        T o → {
            ?? ( json_obj_get o key ) {
                T v → {
                    ?? ( json_num_as_i v ) {
                        T n → { ^ n }
                        F → { ^ def }
                    }
                }
                F → { ^ def }
            }
        }
        F → { ^ def }
    }
}

@ __api_opt_f Json j s key f def → f {
    ?? ( json_obj_get j `options` ) {
        T o → {
            ?? ( json_obj_get o key ) {
                T v → {
                    ?? ( json_num_as_f v ) {
                        T x → { ^ x }
                        F → { ^ def }
                    }
                }
                F → { ^ def }
            }
        }
        F → { ^ def }
    }
}

// ── NDJSON frames ───────────────────────────────────────────────────

@ __api_frame_token s model s field s piece → String {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `model` ( json_str_lit model ) )
    ? ( nurl_str_eq field `response` ) {
        : b _2 ( json_obj_set j `response` ( json_str_lit piece ) )
    } {
        : Json msg ( json_obj_new )
        : b _3 ( json_obj_set msg `role` ( json_str_lit `assistant` ) )
        : b _4 ( json_obj_set msg `content` ( json_str_lit piece ) )
        : b _5 ( json_obj_set j `message` msg )
    }
    : b _6 ( json_obj_set j `done` ( json_bool F ) )
    : String out ( json_stringify j )
    ( json_free j )
    ( string_push_char out 10 )
    ^ out
}

@ __api_frame_done s model s field i nprompt i neval b with_text s full → String {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `model` ( json_str_lit model ) )
    ? ( nurl_str_eq field `response` ) {
        : b _2 ( json_obj_set j `response` ( json_str_lit ? with_text full `` ) )
    } {
        : Json msg ( json_obj_new )
        : b _3 ( json_obj_set msg `role` ( json_str_lit `assistant` ) )
        : b _4 ( json_obj_set msg `content` ( json_str_lit ? with_text full `` ) )
        : b _5 ( json_obj_set j `message` msg )
    }
    : b _6 ( json_obj_set j `done` ( json_bool T ) )
    : b _7 ( json_obj_set j `done_reason` ( json_str_lit `stop` ) )
    : b _8 ( json_obj_set j `prompt_eval_count` ( json_int nprompt ) )
    : b _9 ( json_obj_set j `eval_count` ( json_int neval ) )
    : String out ( json_stringify j )
    ( json_free j )
    ( string_push_char out 10 )
    ^ out
}

@ __api_write_str TcpConn c String s → b {
    : ( Vec u ) b2 ( bytes_from_str ( string_data s ) )
    : !v NetErr r ( response_write_chunk c b2 )
    ( vec_free [u] b2 )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ^ ok
}

@ __api_begin_ndjson TcpConn c → b {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Content-Type` `application/x-ndjson` ) )
    : !v NetErr r ( response_begin_chunked c 200 hs )
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ^ ok
}

@ __api_error_chunked TcpConn c i status s msg → b {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Content-Type` `application/json` ) )
    : !v NetErr r ( response_begin_chunked c status hs )
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    ?? r { T _ → {} F _ → { ^ T } }
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `error` ( json_str_lit msg ) )
    : String txt ( json_stringify j )
    ( json_free j )
    ( string_push_char txt 10 )
    : b _w ( __api_write_str c txt )
    ( string_free txt )
    : !v NetErr _e ( response_end_chunked c )
    ^ T
}

// ── the generation core, shared by /api/generate and /api/chat ──────
//
// Streams NDJSON frames as tokens decode (stream=true), or accumulates
// and answers with a single object (stream=false).
@ __api_generate TcpConn c s model String prompt s field b stream
i npredict f temp i topk f topp i seed → b {
    : *Llm m # *Llm g_api_llm
    : *Tok t ( llm_tok m )
    : ( Vec i ) ids ( tok_encode t ( string_data prompt ) T )
    : i nprompt ( vec_len [i] ids )
    ? > nprompt ( llm_n_ctx m ) {
        ( vec_free [i] ids )
        ^ ( __api_error_chunked c 400 `prompt is longer than the model's context` )
    } {}
    ? stream { ? ( __api_begin_ndjson c ) {} { ( vec_free [i] ids ) ^ T } } {}

    // Diffusion model: the block-denoise loop produces the whole
    // response (src/diffuse.nu); a streaming client then receives the
    // pieces as ordinary token frames, just all at once.
    ? ( llm_is_diffusion m ) {
        : Rng drng ( rng_seed seed )
        : ( Vec i ) gen ( dz_generate m ids npredict 32 0.7 0.5 16 temp drng )
        ( rng_free drng )
        ( vec_free [i] ids )
        : String dfull ( string_new )
        : ~ b dbroken F
        : ~ i gi 0
        ~ < gi ( vec_len [i] gen ) {
            : ~ i gid 0
            ?? ( vec_get [i] gen gi ) { T x → { = gid x } F → {} }
            : ( Vec u ) pb ( tok_piece t gid )
            : String piece ( bytes_to_str pb )
            ( vec_free [u] pb )
            ( string_push_str dfull ( string_data piece ) )
            ? & stream ! dbroken {
                : String fr ( __api_frame_token model field ( string_data piece ) )
                ? ( __api_write_str c fr ) {} { = dbroken T }
                ( string_free fr )
            } {}
            ( string_free piece )
            = gi + gi 1
        }
        : i dproduced ( vec_len [i] gen )
        ( vec_free [i] gen )
        ? dbroken {
            ( string_free dfull )
            ^ T
        } {}
        ? stream {} { ? ( __api_begin_ndjson c ) {} { ( string_free dfull ) ^ T } }
        : String dfin ( __api_frame_done model field nprompt dproduced ! stream ( string_data dfull ) )
        : b _dw ( __api_write_str c dfin )
        ( string_free dfin )
        ( string_free dfull )
        : !v NetErr _de ( response_end_chunked c )
        ^ T
    } {}

    ( llm_prefill m ids )
    ( vec_free [i] ids )

    : Rng rng ( rng_seed seed )
    : String full ( string_new )
    : ~ i pos nprompt
    : ~ i produced 0
    : ~ b stop F
    : ~ b broken F
    ~ & & & < produced npredict < pos ( llm_n_ctx m ) ! stop ! broken {
        : i nt ( sample_next m rng temp topk topp )
        ? == nt ( tok_eos t ) { = stop T } {
            : ( Vec u ) pb ( tok_piece t nt )
            : String piece ( bytes_to_str pb )
            ( vec_free [u] pb )
            // a chat dialect's terminator may arrive as plain text
            ? ( chat_stop_matches g_api_style ( string_data piece ) ) { = stop T } {
                ( string_push_str full ( string_data piece ) )
                ? stream {
                    : String fr ( __api_frame_token model field ( string_data piece ) )
                    ? ( __api_write_str c fr ) {} { = broken T }
                    ( string_free fr )
                } {}
                ( llm_eval m nt pos )
                = pos + pos 1
                = produced + produced 1
            }
            ( string_free piece )
        }
    }

    ( rng_free rng )
    ? broken {
        ( string_free full )
        ^ T
    } {}
    ? stream {} { ? ( __api_begin_ndjson c ) {} { ( string_free full ) ^ T } }
    : String fin ( __api_frame_done model field nprompt produced ! stream ( string_data full ) )
    : b _w ( __api_write_str c fin )
    ( string_free fin )
    ( string_free full )
    : !v NetErr _e ( response_end_chunked c )
    ^ T
}

// ── the stream hook: /api/generate + /api/chat ──────────────────────

@ __api_stream_hook TcpConn c HttpRequest req → b {
    : s path ( string_data . req path )
    : b is_gen ? ( nurl_str_eq path `/api/generate` ) T F
    : b is_chat ? ( nurl_str_eq path `/api/chat` ) T F
    ? | is_gen is_chat {} { ^ F }
    ? ( nurl_str_eq ( string_data . req method ) `POST` ) {} { ^ F }

    : !Json JsonError pj ( __api_body_json req )
    ?? pj {
        F _ → { ^ ( __api_error_chunked c 400 `invalid JSON body` ) }
        T j → {
            : String model ( __api_str j `model` `` )
            ? > ( string_len model ) 0 {} {
                ( string_free model )
                ( json_free j )
                ^ ( __api_error_chunked c 400 `missing "model"` )
            }
            : String lerr ( __api_ensure ( string_data model ) )
            ? > ( string_len lerr ) 0 {
                : b r ( __api_error_chunked c 404 ( string_data lerr ) )
                ( string_free lerr )
                ( string_free model )
                ( json_free j )
                ^ r
            } {}
            ( string_free lerr )

            // prompt: /api/generate takes it verbatim; /api/chat renders
            // the message list through the model's own chat template
            : ~ String prompt ( string_new )
            ? is_gen {
                ( string_free prompt )
                = prompt ( __api_str j `prompt` `` )
            } {
                : ( Vec ChatMsg ) msgs ( vec_new [ChatMsg] )
                ?? ( json_obj_get j `messages` ) {
                    T arr → {
                        : ~ i k 0
                        ~ < k ( json_arr_len arr ) {
                            ?? ( json_arr_get arr k ) {
                                T mo → {
                                    : String role ( __api_str mo `role` `user` )
                                    : String content ( __api_str mo `content` `` )
                                    ( vec_push [ChatMsg] msgs ( chat_msg ( string_data role ) ( string_data content ) ) )
                                    ( string_free role )
                                    ( string_free content )
                                }
                                F → {}
                            }
                            = k + k 1
                        }
                    }
                    F → {}
                }
                ( string_free prompt )
                = prompt ( chat_render g_api_style msgs )
                ( chat_msgs_free msgs )
            }

            : b stream ( __api_bool j `stream` T )
            : i npredict ( __api_opt_i j `num_predict` 128 )
            : f temp ( __api_opt_f j `temperature` 0.8 )
            : i topk ( __api_opt_i j `top_k` 40 )
            : f topp ( __api_opt_f j `top_p` 0.95 )
            : i seed ( __api_opt_i j `seed` 42 )
            : s field ? is_gen `response` `message`
            : b r ( __api_generate c ( string_data model ) prompt field stream npredict temp topk topp seed )
            ( string_free prompt )
            ( string_free model )
            ( json_free j )
            ^ r
        }
    }
}

// ── plain JSON routes ───────────────────────────────────────────────

@ __api_tags HttpRequest req Params ps → HttpResponse {
    : Json arr ( json_arr_new )
    : String rootS ( string_from g_api_root )
    : String mdir ( path_join g_api_root `manifests` )
    ?? ( dir_list ( string_data mdir ) ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : Json o ( json_obj_new )
                        : b _1 ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
                        : b _2 ( json_obj_set o `model` ( json_str_lit ( string_data nm ) ) )
                        : ~ i sz 0
                        ?? ( nl_resolve rootS ( string_data nm ) ) {
                            T bp → {
                                ?? ( file_size ( string_data bp ) ) {
                                    T n → { = sz n }
                                    F _ → {}
                                }
                                ( string_free bp )
                            }
                            F → {}
                        }
                        : b _3 ( json_obj_set o `size` ( json_int sz ) )
                        : b _4 ( json_arr_push arr o )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ( string_free mdir )
    ( string_free rootS )
    : Json root ( json_obj_new )
    : b _r ( json_obj_set root `models` arr )
    : String txt ( json_stringify root )
    ( json_free root )
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `application/json` )
    ( response_set_body_str resp ( string_data txt ) )
    ( string_free txt )
    ^ resp
}

@ __api_show HttpRequest req Params ps → HttpResponse {
    : !Json JsonError pj ( __api_body_json req )
    ?? pj {
        F _ → { ^ ( response_text 400 `{"error":"invalid JSON body"}\n` ) }
        T j → {
            : String model ( __api_str j `model` `` )
            ( json_free j )
            : String rootS ( string_from g_api_root )
            : ?String rp ( nl_resolve rootS ( string_data model ) )
            ( string_free rootS )
            ?? rp {
                F → {
                    ( string_free model )
                    ^ ( response_text 404 `{"error":"model not found"}\n` )
                }
                T path → {
                    : Json o ( json_obj_new )
                    : b _1 ( json_obj_set o `model` ( json_str_lit ( string_data model ) ) )
                    ?? ( gguf_open ( string_data path ) ) {
                        T gg → {
                            : Json d ( json_obj_new )
                            : b _2 ( json_obj_set d `general.architecture` ( json_str_lit ( gguf_kv_str_or gg `general.architecture` `?` ) ) )
                            : b _3 ( json_obj_set d `llama.block_count` ( json_int ( gguf_kv_int_or gg `llama.block_count` 0 ) ) )
                            : b _4 ( json_obj_set d `llama.embedding_length` ( json_int ( gguf_kv_int_or gg `llama.embedding_length` 0 ) ) )
                            : b _5 ( json_obj_set d `llama.context_length` ( json_int ( gguf_kv_int_or gg `llama.context_length` 0 ) ) )
                            : b _6 ( json_obj_set d `tensors` ( json_int ( gguf_n_tensors gg ) ) )
                            : b _7 ( json_obj_set o `model_info` d )
                            ( gguf_close gg )
                        }
                        F e → { ( string_free e ) }
                    }
                    ( string_free path )
                    ( string_free model )
                    : String txt ( json_stringify o )
                    ( json_free o )
                    : HttpResponse resp ( response_new 200 )
                    ( response_set_header resp `Content-Type` `application/json` )
                    ( response_set_body_str resp ( string_data txt ) )
                    ( string_free txt )
                    ^ resp
                }
            }
        }
    }
}

@ __api_root HttpRequest req Params ps → HttpResponse {
    ^ ( response_text 200 `nurllama is running\n` )
}

// Serve on `host:port`. Single worker: the decode loop owns the device,
// so serialisation is structural rather than a lock.
@ api_serve String root s host i port → i {
    ( api_set_root root )
    : *HttpApp a ( http_app_new )
    ( http_app_workers a 1 )
    ( http_app_body_max a 4194304 )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_root rq ps ) } )
    ( http_app_get a `/api/tags` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_tags rq ps ) } )
    ( http_app_post a `/api/show` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_show rq ps ) } )
    ( http_app_stream a \ TcpConn c HttpRequest rq → b { ^ ( __api_stream_hook c rq ) } )
    : String msg ( string_from `nurllama serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )
    ( string_free msg )
    : i rc ( http_app_listen a host port )
    ( __api_unload )
    ^ rc
}
