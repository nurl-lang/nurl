// packages/embed/src/serve.nu — the embedding model as a service.
//
//   embed serve <model-dir> [--addr 0.0.0.0:8000] [--token T] [--maxseq N]
//
// The HTTP surface mirrors the reference FastAPI embedding service, so
// existing clients work unchanged:
//
//   POST /create_embedding   {"text": "..." | ["...", …], "normalize": true}
//                            {"texts": ["...", …]}          (same thing)
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
// token.
//
// Concurrency. One model on one device can run one forward at a time —
// that part is not a choice. Everything ELSE about a request is: reading
// the socket, parsing the JSON, tokenizing (the Unigram engine is
// read-only, so it is re-entrant), and serialising a few thousand floats
// back out, which for a batch is the larger half of the work. So the
// server is fiber-per-connection on the async runtime, and the forward
// is handed to ONE dedicated model thread over a queue — one job per
// REQUEST, so a request's texts reach the model together and run as a
// few padded batched forwards (embed_encode_batch), not text by text. A
// single worker used to mean a slow or idle client stalled every other
// client behind it; now it does not, and a batch's tokenizing and JSON
// overlap with another request's arithmetic.
//
// The forward runs on a thread rather than on the requesting fiber for
// a hard reason, not a stylistic one: async fibers get 64 KB stacks, and
// NVRTC — which the first forward at a new sequence length still calls —
// wants far more than that. Compiling a kernel on a fiber segfaults
// inside libnvrtc. One model thread with an ordinary 8 MB stack also
// keeps every CUDA call on one thread, which is where a context wants
// to be.
//
// Handlers are top-level functions over module globals, not closures —
// closure environments are manual in NURL and a server's handlers live
// for the process (same idiom as whisper/nurllama).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/cell.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `model.nu`

: ~ i g_em 0  // *Embed as an address (0 = not serving)
: ~ s g_em_token ``
: ~ s g_em_name ``
: ~ i g_em_reqs 0

