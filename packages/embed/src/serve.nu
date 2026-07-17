// packages/embed/src/serve.nu — the embedding model as a service.
//
//   embed serve <model-dir> [--addr 0.0.0.0:8000] [--token T] [--maxseq N]
//
// The HTTP surface mirrors the reference FastAPI embedding service, so
// existing clients work unchanged:
//
//   POST /create_embedding   {"text": "..." | ["...", …], "normalize": true}
//                            → {"embeddings": [[…]], "model": "…", "dimension": N}
//   GET  /create_embedding?text=…&normalize=true      (single text)
//   GET  /health             {"status":"healthy", "model", "model_loaded",
//                             "device": "cuda"|"cpu", …}
//   GET  /                   the same (a browser poking the port should
//                            learn something, not get a 404)
//
// Auth: no --token → open server (bind loopback!). With a token, requests
// must carry `Authorization: Bearer <t>` (or `?token=<t>` for clients that
// cannot set headers); the compare is constant-time over the configured
// token. A batch loops single-text forwards — exact per-row numerics, and
// the forward pass dominates at embedding sizes anyway.
//
// Handlers are top-level functions over module globals, not closures —
// closure environments are manual in NURL and a server's handlers live
// for the process (same idiom as whisper/nurllama).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `model.nu`

: ~ i g_em 0  // *Embed as an address (0 = not serving)
: ~ s g_em_token ``
: ~ s g_em_name ``
: ~ i g_em_reqs 0

// Constant-time-ish token compare (every byte of the CONFIGURED token is
// examined; a length mismatch folds in).
@ __em_tok_eq s got s want → b {
    : i lg ( nurl_str_len got )
    : i lw ( nurl_str_len want )
    : ~ i diff ^^ lg lw
    : ~ i k 0
    ~ < k lw {
        : i cw ( nurl_str_get want k )
        : i cg ? < k lg ( nurl_str_get got k ) 0
        = diff | diff ^^ cw cg
        = k + k 1
    }
    ^ == diff 0
}

@ __em_query_val s q s name → String {
    : String out ( string_new )
    : ( Vec UrlParam ) ps ( url_query_decode q )
    : ~ i k 0
    ~ < k ( vec_len [UrlParam] ps ) {
        ?? ( vec_get [UrlParam] ps k ) {
            T p → {
                ? & != 0 ( nurl_str_eq ( string_data . p key ) name ) == ( string_len out ) 0 {
                    ( string_push_str out ( string_data . p val ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( url_params_free ps )
    ^ out
}

@ __em_authed HttpRequest req → b {
    ? == ( nurl_str_len g_em_token ) 0 { ^ T } {}
    : ~ b ok F
    ?? ( header_get . req headers `authorization` ) {
        T hv → {
            : s h ( string_data hv )
            ? & > ( nurl_str_len h ) 7 != 0 ( nurl_str_starts h `Bearer ` ) {
                ? ( __em_tok_eq ( nurl_str_slice h 7 - ( nurl_str_len h ) 7 ) g_em_token ) { = ok T } {}
            } {}
            ( string_free hv )
        }
        F → {}
    }
    ? ok { ^ T } {}
    : String qt ( __em_query_val ( string_data . req query ) `token` )
    ? > ( string_len qt ) 0 {
        ? ( __em_tok_eq ( string_data qt ) g_em_token ) { = ok T } {}
    } {}
    ( string_free qt )
    ^ ok
}

@ __em_jerr i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    : b _s ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( json_free o )
    ^ r
}

// Embed `texts` (owned Vec of owned Strings; freed here) → the response.
@ __em_run ( Vec String ) texts b normalize → HttpResponse {
    : *Embed e # *Embed g_em
    : i nt ( vec_len [String] texts )
    : ~ b ok T
    : Json arr ( json_arr_new )
    : ( Vec f ) emb ( vec_new [f] )
    : ~ i k 0
    ~ & ok < k nt {
        ?? ( vec_get [String] texts k ) {
            T t → {
                ( vec_clear [f] emb )
                ? ( embed_encode e ( string_data t ) emb ) {
                    : Json row ( json_arr_new )
                    : ~ i j 0
                    : i dn ( vec_len [f] emb )
                    ~ < j dn {
                        ?? ( vec_get [f] emb j ) {
                            T x → { : b _p ( json_arr_push row ( json_float x ) ) }
                            F → {}
                        }
                        = j + j 1
                    }
                    : b _p2 ( json_arr_push arr row )
                } { = ok F }
            }
            F → { = ok F }
        }
        = k + k 1
    }
    ( vec_free [f] emb )
    = k 0
    ~ < k nt {
        ?? ( vec_get [String] texts k ) { T t → { ( string_free t ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] texts )
    ? ok {} {
        ( json_free arr )
        ^ ( __em_jerr 500 `embedding failed` )
    }
    = g_em_reqs + g_em_reqs 1
    : Json o ( json_obj_new )
    : b _s1 ( json_obj_set o `embeddings` arr )
    : b _s2 ( json_obj_set o `model` ( json_str_lit g_em_name ) )
    : b _s3 ( json_obj_set o `dimension` ( json_int ( embed_dim e ) ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// The temporary normalize override: flip, run, restore. The server is
// single-worker, so no other request can observe the flipped state.
@ __em_run_norm ( Vec String ) texts b normalize → HttpResponse {
    : *Embed e # *Embed g_em
    : EmbedCfg c . e cfg
    : b saved . c normalize
    ( embed_set_pooling e . c pool normalize )
    : HttpResponse r ( __em_run texts normalize )
    ( embed_set_pooling e . c pool saved )
    ^ r
}

@ __em_post HttpRequest req → HttpResponse {
    ? ( __em_authed req ) {} { ^ ( __em_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    // the body is raw bytes; JSON wants a NUL-terminated string
    : String bodys ( string_new )
    ( string_push_bytes bodys ( vec_data [u] . req body ) ( vec_len [u] . req body ) )
    : !Json JsonError parsed ( json_parse ( string_data bodys ) )
    ( string_free bodys )
    ?? parsed {
        T root → {
            : ( Vec String ) texts ( vec_new [String] )
            : ~ b have F
            ?? ( json_obj_get root `text` ) {
                T tv → {
                    ? ( json_is_str tv ) {
                        ( vec_push [String] texts ( string_from ( json_str_data tv ) ) )
                        = have T
                    } {
                        ? ( json_is_arr tv ) {
                            : i n ( json_arr_len tv )
                            : ~ i k 0
                            ~ < k n {
                                ?? ( json_arr_get tv k ) {
                                    T el → {
                                        ? ( json_is_str el ) {
                                            ( vec_push [String] texts ( string_from ( json_str_data el ) ) )
                                            = have T
                                        } {}
                                    }
                                    F → {}
                                }
                                = k + k 1
                            }
                        } {}
                    }
                }
                F → {}
            }
            : ~ b normalize T
            ?? ( json_obj_get root `normalize` ) {
                T nv → { = normalize ( json_as_bool nv ) }
                F → {}
            }
            ( json_free root )
            ? & have > ( vec_len [String] texts ) 0 {} {
                : ~ i k2 0
                ~ < k2 ( vec_len [String] texts ) {
                    ?? ( vec_get [String] texts k2 ) { T t → { ( string_free t ) } F → {} }
                    = k2 + k2 1
                }
                ( vec_free [String] texts )
                ^ ( __em_jerr 400 `no text provided — body must be {"text": "..."} or {"text": ["...", ...]}` )
            }
            ^ ( __em_run_norm texts normalize )
        }
        F je → {
            ^ ( __em_jerr 400 `request body is not valid JSON` )
        }
    }
}

@ __em_get HttpRequest req → HttpResponse {
    ? ( __em_authed req ) {} { ^ ( __em_jerr 401 `unauthorized — pass 'Authorization: Bearer <token>'` ) }
    : String txt ( __em_query_val ( string_data . req query ) `text` )
    ? > ( string_len txt ) 0 {} {
        ( string_free txt )
        ^ ( __em_jerr 400 `no text provided — GET /create_embedding?text=...` )
    }
    : String nq ( __em_query_val ( string_data . req query ) `normalize` )
    : b normalize ? != 0 ( nurl_str_eq ( string_data nq ) `false` ) { F } { T }
    ( string_free nq )
    : ( Vec String ) texts ( vec_new [String] )
    ( vec_push [String] texts txt )
    ^ ( __em_run_norm texts normalize )
}

@ __em_health HttpRequest req → HttpResponse {
    : *Embed e # *Embed g_em
    : Json o ( json_obj_new )
    : b _s1 ( json_obj_set o `status` ( json_str_lit `healthy` ) )
    : b _s2 ( json_obj_set o `model` ( json_str_lit g_em_name ) )
    : b _s3 ( json_obj_set o `model_loaded` ( json_bool ( embed_ok e ) ) )
    : b _s4 ( json_obj_set o `device` ( json_str_lit ( embed_backend e ) ) )
    : b _s5 ( json_obj_set o `dimension` ( json_int ( embed_dim e ) ) )
    : b _s6 ( json_obj_set o `requests` ( json_int g_em_reqs ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// Serve `e` (borrowed for the server's lifetime). Blocks until stopped.
@ embed_serve * Embed e s name s host i port s token → i {
    = g_em # i e
    ? > ( nurl_str_len g_em_token ) 0 { ( nurl_free g_em_token ) } {}
    = g_em_token ( strdup token )
    ? > ( nurl_str_len g_em_name ) 0 { ( nurl_free g_em_name ) } {}
    = g_em_name ( strdup name )

    : *HttpApp a ( http_app_new )
    // One forward runs one model on one device; a second concurrent
    // request would serialise on it anyway — a single worker is the
    // honest shape. Hardening: bounded bodies (16 MB of JSON text is
    // ~2000 full-length documents), a head cap, slowloris idle cut, a
    // per-request deadline, and panic → 500 (never down the server).
    ( http_app_workers a 1 )
    ( http_app_body_max a 16777216 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 30000 )
    ( http_app_request_timeout a 600000 )
    ( http_app_recover a T )
    ( http_app_post a `/create_embedding` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_post rq ) } )
    ( http_app_get a `/create_embedding` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_get rq ) } )
    ( http_app_get a `/health` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_health rq ) } )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __em_health rq ) } )

    : String msg ( string_from `embed serving on http://` )
    ( string_push_str msg host )
    ( string_push_char msg 58 )
    ( string_push_int msg port )
    ( string_push_str msg ` (POST /create_embedding, GET /health)` )
    ? == ( nurl_str_len token ) 0 { ( string_push_str msg ` — NO TOKEN, keep it on loopback` ) } {}
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )
    ( string_free msg )

    : i rc ( http_app_listen a host port )
    = g_em 0
    ^ rc
}