// ── The model queue ───────────────────────────────────────────────────
//
// One job per waiting request, linked through the jobs themselves — a
// module global cannot hold a Vec (or a Mutex) built by a call, so the
// queue is two pointers and the synchronisation primitives are kept as
// the two words of each one's Cell. The submitting fiber owns the job
// and frees it once it has seen `done`; the model thread only fills it
// in.
: EmJob {
    i next
    ( Vec i ) ids  // flat tokens for the whole request
    ( Vec i ) offs  // B+1 offsets into ids
    ( Vec f ) out  // B*dim floats, written in place
    b normalize
    b done
    b ok
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

@ __em_qm → Mutex { ^ @ Mutex { @ Cell { # s g_q_m_ptr g_q_m_bytes } } }

@ __em_qreq → Cond { ^ @ Cond { @ Cell { # s g_q_req_ptr g_q_req_bytes } } }

@ __em_qdone → Cond { ^ @ Cond { @ Cell { # s g_q_done_ptr g_q_done_bytes } } }

// Run one request's forward — the WHOLE batch, one job — on the model
// thread and wait for it. `ids`, `offs` and `out` stay owned by the
// caller — the job only borrows them for the length of the call, which
// is exactly how long the caller blocks.
@ __em_submit ( Vec i ) ids ( Vec i ) offs ( Vec f ) out b normalize → b {
    ? != g_q_m_ptr 0 {} { ^ F }
    : *EmJob j # *EmJob ( nurl_alloc Z EmJob )
    = . j next 0
    = . j ids ids
    = . j offs offs
    = . j out out
    = . j normalize normalize
    = . j done F
    = . j ok F
    ( mutex_lock ( __em_qm ) )
    ? == g_q_tail 0 {
        = g_q_head # i j
        = g_q_tail # i j
    } {
        : *EmJob t # *EmJob g_q_tail
        = . t next # i j
        = g_q_tail # i j
    }
    ( cond_signal ( __em_qreq ) )
    ~ ! . j done { ( cond_wait ( __em_qdone ) ( __em_qm ) ) }
    ( mutex_unlock ( __em_qm ) )
    : b r . j ok
    ( nurl_free # *u j )
    ^ r
}

// The model thread: take jobs, run them, wake the waiter.
@ __em_model_loop → v {
    : *Embed e # *Embed g_em
    : ~ b run T
    ~ run {
        ( mutex_lock ( __em_qm ) )
        ~ & == g_q_head 0 ! g_q_stop { ( cond_wait ( __em_qreq ) ( __em_qm ) ) }
        ? == g_q_head 0 {
            ( mutex_unlock ( __em_qm ) )
            = run F
        } {
            : *EmJob j # *EmJob g_q_head
            = g_q_head . j next
            ? == g_q_head 0 { = g_q_tail 0 } {}
            ( mutex_unlock ( __em_qm ) )
            : b r ( embed_encode_batch e . j ids . j offs . j out . j normalize )
            ( mutex_lock ( __em_qm ) )
            = . j ok r
            = . j done T
            ( cond_broadcast ( __em_qdone ) )
            ( mutex_unlock ( __em_qm ) )
        }
    }
}

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

@ __em_free_texts ( Vec String ) texts → v {
    : ~ i k 0
    ~ < k ( vec_len [String] texts ) {
        ?? ( vec_get [String] texts k ) { T t → { ( string_free t ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] texts )
}

// Embed `texts` (owned Vec of owned Strings; freed here) → the response.
//
// Tokenizing is done outside the model lock — the Unigram engine only
// reads — and so is building the response, which for a batch of long
// vectors is thousands of float conversions. The lock covers exactly the
// device forward — and the whole request is ONE job: the model thread
// sees every text of the batch at once and runs them as a few padded
// batched forwards (embed_encode_batch), not one forward per text.
@ __em_run ( Vec String ) texts b normalize → HttpResponse {
    : *Embed e # *Embed g_em
    : i nt ( vec_len [String] texts )
    : i dim ( embed_dim e )
    : ~ b ok T
    // tokenize everything into one flat ids + offsets pair
    : ( Vec i ) ids ( vec_new [i] )
    : ( Vec i ) offs ( vec_new [i] )
    ( vec_push [i] offs 0 )
    : ~ i k 0
    ~ & ok < k nt {
        ?? ( vec_get [String] texts k ) {
            T t → {
                // per text into a fresh vec — embed_tokenize's maxseq
                // truncation is over the whole vec it is handed
                : ( Vec i ) tid ( vec_new [i] )
                ? ( embed_tokenize e ( string_data t ) tid ) {
                    : i tn ( vec_len [i] tid )
                    : ~ i j 0
                    ~ < j tn {
                        ?? ( vec_get [i] tid j ) { T x → { ( vec_push [i] ids x ) } F → {} }
                        = j + j 1
                    }
                    ( vec_push [i] offs ( vec_len [i] ids ) )
                } { = ok F }
                ( vec_free [i] tid )
            }
            F → { = ok F }
        }
        = k + k 1
    }
    : ( Vec f ) flat ( vec_with_cap [f] * nt dim )
    : ~ i z 0
    ~ < z * nt dim { ( vec_push [f] flat 0.0 ) = z + z 1 }
    ? ok { = ok ( __em_submit ids offs flat normalize ) } {}
    ( vec_free [i] ids )
    ( vec_free [i] offs )
    ( __em_free_texts texts )
    ? ok {} {
        ( vec_free [f] flat )
        ^ ( __em_jerr 500 `embedding failed` )
    }
    // one per served request, not per text in a batch — the queue mutex
    // is what makes it a count and not a race
    ( mutex_lock ( __em_qm ) )
    = g_em_reqs + g_em_reqs 1
    ( mutex_unlock ( __em_qm ) )
    // The body is built as ONE string, not a Json tree. A 64-text batch
    // is ~65k floats; as json_float nodes that is 65k allocations whose
    // frees each walk the panic-unwind journal the handler's panic→500
    // guard keeps — O(allocations²), measured at 3.8 s of a 3.9 s
    // request. The numbers go through the same nurl_str_float formatter
    // json_stringify uses, so the body is byte-identical to the tree's;
    // only the tree is gone. (json_str_lit still escapes the model
    // name — the one field that needs it.)
    : String bs ( string_from `{"embeddings":[` )
    = k 0
    ~ < k nt {
        ? > k 0 { ( string_push_char bs 44 ) } {}
        ( string_push_char bs 91 )
        : ~ i j 0
        ~ < j dim {
            ? > j 0 { ( string_push_char bs 44 ) } {}
            ?? ( vec_get [f] flat + * k dim j ) {
                T x → { ( string_push_float bs x ) }
                F → {}
            }
            = j + j 1
        }
        ( string_push_char bs 93 )
        = k + k 1
    }
    ( vec_free [f] flat )
    ( string_push_str bs `],"model":` )
    : Json mn ( json_str_lit g_em_name )
    : String mns ( json_stringify mn )
    ( json_free mn )
    ( string_push_str bs ( string_data mns ) )
    ( string_free mns )
    ( string_push_str bs `,"dimension":` )
    ( string_push_int bs dim )
    ( string_push_char bs 125 )
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( response_set_body_str r ( string_data bs ) )
    ( string_free bs )
    ^ r
}

// Collect the strings under `key` — a bare string or an array of them —
// into `texts`. Returns T when the key was there and yielded something.
@ __em_collect Json root s key ( Vec String ) texts → b {
    : ~ b have F
    ?? ( json_obj_get root key ) {
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
    ^ have
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
            // "text" is what this server has always taken; "texts" is
            // what the reference service (and this package's own
            // description) documents. Both, then — the plural first, so
            // a body carrying only it is not a 400.
            : ~ b have ( __em_collect root `texts` texts )
            ? ( __em_collect root `text` texts ) { = have T } {}
            : ~ b normalize T
            ?? ( json_obj_get root `normalize` ) {
                T nv → { = normalize ( json_as_bool nv ) }
                F → {}
            }
            ( json_free root )
            ? & have > ( vec_len [String] texts ) 0 {} {
                ( __em_free_texts texts )
                ^ ( __em_jerr 400 `no text provided — body must be {"text": "..."} or {"text": ["...", ...]}` )
            }
            ^ ( __em_run texts normalize )
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
    ^ ( __em_run texts normalize )
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
    : b _s7 ( json_obj_set o `max_seq` ( json_int ( embed_maxseq e ) ) )
    : b _s8 ( json_obj_set o `device_name` ( json_str_lit ( embed_device_name e ) ) )
    // What the device-buffer pool is holding, so "where did the VRAM go"
    // is a question the server answers instead of one an operator has to
    // reverse-engineer from nvidia-smi. Two plain integer loads while the
    // model thread may be allocating: a health report is allowed to be
    // one request stale, and nothing here dereferences the pool table.
    : b _s9 ( json_obj_set o `pool_blocks` ( json_int ( gk_pool_count ) ) )
    : b _s10 ( json_obj_set o `pool_idle_bytes` ( json_int ( gk_pool_idle_bytes ) ) )
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
    : Mutex qm ( mutex_new )
    : Cell qmc . qm c
    = g_q_m_ptr # i . qmc ptr
    = g_q_m_bytes . qmc bytes
    : Cond qreq ( cond_new )
    : Cell qrc . qreq c
    = g_q_req_ptr # i . qrc ptr
    = g_q_req_bytes . qrc bytes
    : Cond qdone ( cond_new )
    : Cell qdc . qdone c
    = g_q_done_ptr # i . qdc ptr
    = g_q_done_bytes . qdc bytes
    : ( @ v ) modelfn \ → v { ( __em_model_loop ) }
    ?? ( thread_spawn modelfn ) {
        T th → { ( thread_detach th ) }
        F _te → {
            ( nurl_eprint `embed: cannot start the model thread\n` )
            ^ 1
        }
    }

    : *HttpApp a ( http_app_new )
    // Fiber-per-connection: connections are cheap, and the one thing
    // that must not overlap — the forward — has its own lock (__em_run).
    // Hardening: bounded bodies (16 MB of JSON text is ~2000 full-length
    // documents), a head cap, slowloris idle cut, a per-request
    // deadline, and panic → 500 (never down the server).
    ( http_app_async a 0 )
    ( http_app_body_max a 16777216 )
    ( http_app_head_max a 65536 )
    ( http_app_idle_ms a 30000 )
    ( http_app_request_timeout a 600000 )
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
    ( mutex_lock qm )
    = g_q_stop T
    ( cond_broadcast qreq )
    ( mutex_unlock qm )
    = g_em 0
    ^ rc
}
